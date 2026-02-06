#!/bin/bash
# Full pipeline: video -> 5 fps frames -> resize -> blur -> COLMAP (features, matching, sparse, dense)
# Usage: ./run.sh <project> [options]
#   --from-step STEP        Start from: video | images | images_resized | feature_extraction | feature_matching | sparse_reconstruction | dense_reconstruction
#   --blur-threshold N       Create filtered folder with images not below N; also save plot
#   --use-image-set SET      whole (images_resized) | filtered (images_resized_filtered). Default: whole
#   --skip-blur-if-plot      Skip blur step if blur_histogram.png already exists
#   --matcher TYPE          sequential | exhaustive (default: exhaustive)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
DATA_DIR="$SCRIPT_DIR/data"

FROM_STEP="video"
BLUR_THRESHOLD=""
MATCHER="exhaustive"
USE_IMAGE_SET="whole"
SKIP_BLUR_IF_PLOT=""

# Parse project (first non-option arg)
PROJECT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-step)
      FROM_STEP="$2"
      shift 2
      ;;
    --blur-threshold)
      BLUR_THRESHOLD="$2"
      shift 2
      ;;
    --use-image-set)
      USE_IMAGE_SET="$2"
      shift 2
      ;;
    --skip-blur-if-plot)
      SKIP_BLUR_IF_PLOT="1"
      shift
      ;;
    --matcher)
      MATCHER="$2"
      shift 2
      ;;
    *)
      if [[ -z "$PROJECT_ARG" ]]; then
        PROJECT_ARG="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PROJECT_ARG" ]]; then
  echo "Usage: $0 <project> [--from-step STEP] [--blur-threshold N] [--use-image-set whole|filtered] [--skip-blur-if-plot] [--matcher sequential|exhaustive]"
  exit 1
fi

if [[ "$PROJECT_ARG" == */* ]]; then
  PROJECT_DIR="$SCRIPT_DIR/$PROJECT_ARG"
else
  PROJECT_DIR="$DATA_DIR/$PROJECT_ARG"
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: project directory not found: $PROJECT_DIR"
  exit 1
fi

if [[ -f "$SCRIPT_DIR/venv/bin/activate" ]]; then
  source "$SCRIPT_DIR/venv/bin/activate"
fi

IMAGES_DIR="$PROJECT_DIR/images"
RESIZED_DIR="$PROJECT_DIR/images_resized"
FILTERED_DIR="$PROJECT_DIR/images_resized_filtered"

# Image dir for COLMAP feature extraction
if [[ "$USE_IMAGE_SET" == "filtered" ]]; then
  FEATURE_IMAGE_PATH="$FILTERED_DIR"
else
  FEATURE_IMAGE_PATH="$RESIZED_DIR"
fi

run_step_video() {
  local VIDEO
  VIDEO="$(find "$PROJECT_DIR" -maxdepth 1 -type f \( -name "*.mov" -o -name "*.mp4" \) | head -1)"
  if [[ -z "$VIDEO" ]]; then
    echo "Error: no .mov or .mp4 found in $PROJECT_DIR"
    exit 1
  fi
  mkdir -p "$IMAGES_DIR"
  rm -f "$IMAGES_DIR"/frame_*.jpg 2>/dev/null || true
  echo "=== 1. Sampling video to 5 fps ==="
  ffmpeg -y -i "$VIDEO" -vf fps=5 "$IMAGES_DIR/frame_%05d.jpg"
}

run_step_images() {
  run_step_video
}

run_step_resize() {
  echo "=== 2. Resizing images ==="
  cd "$PROJECT_DIR"
  python "$SRC_DIR/resize_imges.py" --input images --output images_resized
}

run_step_blur() {
  echo "=== 2b. Blur analysis (plot + optional filtered folder) ==="
  cd "$PROJECT_DIR"
  local extra=""
  [[ -n "$BLUR_THRESHOLD" ]] && extra="--threshold $BLUR_THRESHOLD --output-filtered-dir images_resized_filtered"
  [[ -n "$SKIP_BLUR_IF_PLOT" ]] && extra="$extra --skip-if-plot-exists"
  python "$SRC_DIR/blur_analysis.py" --input images_resized --output-plot "$PROJECT_DIR/blur_histogram.png" $extra
}

run_step_feature_extraction() {
  echo "=== 3. Feature extraction (COLMAP) — image_path=$FEATURE_IMAGE_PATH ==="
  cd "$PROJECT_DIR"
  IMAGE_PATH="$(basename "$FEATURE_IMAGE_PATH")"
  export IMAGE_PATH
  bash "$SRC_DIR/1_feature_extraction.sh"
}

run_step_feature_matching() {
  echo "=== 4. Feature matching (COLMAP) ==="
  cd "$PROJECT_DIR"
  export MATCHER
  bash "$SRC_DIR/2_feature_matching.sh"
}

run_step_sparse_reconstruction() {
  echo "=== 5. Sparse reconstruction (COLMAP) ==="
  cd "$PROJECT_DIR"
  bash "$SRC_DIR/3_sparce_reconstruction.sh"
}

run_step_dense_reconstruction() {
  echo "=== 6. Dense reconstruction (COLMAP) ==="
  cd "$PROJECT_DIR"
  bash "$SRC_DIR/4_dense_reconstruction.sh"
}

case "$FROM_STEP" in
  video)
    run_step_video
    run_step_resize
    run_step_blur
    run_step_feature_extraction
    run_step_feature_matching
    run_step_sparse_reconstruction
    run_step_dense_reconstruction
    ;;
  images)
    run_step_resize
    run_step_blur
    run_step_feature_extraction
    run_step_feature_matching
    run_step_sparse_reconstruction
    run_step_dense_reconstruction
    ;;
  images_resized)
    run_step_blur
    run_step_feature_extraction
    run_step_feature_matching
    run_step_sparse_reconstruction
    run_step_dense_reconstruction
    ;;
  feature_extraction)
    run_step_feature_extraction
    run_step_feature_matching
    run_step_sparse_reconstruction
    run_step_dense_reconstruction
    ;;
  feature_matching)
    run_step_feature_matching
    run_step_sparse_reconstruction
    run_step_dense_reconstruction
    ;;
  sparse_reconstruction)
    run_step_sparse_reconstruction
    run_step_dense_reconstruction
    ;;
  dense_reconstruction)
    run_step_dense_reconstruction
    ;;
  *)
    echo "Error: unknown --from-step: $FROM_STEP"
    exit 1
    ;;
esac

echo "Done. Sparse model: $PROJECT_DIR/sparse/ — Dense: $PROJECT_DIR/dense/"
