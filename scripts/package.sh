#!/usr/bin/env sh
# Packs the jar as dist/terrarium.love, with dist/SHA256SUMS beside it (#91):
#
#   sh scripts/package.sh            (HEAD)
#   sh scripts/package.sh v0.1.0     (any commit or tag)
#
# The .love is a git archive of one commit, so only what's committed ships:
# never an uncommitted edit, renders/ or a month's CSVs. Left out are the
# things only a developer runs or reads: tests/, CI, the claim tools, docs/,
# and the agents' settings and CLAUDE.md. The capture scripts (scripts/*.lua)
# stay, since --script loads them from inside the game. Easel checks the
# download against SHA256SUMS before it swaps the game on the frame.

cd "$(dirname "$0")/.." || exit 1
ref=${1:-HEAD}

mkdir -p dist
rm -f dist/terrarium.love dist/SHA256SUMS
git archive --format=zip -9 -o dist/terrarium.love "$ref" -- . \
    ':(exclude)tests' ':(exclude).github' ':(exclude).claude' \
    ':(exclude).gitignore' ':(exclude).gitattributes' ':(exclude)CLAUDE.md' \
    ':(exclude)scripts/issue*' ':(exclude)docs' || exit 1
# (the sed keeps Git Bash's binary-mode '*' out, so it reads as on Linux)
(cd dist && sha256sum terrarium.love | sed 's/ \*/  /' > SHA256SUMS) || exit 1

echo "packed $(git rev-parse --short "$ref") as dist/terrarium.love"
cat dist/SHA256SUMS
