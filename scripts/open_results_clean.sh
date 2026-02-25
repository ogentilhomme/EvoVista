#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"

PROJECT="${1:-}"
SCENE="${2:-0}"
OPEN_MESH="${OPEN_MESH:-auto}" # auto: open if present, 0: never, 1: force/presence warning

if [[ -z "$PROJECT" ]]; then
  echo "Usage: $0 <project> [scene_id]"
  echo "Example: $0 home 0"
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "Error: DISPLAY is not set. Start this from a graphical session."
  exit 1
fi

PROJECT_DIR="$DATA_DIR/$PROJECT"
SPARSE_DIR="$PROJECT_DIR/sparse/$SCENE"
FUSED_PLY="$PROJECT_DIR/dense/$SCENE/fused.ply"
MESH_PLY="$PROJECT_DIR/dense/$SCENE/house_mesh.ply"
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: project directory not found: $PROJECT_DIR"
  exit 1
fi

if [[ ! -d "$SPARSE_DIR" ]]; then
  echo "Warning: sparse directory not found: $SPARSE_DIR"
fi
if [[ ! -f "$FUSED_PLY" ]]; then
  echo "Warning: fused ply not found: $FUSED_PLY"
fi

if [[ ! -x /usr/bin/colmap ]]; then
  echo "Error: /usr/bin/colmap not found."
  exit 1
fi
if [[ ! -x /usr/bin/meshlab ]]; then
  echo "Error: /usr/bin/meshlab not found."
  exit 1
fi

run_clean_bg() {
  # Start GUI apps detached and with clean env to avoid Snap runtime conflicts.
  local name="$1"
  shift
  env -i \
    HOME="${HOME:-}" \
    USER="${USER:-}" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    DISPLAY="${DISPLAY:-}" \
    XAUTHORITY="${XAUTHORITY:-}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
    "$@" >/tmp/"$name".log 2>&1 &
}

echo "Opening COLMAP GUI (clean env)..."
# Import sparse model directly so partner can inspect poses/points immediately.
run_clean_bg "colmap_gui_${PROJECT}_${SCENE}" /usr/bin/colmap gui \
  --database_path "$PROJECT_DIR/database.db" \
  --image_path "$PROJECT_DIR/images" \
  --import_path "$SPARSE_DIR"

if [[ -f "$FUSED_PLY" ]]; then
  # Fused point cloud is the primary dense artifact to check reconstruction quality.
  echo "Opening fused cloud in MeshLab: $FUSED_PLY"
  run_clean_bg "meshlab_fused_${PROJECT}_${SCENE}" /usr/bin/meshlab "$FUSED_PLY"
fi

case "$OPEN_MESH" in
  auto)
    if [[ -f "$MESH_PLY" ]]; then
      echo "Opening mesh in MeshLab: $MESH_PLY"
      run_clean_bg "meshlab_mesh_${PROJECT}_${SCENE}" /usr/bin/meshlab "$MESH_PLY"
    fi
    ;;
  1)
    if [[ -f "$MESH_PLY" ]]; then
      echo "Opening mesh in MeshLab: $MESH_PLY"
      run_clean_bg "meshlab_mesh_${PROJECT}_${SCENE}" /usr/bin/meshlab "$MESH_PLY"
    else
      echo "Warning: OPEN_MESH=1 but mesh not found: $MESH_PLY"
    fi
    ;;
  0)
    ;;
  *)
    echo "Warning: invalid OPEN_MESH='$OPEN_MESH' (expected auto|0|1)."
    ;;
esac

if [[ -f "$MESH_PLY" ]]; then
  echo "Mesh available: $MESH_PLY"
else
  echo "Mesh not available yet: $MESH_PLY"
fi

echo "Done. Logs are in /tmp/colmap_gui_${PROJECT}_${SCENE}.log and /tmp/meshlab_*.log"
