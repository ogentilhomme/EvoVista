#!/bin/bash

mkdir sparse

colmap mapper \
  --database_path database.db \
  --image_path images \
  --output_path sparse