#!/bin/zsh
# Mall Makers asset batch. Per asset:
#   trellis-cli (TRELLIS.2, geometry res 1024, 1024 px textures, --dump-post)  -> dumps/<id>.trellisraw
#   raw2qtm3d.py                                                               -> dumps/<id>.qtm3d
#   QtMeshEditor generate3d via the QTMESH_TRELLIS2_IMPORT seam, --game-preset roblox-meshpart (keeps the
#   preset's triangle budget, 1024 px baked PBR)                                -> generated/<id>.glb
# A generation that makes no progress for STALL_MIN minutes (boxy full-voxel shapes at res 1024 on 24 GB)
# is killed and retried once at res 512 with the same 1024 px textures; the fallback is logged.
# Cutouts come from matte.py (BiRefNet 1024, the QtMeshEditor 'best' matting tier); the bake also passes
# --matting best so a cutout without alpha would get the same tier inside QtMeshEditor.
# Usage: gen_batch.sh [id ...]   (default: generation_order from source/manifest.json)
cd "$(dirname "$0")"
T=$HOME/trellis.cpp/build-arm64/trellis-cli
Q=/Applications/QtMeshEditor.app/Contents/MacOS/QtMeshEditor
RES=${RES:-1024}
STALL_MIN=${STALL_MIN:-45}
ids=("$@")
if [ ${#ids[@]} -eq 0 ]; then ids=($(python3 -c "import json;print(' '.join(json.load(open('source/manifest.json'))['generation_order']))")); fi
mkdir -p dumps generated logs
run_gen() { # $1 id, $2 res
  local id=$1 res=$2
  "$T" --image "cutout/$id.png" --dump-post "dumps/$id.trellisraw" --models $HOME/trellis.cpp/models --res $res --seed 42 --tex-res 1024 --model trellis > "logs/$id.dump.log" 2>&1 &
  local pid=$!
  local last=$(stat -f %z "logs/$id.dump.log") idle=0
  trap "kill $pid 2>/dev/null; exit 1" TERM INT
  while kill -0 $pid 2>/dev/null; do
    sleep 60
    local now=$(stat -f %z "logs/$id.dump.log")
    if [ "$now" = "$last" ]; then idle=$((idle+1)); else idle=0; last=$now; fi
    if [ $idle -ge $STALL_MIN ]; then echo "[stall] $id res=$res no log progress for ${STALL_MIN}m, killing"; kill $pid; sleep 5; kill -9 $pid 2>/dev/null; wait $pid 2>/dev/null; return 99; fi
  done
  wait $pid; return $?
}
for id in $ids; do
  preset=$(python3 -c "import json;print(json.load(open('source/manifest.json'))['generated']['$id']['preset'])")
  if [ -s "generated/$id.glb" ]; then echo "[skip] $id exists"; continue; fi
  start=$(date +%s)
  if [ ! -s "dumps/$id.trellisraw" ]; then
    echo "[gen] $id res=$RES $(date +%H:%M:%S)"
    run_gen $id $RES; rc=$?
    if [ $rc -eq 137 ] || [ $rc -eq 143 ]; then echo "[abort] $id killed (rc=$rc), stopping batch"; rm -f "dumps/$id.trellisraw"; exit 1; fi
    if [ $rc -ne 0 ]; then
      rm -f "dumps/$id.trellisraw"
      echo "[fallback] $id rc=$rc -> res 512 $(date +%H:%M:%S)"
      run_gen $id 512; rc=$?
      if [ $rc -ne 0 ]; then echo "[fail-gen] $id rc=$rc"; rm -f "dumps/$id.trellisraw"; continue; fi
      echo "$id" >> logs/res512_fallback.txt
    fi
  fi
  python3 raw2qtm3d.py "dumps/$id.trellisraw" "dumps/$id.qtm3d" > "logs/$id.conv.log" 2>&1 || { echo "[fail-conv] $id"; continue; }
  echo "[bake] $id preset=$preset $(date +%H:%M:%S)"
  QTMESH_TRELLIS2_IMPORT="dumps/$id.qtm3d" "$Q" generate3d "cutout/$id.png" -o "generated/$id.glb" --backend pixal3d --tex-res 1024 --game-preset $preset --matting best --seed 42 --no-source > "logs/$id.bake.log" 2>&1
  rc=$?
  echo "[done] $id rc=$rc $(( $(date +%s) - start ))s $(grep -oE 'game-ready: [0-9]+ -> [0-9]+ tris[^)]*\)?' logs/$id.bake.log | tail -1)"
  [ -s "generated/$id.glb" ] && rm -f "dumps/$id.trellisraw" "dumps/$id.qtm3d" "generated/${id}_source.qtm3d"
done
echo "[batch complete] $(date +%H:%M:%S)"
