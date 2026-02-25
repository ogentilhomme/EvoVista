#!/bin/bash

set -euo pipefail
# Enable bash trace only when explicitly requested from caller.
[[ "${DEBUG_TRACE:-0}" == "1" ]] && set -x

# IMAGE_PATH: directory for feature extraction (default images_resized)
# This script is meant to be called by run.sh (which provides run_colmap backend wrapper).
type run_colmap >/dev/null 2>&1 || {
  echo "Error: run_colmap not found. Launch via ./run.sh"
  exit 1
}

IMAGE_PATH="${IMAGE_PATH:-images_resized}"
run_colmap feature_extractor \
  --database_path database.db \
  --image_path "$IMAGE_PATH" \
  --ImageReader.single_camera 1
