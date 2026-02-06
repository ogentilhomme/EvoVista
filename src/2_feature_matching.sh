#!/bin/bash
# Use MATCHER=sequential or MATCHER=exhaustive (default)

MATCHER="${MATCHER:-exhaustive}"
colmap "${MATCHER}_matcher" \
  --database_path database.db