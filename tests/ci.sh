#!/usr/bin/env sh
# Everything CI checks, runnable at home too:
#
#   LOVE=lovec sh tests/ci.sh                          (from the repo root)
#   LOVE=... WINDOW="xvfb-run -a" sh tests/ci.sh       (also check a windowed jar)
#
# 1. The randomness lint.
# 2. The whole self-test, headless, but for the month.
# 3. The month (#27, the M3 gate): ten jars of 30 jar days each, one process
#    per seed, side by side (it's the slowest test by far, and the timed
#    tests in the self-test mustn't share the machine with it). Each writes
#    its genes, day by day, to month_<seed>.csv in the save directory.
# 4. The replay hash from two separate processes. Inside one process the
#    replay check can't see bugs that only differ between runs: a pairs()
#    order, a table address, the wall clock. Then once more with LuaJIT's
#    compiler off (--interpret), which must agree: a sum the interpreter and
#    the compiler work out differently (x ^ 2, #94) makes processes disagree.
# 5. With $WINDOW set, a jar opened in a real window and drawn as it runs, in
#    each style (#94), against one opened with none. They must hash the same,
#    because rendering never touches the sim.

cd "$(dirname "$0")/.." || exit 1
LOVE=${LOVE:-lovec}
SECONDS_OF_JAR=${SECONDS_OF_JAR:-300}
MONTH_SEEDS=${MONTH_SEEDS:-"20261018 1 2 3 4 5 6 7 8 9"} # (dev.lua's MONTH_SEEDS)
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
failed=0

hash_of() {
    "$@" | tee /dev/stderr | sed -n 's/^hash //p' | tr -d '\r'
}

echo "== randomness lint"
sh tests/check_random.sh || failed=1

echo "== self-test"
"$LOVE" . --selftest --skip month || failed=1

echo "== a month in the jar, $JOBS seeds at a time"
logs=$(mktemp -d) || exit 1
printf '%s\n' $MONTH_SEEDS | xargs -P "$JOBS" -I{} sh -c \
    '"$1" . --test month --seed "$2" > "$3/$2.log" 2>&1 || echo "$2" >> "$3/failed"' sh "$LOVE" {} "$logs"
for seed in $MONTH_SEEDS; do grep -v '^\[nav\]' "$logs/$seed.log"; done
if [ -s "$logs/failed" ]; then
    echo "month: FAIL seeds $(tr '\n' ' ' < "$logs/failed")"
    failed=1
fi
rm -rf "$logs"

echo "== replay across processes ($SECONDS_OF_JAR s of jar)"
a=$(hash_of "$LOVE" . --replay "$SECONDS_OF_JAR")
b=$(hash_of "$LOVE" . --replay "$SECONDS_OF_JAR")
if [ -n "$a" ] && [ "$a" = "$b" ]; then
    echo "replay: both processes hash $a"
else
    echo "replay: FAIL processes disagree ('$a' vs '$b')"
    failed=1
fi
i=$(hash_of "$LOVE" . --replay "$SECONDS_OF_JAR" --interpret)
if [ -n "$i" ] && [ "$i" = "$a" ]; then
    echo "replay: interpreted, it hashes $i too"
else
    echo "replay: FAIL interpreted ('$i') and compiled ('$a') disagree (core/fmath.lua)"
    failed=1
fi

if [ -n "${WINDOW:-}" ]; then
    echo "== a jar watched in a window, in every style, against a jar with none"
    h=$(hash_of "$LOVE" . --replay 60)
    for style in $("$LOVE" . --styles | tr -d '\r'); do
        w=$(hash_of $WINDOW "$LOVE" . --replay 60 --window --style "$style")
        if [ -n "$w" ] && [ "$w" = "$h" ]; then
            echo "window: watched in $style and unwatched both hash $w"
        else
            echo "window: FAIL watching in $style changed the jar ('$w' watched vs '$h' headless)"
            failed=1
        fi
    done
fi

[ "$failed" = 0 ] && echo "ci: all green"
exit $failed
