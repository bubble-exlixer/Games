#!/bin/bash
# Build the Windows play zip: exports DeadShift.pck and zips it with the launcher + readme.
#   GODOT=/path/to/Godot_v4.4.1-stable_linux.x86_64 tools/mkbuild.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${GODOT:-godot}"
OUT="$ROOT/build"
mkdir -p "$OUT/play"
(cd "$ROOT/DeadShift" && "$G" --headless --path . --export-pack "Windows Desktop" "$OUT/play/DeadShift.pck")
cp "$ROOT/tools/Play_DeadShift.bat" "$OUT/play/"
cp "$ROOT/tools/Play_README.txt" "$OUT/play/README.txt"
rm -f "$OUT/DeadShift_Play.zip"
(cd "$OUT/play" && zip -q -9 ../DeadShift_Play.zip *)
ls -la "$OUT/DeadShift_Play.zip"
