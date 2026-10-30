#!/usr/bin/env sh
# Packs the jar as dist/terrarium.love, with dist/SHA256SUMS beside it (#91):
#
#   sh scripts/package.sh            (HEAD)
#   sh scripts/package.sh v0.1.0     (any commit or tag)
#
# The .love is a git archive of one commit, so only what's committed ships:
# never an uncommitted edit, renders/ or a month's CSVs. Left out are the
# things only a developer runs or reads: tests/, CI, the claim tools, and
# the agents' settings and CLAUDE.md. The capture scripts (scripts/*.lua)
# stay, since --script loads them from inside the game. Easel checks the
# download against SHA256SUMS before it swaps the game on the frame.
#
# With LOVE_WIN set to an unzipped love-11.5-win64 folder, it also builds
# the Windows game (#34), dist/terrarium-win64.zip: the .love fused onto
# love.exe as Terrarium.exe, in a Terrarium/ folder with LÖVE's DLLs and
# its licence, which a fused game has to carry. SHA256SUMS lists both.
#
#   LOVE_WIN=~/love-11.5-win64 sh scripts/package.sh v0.1.0

cd "$(dirname "$0")/.." || exit 1
ref=${1:-HEAD}

mkdir -p dist
rm -f dist/terrarium.love dist/terrarium-win64.zip dist/SHA256SUMS
git archive --format=zip -9 -o dist/terrarium.love "$ref" -- . \
    ':(exclude)tests' ':(exclude).github' ':(exclude).claude' \
    ':(exclude).gitignore' ':(exclude).gitattributes' ':(exclude)CLAUDE.md' \
    ':(exclude)CHANGELOG.md' ':(exclude)scripts/issue*' || exit 1
echo "packed $(git rev-parse --short "$ref") as dist/terrarium.love"
sums=terrarium.love

if [ -n "$LOVE_WIN" ]; then
    [ -f "$LOVE_WIN/love.exe" ] || { echo "no love.exe in LOVE_WIN ($LOVE_WIN)" >&2; exit 1; }
    out=dist/win64/Terrarium
    rm -rf dist/win64 && mkdir -p "$out" || exit 1
    # A fused game is love.exe with the .love on its end: LÖVE finds the
    # zip there and runs it, and its saves go to %APPDATA%/terrarium
    cat "$LOVE_WIN/love.exe" dist/terrarium.love > "$out/Terrarium.exe" || exit 1
    cp "$LOVE_WIN"/*.dll "$LOVE_WIN/license.txt" "$out/" || exit 1
    zipped=$(cd dist && pwd)/terrarium-win64.zip
    if command -v zip > /dev/null; then
        (cd dist/win64 && zip -q -9 -r "$zipped" Terrarium) || exit 1
    else # (Git Bash has no zip; Python's makes the same folder)
        (cd dist/win64 && python -c 'import shutil, sys; shutil.make_archive(sys.argv[1][:-4], "zip", ".", "Terrarium")' \
            "$zipped") || exit 1
    fi
    rm -rf dist/win64
    echo "fused it onto $(basename "$LOVE_WIN")'s love.exe as dist/terrarium-win64.zip"
    sums="$sums terrarium-win64.zip"
fi

# (the sed keeps Git Bash's binary-mode '*' out, so it reads as on Linux)
(cd dist && sha256sum $sums | sed 's/ \*/  /' > SHA256SUMS) || exit 1
cat dist/SHA256SUMS
