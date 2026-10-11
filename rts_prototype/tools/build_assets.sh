#!/usr/bin/env bash
# Full asset pipeline: material textures -> 3D render -> sprite composition.
# Usage: GODOT=/path/to/godot tools/build_assets.sh   (run from rts_prototype/)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
RUN=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  RUN=(xvfb-run -a -s "-screen 0 1280x1024x24")
fi
python3 tools/gen_textures.py
"$GODOT" --headless --path . --import
"${RUN[@]}" "$GODOT" --path . --rendering-driver opengl3 --script res://tools/render_sprites.gd
python3 tools/compose_sprites.py
"$GODOT" --headless --path . --import
