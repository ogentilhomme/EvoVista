#!/bin/bash
# Run dense reconstruction for each scene in sparse/ (sparse/0, sparse/1, ...).
# Output: dense/0/, dense/1/, ... each with fused.ply (and optionally house_mesh.ply).

set -e

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

  colmap image_undistorter \
    --image_path images \
    --input_path "$sparse_dir" \
    --output_path "$dense_dir" \
    --output_type COLMAP

  colmap patch_match_stereo \
    --workspace_path "$dense_dir"

  colmap stereo_fusion \
    --workspace_path "$dense_dir" \
    --output_path "$dense_dir/fused.ply"

  if command -v meshlabserver &>/dev/null; then
    meshlabserver \
      -i "$dense_dir/fused.ply" \
      -o "$dense_dir/house_mesh.ply" \
      -s poisson.mlx
  else
    echo "meshlabserver not found — skipping Poisson mesh for scene $scene_name. Fused PLY: $dense_dir/fused.ply"
  fi
done

echo "Dense reconstruction done. Scenes in dense/<N>/ (fused.ply, optionally house_mesh.ply)."
