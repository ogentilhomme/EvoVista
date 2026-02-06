#!/bin/bash
# IMAGE_PATH: directory for feature extraction (default images_resized)

IMAGE_PATH="${IMAGE_PATH:-images_resized}"
colmap feature_extractor \
  --database_path database.db \
  --image_path "$IMAGE_PATH" \
  --ImageReader.single_camera 1