#!/bin/bash

set -euo pipefail
# Enable bash trace only when explicitly requested from caller.
[[ "${DEBUG_TRACE:-0}" == "1" ]] && set -x

# Use MATCHER=sequential or MATCHER=exhaustive (default)
# This script is meant to be called by run.sh (which provides run_colmap backend wrapper).
type run_colmap >/dev/null 2>&1 || {
  echo "Error: run_colmap not found. Launch via ./run.sh"
  exit 1
}

MATCHER="${MATCHER:-exhaustive}"
run_colmap "${MATCHER}_matcher" \
  --database_path database.db
