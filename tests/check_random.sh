#!/usr/bin/env sh
# All randomness comes from the jar's seeded streams in core/rng.lua (sim, look,
# scape, sound). This fails if any game code calls math.random or love.math.random
# directly, or makes a generator of its own outside core/rng.lua and the
# self-test. Comments are fine. lib/ is a vendored subtree and isn't checked:
# LoveLibs' audio noise uses math.random, which never shares state with the
# jar's streams.
#
#   sh tests/check_random.sh        (from the repo root; exits 1 on a hit)

cd "$(dirname "$0")/.." || exit 1

# file:line:code, with any line comment stripped first
code() {
    grep -rnE "$1" --include='*.lua' . |
        grep -v '^\./lib/' |
        sed -E 's/^([^:]*:[0-9]+:)(([^-]|-[^-])*)--.*$/\1\2/' |
        grep -E "$1"
}

hits=$(code 'math\.random(seed)?[^A-Za-z_]')
gens=$(code 'newRandomGenerator' | grep -vE '^\./(core/rng|dev)\.lua:')

if [ -n "$hits$gens" ]; then
    echo "Direct randomness outside core/rng.lua (draw from rng.sim, rng.look, rng.scape or rng.sound):"
    [ -n "$hits" ] && echo "$hits"
    [ -n "$gens" ] && echo "$gens"
    exit 1
fi
echo "randomness: every draw goes through core/rng.lua"
