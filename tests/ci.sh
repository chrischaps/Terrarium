#!/usr/bin/env sh
# Everything CI checks, runnable at home too:
#
#   LOVE=lovec sh tests/ci.sh                          (from the repo root)
#   LOVE=... WINDOW="xvfb-run -a" sh tests/ci.sh       (also check a windowed jar)
#   GAME=dist/terrarium.love sh tests/ci.sh            (check the packed game, #91)
#
# 1. The randomness lint.
# 2. The whole self-test, headless, but for the month.
# 3. The month (#27, the M3 gate): ten jars of 30 jar days each, one process
#    per seed, side by side (it's the slowest test by far, and the timed
#    tests in the self-test mustn't share the machine with it). Each writes
#    its genes, day by day, to month_<seed>.csv in the save directory.
# 4. The replay hash from two separate processes. Inside one process the
#    replay check can't see bugs that only differ between runs: a pairs()
#    order, a table address, the wall clock. And the jar's book (#30) the
#    same way: one process runs a jar, writes its book and runs on, another
#    reads the book and runs on, and they must end on the same hash. Inside
#    one process a book can't show it kept what a new one doesn't have.
# 5. With $WINDOW set, a jar opened in a real window against one opened with
#    none. They must hash the same, because rendering never touches the sim.
#    And the Pi frame's mode (#90), started and stopped the way its launcher
#    does: --frame, then SIGTERM, which must quit through love.quit and leave
#    the launcher's thumb in $EASEL_DATA, and the jar's book beside it. Started
#    again, the frame reads the book back and goes on where it was.

cd "$(dirname "$0")/.." || exit 1
LOVE=${LOVE:-lovec}
GAME=${GAME:-.} # what LÖVE runs; the lint always reads the source
SECONDS_OF_JAR=${SECONDS_OF_JAR:-300}
BOOK_SECONDS=${BOOK_SECONDS:-3600} # of 900-second days: eggs, hatchlings, elders and the first deaths
MONTH_SEEDS=${MONTH_SEEDS:-"20261018 1 2 3 4 5 6 7 8 9"} # (dev.lua's MONTH_SEEDS)
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
failed=0

hash_of() {
    "$@" | tee /dev/stderr | sed -n 's/^hash //p' | tr -d '\r'
}

echo "== randomness lint"
sh tests/check_random.sh || failed=1

echo "== self-test"
"$LOVE" "$GAME" --selftest --skip month || failed=1

echo "== a month in the jar, $JOBS seeds at a time"
logs=$(mktemp -d) || exit 1
printf '%s\n' $MONTH_SEEDS | xargs -P "$JOBS" -I{} sh -c \
    '"$1" "$4" --test month --seed "$2" > "$3/$2.log" 2>&1 || echo "$2" >> "$3/failed"' sh "$LOVE" {} "$logs" "$GAME"
for seed in $MONTH_SEEDS; do grep -v '^\[nav\]' "$logs/$seed.log"; done
if [ -s "$logs/failed" ]; then
    echo "month: FAIL seeds $(tr '\n' ' ' < "$logs/failed")"
    failed=1
fi
rm -rf "$logs"

echo "== replay across processes ($SECONDS_OF_JAR s of jar)"
a=$(hash_of "$LOVE" "$GAME" --replay "$SECONDS_OF_JAR")
b=$(hash_of "$LOVE" "$GAME" --replay "$SECONDS_OF_JAR")
if [ -n "$a" ] && [ "$a" = "$b" ]; then
    echo "replay: both processes hash $a"
else
    echo "replay: FAIL processes disagree ('$a' vs '$b')"
    failed=1
fi

echo "== the jar's book across processes ($BOOK_SECONDS s of jar, #30)"
book=$(mktemp -d) || exit 1
file="$book/jar.book"
if command -v cygpath > /dev/null 2>&1; then file=$(cygpath -m "$file"); fi # (LÖVE on Windows wants C:/...)
a=$(hash_of "$LOVE" "$GAME" --keep "$BOOK_SECONDS" "$file" --day 900 --hour lampon)
b=$(hash_of "$LOVE" "$GAME" --resume "$file")
if [ -n "$a" ] && [ "$a" != "-" ] && [ "$a" = "$b" ]; then
    echo "book: written and read back in another process, both hash $a"
else
    echo "book: FAIL the jar read back went another way ('$a' written vs '$b' read)"
    failed=1
fi
rm -rf "$book"

if [ -n "${WINDOW:-}" ]; then
    echo "== a jar in a window against a jar with none"
    w=$(hash_of $WINDOW "$LOVE" "$GAME" --replay 60 --window)
    h=$(hash_of "$LOVE" "$GAME" --replay 60)
    if [ -n "$w" ] && [ "$w" = "$h" ]; then
        echo "window: windowed and headless both hash $w"
    else
        echo "window: FAIL rendering changed the jar ('$w' windowed vs '$h' headless)"
        failed=1
    fi

    echo "== the frame, ended as Easel ends it (#90)"
    easel=$(mktemp -d) || exit 1
    EASEL_DATA="$easel" $WINDOW sh -c '
        "$1" . --frame > "$2/log" 2>&1 &
        pid=$!
        i=0
        until grep -q "^\[frame\] [0-9]" "$2/log" || [ $i -ge 240 ]; do sleep 0.5; i=$((i + 1)); done
        sleep 3
        kill -TERM $pid
        wait $pid' sh "$LOVE" "$easel"
    status=$?
    cat "$easel/log"
    if [ "$status" = 0 ] && head -c 4 "$easel/thumb.png" 2>/dev/null | grep -q PNG; then
        echo "frame: SIGTERM quit cleanly and left Easel its thumb"
    else
        echo "frame: FAIL SIGTERM exited $status, thumb $(ls "$easel")"
        failed=1
    fi
    if head -c 15 "$easel/jar.book" 2>/dev/null | grep -q '^terrarium book'; then
        mv "$easel/log" "$easel/first.log"
        EASEL_DATA="$easel" $WINDOW sh -c '
            "$1" . --frame > "$2/log" 2>&1 &
            pid=$!
            i=0
            until grep -q "^\[frame\] [0-9]" "$2/log" || [ $i -ge 240 ]; do sleep 0.5; i=$((i + 1)); done
            kill -TERM $pid
            wait $pid' sh "$LOVE" "$easel"
        cat "$easel/log"
        if grep -q '^\[book\] resumed .*(as it was written)' "$easel/log"; then
            echo "frame: started again, it read its book back and went on"
        else
            echo "frame: FAIL started again, it didn't go on from its book"
            failed=1
        fi
    else
        echo "frame: FAIL SIGTERM left no book in $EASEL_DATA ($(ls "$easel"))"
        failed=1
    fi
    rm -rf "$easel"
fi

[ "$failed" = 0 ] && echo "ci: all green"
exit $failed
