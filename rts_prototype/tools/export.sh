#!/usr/bin/env bash
# Builds standalone Windows and Linux releases into build/ and zips them.
# Usage: GODOT=/path/to/godot tools/export.sh   (run from rts_prototype/)
# Requires Godot 4.3+ and matching export templates (Editor > Manage Export Templates).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
rm -rf build
mkdir -p build/windows build/linux
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/MiniCraft.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/MiniCraft.x86_64
chmod +x build/linux/MiniCraft.x86_64
(cd build/windows && zip -q ../MiniCraft_Windows.zip MiniCraft.exe)
(cd build/linux && zip -q ../MiniCraft_Linux.zip MiniCraft.x86_64)
ls -lh build/*.zip
