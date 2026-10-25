#!/bin/bash
# usage: ./run.sh [glb] [az_step=10] [res=1024]
set -e; cd "$(dirname "$0")"
GLB=${1:-src/model.glb}; STEP=${2:-10}; RES=${3:-1024}; BL=${BLENDER:-/workspace/tools/blender-4.2.3-linux-x64/blender}
python3 extract_textures.py "$GLB" textures
OUT=out/views_${STEP}deg_${RES}
"$BL" -b -P render_views.py -- "$GLB" "$OUT" "$STEP" "$RES"
python3 contact.py "$OUT" "$OUT/contact_sheet.png"
