#!/usr/bin/env sh
# Everything CI checks, runnable at home too:
#
#   LOVE=lovec sh tests/ci.sh                          (from the repo root)
#   LOVE=... WINDOW="xvfb-run -a" sh tests/ci.sh       (also check a windowed jar)
#
# 1. The randomness lint.
# 2. The whole self-test, headless.
# 3. The replay hash from two separate processes. Inside one process the
#    replay check can't see bugs that only differ between runs: a pairs()
#    order, a table address, the wall clock.
# 4. With $WINDOW set, a jar opened in a real window against one opened with
#    none. They must hash the same, because rendering never touches the sim.

cd "$(dirname "$0")/.." || exit 1
LOVE=${LOVE:-lovec}
SECONDS_OF_JAR=${SECONDS_OF_JAR:-300}
failed=0

hash_of() {
    "$@" | tee /dev/stderr | sed -n 's/^hash //p' | tr -d '\r'
}

echo "== randomness lint"
sh tests/check_random.sh || failed=1

echo "== self-test"
"$LOVE" . --selftest || failed=1

echo "== replay across processes ($SECONDS_OF_JAR s of jar)"
a=$(hash_of "$LOVE" . --replay "$SECONDS_OF_JAR")
b=$(hash_of "$LOVE" . --replay "$SECONDS_OF_JAR")
if [ -n "$a" ] && [ "$a" = "$b" ]; then
    echo "replay: both processes hash $a"
else
    echo "replay: FAIL processes disagree ('$a' vs '$b')"
    failed=1
fi

if [ -n "${WINDOW:-}" ]; then
    echo "== a jar in a window against a jar with none"
    w=$(hash_of $WINDOW "$LOVE" . --replay 60 --window)
    h=$(hash_of "$LOVE" . --replay 60)
    if [ -n "$w" ] && [ "$w" = "$h" ]; then
        echo "window: windowed and headless both hash $w"
    else
        echo "window: FAIL rendering changed the jar ('$w' windowed vs '$h' headless)"
        failed=1
    fi
fi

[ "$failed" = 0 ] && echo "ci: all green"
exit $failed
