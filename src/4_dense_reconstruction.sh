#!/bin/bash

set -euo pipefail
# Enable bash trace only when explicitly requested from caller.
[[ "${DEBUG_TRACE:-0}" == "1" ]] && set -x

# This script is meant to be called by run.sh (which provides run_colmap backend wrapper).
type run_colmap >/dev/null 2>&1 || {
  echo "Error: run_colmap not found. Launch via ./run.sh"
  exit 1
}

# Run dense reconstruction for each scene in sparse/ (sparse/0, sparse/1, ...).
# Output: dense/0/, dense/1/, ... each with fused.ply (and optionally house_mesh.ply).

for sparse_dir in sparse/*/; do
  # sparse_dir is e.g. "sparse/0/" or "sparse/1/"
  [[ -d "$sparse_dir" ]] || continue
  scene="${sparse_dir%/}"   # sparse/0
  scene_name="${scene#sparse/}"  # 0
  # Require COLMAP model files
  [[ -f "$sparse_dir/cameras.bin" || -f "$sparse_dir/cameras.txt" ]] || continue

  echo "=== Dense reconstruction for scene $scene_name ($sparse_dir) ==="
  dense_dir="dense/$scene_name"
  mkdir -p "$dense_dir"

  # Undistort + PatchMatch + Fusion are the standard COLMAP dense pipeline.
  run_colmap image_undistorter \
    --image_path images \
    --input_path "$sparse_dir" \
    --output_path "$dense_dir" \
    --output_type COLMAP

  run_colmap patch_match_stereo \
    --workspace_path "$dense_dir"

  run_colmap stereo_fusion \
    --workspace_path "$dense_dir" \
    --output_path "$dense_dir/fused.ply"

  if command -v meshlabserver &>/dev/null; then
    # Optional mesh generation. Not required when only fused point cloud is needed.
    meshlabserver \
      -i "$dense_dir/fused.ply" \
      -o "$dense_dir/house_mesh.ply" \
      -s poisson.mlx
  else
    echo "meshlabserver not found — skipping Poisson mesh for scene $scene_name. Fused PLY: $dense_dir/fused.ply"
  fi
done

echo "Dense reconstruction done. Scenes in dense/<N>/ (fused.ply, optionally house_mesh.ply)."
