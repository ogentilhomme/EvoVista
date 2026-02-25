#!/bin/bash
# Full pipeline: video -> 5 fps frames -> resize -> blur -> COLMAP (features, matching, sparse, dense)
# Usage: ./run.sh <project> [options]
#   --from-step STEP        Start from: video | images | images_resized | feature_extraction | feature_matching | sparse_reconstruction | dense_reconstruction
#   --blur-threshold N       Create filtered folder with images not below N; also save plot
#   --use-image-set SET      whole (images_resized) | filtered (images_resized_filtered). Default: whole
#   --skip-blur-if-plot      Skip blur step if blur_histogram.png already exists
#   --matcher TYPE          sequential | exhaustive (default: exhaustive)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
DATA_DIR="$SCRIPT_DIR/data"

FROM_STEP="video"
BLUR_THRESHOLD=""
MATCHER="exhaustive"
USE_IMAGE_SET="whole"
SKIP_BLUR_IF_PLOT=""
# Terminal verbosity control:
# - PRETTY_LOG=1: compact progress in terminal + full raw log on disk
# - PRETTY_LOG=0: print full command output directly
PRETTY_LOG="${PRETTY_LOG:-1}" # 1: filter verbose COLMAP logs in terminal, keep raw log on disk
# Auto-open COLMAP+fused viewer at the end of a successful run (GUI sessions only).
AUTO_OPEN_RESULTS="${AUTO_OPEN_RESULTS:-1}" # 1: open COLMAP+fused at end (GUI session only)

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

RUN_TS="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
# Always keep one raw timestamped log per run for post-mortem/debug.
RAW_LOG_FILE="$LOG_DIR/pipeline_${RUN_TS}.log"
STEP_SUMMARY=()

format_duration() {
  local total="$1"
  local h=$((total / 3600))
  local m=$(((total % 3600) / 60))
  local s=$((total % 60))
  printf "%02dh:%02dm:%02ds" "$h" "$m" "$s"
}

filter_colmap_logs() {
  # Keep only actionable progress/errors for COLMAP in terminal output.
  awk '
    /Processed file \[[0-9]+\/[0-9]+\]/ { print; fflush(); next }
    /Processing view [0-9]+ \/ [0-9]+/   { print; fflush(); next }
    /Elapsed time:/                       { print; fflush(); next }
    /WARNING|Warning|ERROR|Error|Failed|Check failed|symbol lookup error/ { print; fflush(); next }
  '
}

run_and_log() {
  local mode="$1"
  shift
  # COLMAP output can be very verbose; keep full output in RAW_LOG_FILE either way.
  if [[ "$mode" == "colmap" && "$PRETTY_LOG" == "1" ]]; then
    "$@" 2>&1 | tee -a "$RAW_LOG_FILE" | filter_colmap_logs
  else
    "$@" 2>&1 | tee -a "$RAW_LOG_FILE"
  fi
}

run_timed_step() {
  # Wrapper used by the main pipeline to produce per-step timings.
  local title="$1"
  local fn="$2"
  local start end dur
  start="$(date +%s)"
  echo
  echo ">>> START: $title ($(date '+%H:%M:%S'))"
  if "$fn"; then
    end="$(date +%s)"
    dur=$((end - start))
    STEP_SUMMARY+=("$title|$dur")
    echo ">>> DONE:  $title in $(format_duration "$dur")"
  else
    end="$(date +%s)"
    dur=$((end - start))
    echo ">>> FAIL:  $title after $(format_duration "$dur")"
    return 1
  fi
}

detect_scene_id_for_open() {
  # Prefer latest dense scene, fallback to latest sparse scene.
  # Useful when mapper generated multiple disconnected components (0, 1, ...).
  if [[ -d "$PROJECT_DIR/dense" ]]; then
    local latest_dense
    latest_dense="$(find "$PROJECT_DIR/dense" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')"
    if [[ -n "${latest_dense:-}" ]]; then
      echo "$latest_dense"
      return 0
    fi
  fi
  if [[ -d "$PROJECT_DIR/sparse" ]]; then
    local latest_sparse
    latest_sparse="$(find "$PROJECT_DIR/sparse" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')"
    if [[ -n "${latest_sparse:-}" ]]; then
      echo "$latest_sparse"
      return 0
    fi
  fi
  return 1
}

auto_open_results_if_configured() {
  # Non-blocking convenience step: do not fail pipeline on viewer issues.
  [[ "$AUTO_OPEN_RESULTS" == "1" ]] || return 0
  [[ -n "${DISPLAY:-}" ]] || {
    echo "Auto-open skipped: no DISPLAY in environment."
    return 0
  }

  local helper="$SCRIPT_DIR/scripts/open_results_clean.sh"
  [[ -x "$helper" ]] || {
    echo "Auto-open skipped: helper not executable: $helper"
    return 0
  }

  # Helper expects a project name under data/; skip custom absolute/relative project paths.
  if [[ "$PROJECT_DIR" != "$DATA_DIR/"* ]]; then
    echo "Auto-open skipped: project outside data/ ($PROJECT_DIR)."
    return 0
  fi

  local project_name scene_id
  project_name="$(basename "$PROJECT_DIR")"
  scene_id="$(detect_scene_id_for_open || true)"
  if [[ -z "${scene_id:-}" ]]; then
    echo "Auto-open skipped: no sparse/dense scene found."
    return 0
  fi

  echo "Auto-open results: project=$project_name scene=$scene_id"
  "$helper" "$project_name" "$scene_id" || true
}

# COLMAP backend: auto (default), local, or docker
# auto = local only if explicit CUDA support is detected; else docker fallback.
COLMAP_BACKEND="${COLMAP_BACKEND:-auto}" # auto | local | docker
COLMAP_IMAGE="${COLMAP_IMAGE:-colmap/colmap:latest}"
COLMAP_GPU_FLAGS="${COLMAP_GPU_FLAGS:---gpus all}"

docker_is_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

local_colmap_has_cuda() {
  # Strict detection: only trust explicit build info from `colmap version`.
  command -v colmap >/dev/null 2>&1 || return 1
  local version_out
  version_out="$(colmap version 2>&1 || true)"
  [[ -n "$version_out" ]] || return 1

  # Prefer explicit signal from COLMAP build string.
  if echo "$version_out" | grep -Eqi 'without[[:space:]]+cuda'; then
    return 1
  fi
  if echo "$version_out" | grep -Eqi 'with[[:space:]]+cuda|cuda[[:space:]]+enabled'; then
    return 0
  fi
  return 1
}

resolve_colmap_backend() {
  case "$COLMAP_BACKEND" in
    auto)
      if local_colmap_has_cuda; then
        COLMAP_BACKEND="local"
        echo "COLMAP backend: local (CUDA detected)."
      elif docker_is_available; then
        COLMAP_BACKEND="docker"
        echo "COLMAP backend: docker (local CUDA not detected)."
      else
        echo "Error: local COLMAP with CUDA not detected and Docker is unavailable."
        echo "Install CUDA-enabled COLMAP, start Docker, or set COLMAP_BACKEND explicitly."
        exit 1
      fi
      ;;
    local)
      if ! command -v colmap >/dev/null 2>&1; then
        echo "Error: COLMAP_BACKEND=local but 'colmap' command is not available."
        exit 1
      fi
      ;;
    docker)
      if ! docker_is_available; then
        echo "Error: COLMAP_BACKEND=docker but Docker is unavailable."
        exit 1
      fi
      ;;
    *)
      echo "Error: invalid COLMAP_BACKEND='$COLMAP_BACKEND' (expected auto|local|docker)."
      exit 1
      ;;
  esac
}

run_colmap() {
  # Single entry point for all COLMAP commands (local or docker backend).
  if [[ "${COLMAP_BACKEND}" == "local" ]]; then
    run_and_log colmap colmap "$@"
    return
  fi

  # Steps run after cd "$PROJECT_DIR"; keep container wd aligned with host project dir.
  # This removes any hardcoded project name in docker working directory.
  local host_project="$PWD"
  if [[ "$host_project" != "$SCRIPT_DIR/"* ]]; then
    echo "Error: project path must be inside $SCRIPT_DIR"
    return 1
  fi
  local rel="${host_project#$SCRIPT_DIR}"
  local container_wd="/workspace${rel}"

  run_and_log colmap docker run --rm ${COLMAP_GPU_FLAGS} \
    --user "$(id -u):$(id -g)" \
    -v "${SCRIPT_DIR}:/workspace" \
    -w "${container_wd}" \
    "${COLMAP_IMAGE}" \
    colmap "$@"
}
export -f run_colmap
# run_colmap depends on these logging helpers when called from child shells.
export -f run_and_log
export -f filter_colmap_logs
# Export runtime config so child bash scripts (src/*.sh) can call run_colmap safely.
export SCRIPT_DIR COLMAP_BACKEND COLMAP_IMAGE COLMAP_GPU_FLAGS PRETTY_LOG RAW_LOG_FILE

if [[ -f "$SCRIPT_DIR/venv/bin/activate" ]]; then
  source "$SCRIPT_DIR/venv/bin/activate"
fi
resolve_colmap_backend
echo "Run log file: $RAW_LOG_FILE"

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
  run_and_log plain ffmpeg -y -i "$VIDEO" -vf fps=5 "$IMAGES_DIR/frame_%05d.jpg"
}

run_step_images() {
  run_step_video
}

run_step_resize() {
  echo "=== 2. Resizing images ==="
  cd "$PROJECT_DIR"
  run_and_log plain python "$SRC_DIR/resize_imges.py" --input images --output images_resized
}

run_step_blur() {
  echo "=== 2b. Blur analysis (plot + optional filtered folder) ==="
  cd "$PROJECT_DIR"
  local extra=""
  [[ -n "$BLUR_THRESHOLD" ]] && extra="--threshold $BLUR_THRESHOLD --output-filtered-dir images_resized_filtered"
  [[ -n "$SKIP_BLUR_IF_PLOT" ]] && extra="$extra --skip-if-plot-exists"
  run_and_log plain python "$SRC_DIR/blur_analysis.py" --input images_resized --output-plot "$PROJECT_DIR/blur_histogram.png" $extra
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
    run_timed_step "video_sampling" run_step_video
    run_timed_step "resize_images" run_step_resize
    run_timed_step "blur_analysis" run_step_blur
    run_timed_step "feature_extraction" run_step_feature_extraction
    run_timed_step "feature_matching" run_step_feature_matching
    run_timed_step "sparse_reconstruction" run_step_sparse_reconstruction
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  images)
    run_timed_step "resize_images" run_step_resize
    run_timed_step "blur_analysis" run_step_blur
    run_timed_step "feature_extraction" run_step_feature_extraction
    run_timed_step "feature_matching" run_step_feature_matching
    run_timed_step "sparse_reconstruction" run_step_sparse_reconstruction
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  images_resized)
    run_timed_step "blur_analysis" run_step_blur
    run_timed_step "feature_extraction" run_step_feature_extraction
    run_timed_step "feature_matching" run_step_feature_matching
    run_timed_step "sparse_reconstruction" run_step_sparse_reconstruction
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  feature_extraction)
    run_timed_step "feature_extraction" run_step_feature_extraction
    run_timed_step "feature_matching" run_step_feature_matching
    run_timed_step "sparse_reconstruction" run_step_sparse_reconstruction
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  feature_matching)
    run_timed_step "feature_matching" run_step_feature_matching
    run_timed_step "sparse_reconstruction" run_step_sparse_reconstruction
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  sparse_reconstruction)
    run_timed_step "sparse_reconstruction" run_step_sparse_reconstruction
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  dense_reconstruction)
    run_timed_step "dense_reconstruction" run_step_dense_reconstruction
    ;;
  *)
    echo "Error: unknown --from-step: $FROM_STEP"
    exit 1
    ;;
esac

if [[ "${#STEP_SUMMARY[@]}" -gt 0 ]]; then
  echo
  echo "===== Step Summary ====="
  total=0
  for item in "${STEP_SUMMARY[@]}"; do
    name="${item%%|*}"
    sec="${item##*|}"
    total=$((total + sec))
    printf " - %s: %s\n" "$name" "$(format_duration "$sec")"
  done
  echo "Total pipeline time: $(format_duration "$total")"
  echo "Raw log: $RAW_LOG_FILE"
fi

echo "Done. Sparse model: $PROJECT_DIR/sparse/ — Dense: $PROJECT_DIR/dense/"
auto_open_results_if_configured
