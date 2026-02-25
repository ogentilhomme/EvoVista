#!/usr/bin/env bash

set -euo pipefail

COLMAP_BIN="${COLMAP_BIN:-/usr/bin/colmap}"

if [[ ! -x "$COLMAP_BIN" ]]; then
  echo "Error: COLMAP binary not found or not executable: $COLMAP_BIN"
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "Error: DISPLAY is not set. Start this from a graphical session."
  exit 1
fi

# Launch COLMAP GUI with a minimal clean env.
# This avoids Snap-injected runtime libs that can trigger symbol lookup errors.
env -i \
  HOME="${HOME:-}" \
  USER="${USER:-}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  DISPLAY="${DISPLAY:-}" \
  XAUTHORITY="${XAUTHORITY:-}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
  "$COLMAP_BIN" gui
