# 3DRecon

Pipeline for 3D reconstruction from video or images: sample frames, resize, blur analysis, then [COLMAP](https://colmap.github.io/) for feature extraction, matching, sparse and dense reconstruction.

## Requirements

- **Python 3.9+** (for resize, blur analysis, GUI)
- **COLMAP** (feature extraction, matching, sparse/dense reconstruction)
- **ffmpeg** (only if you start from video — to sample frames at 5 fps)

## Installation

### 1. COLMAP

Install COLMAP so the `colmap` command is available:

- **Official install guide:** [https://colmap.github.io/install](https://colmap.github.io/install)
- **macOS (Homebrew):** `brew install colmap`
- **Pre-built binaries:** [GitHub Releases](https://github.com/colmap/colmap/releases)

Check:

```bash
colmap -h
```

### 2. Python virtual environment and dependencies

From the project root:

```bash
# Create venv
python3 -m venv venv

# Activate (macOS/Linux)
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

Optional (macOS, for GUI dock icon):

```bash
pip install pyobjc-framework-Cocoa
```

### 3. (Optional) ffmpeg

Only needed if you run from **video** (e.g. `.mov` / `.mp4`):

- **macOS:** `brew install ffmpeg`
- **Linux:** `sudo apt install ffmpeg` (or your package manager)

## Project layout

Put each reconstruction project in a folder under `data/`:

```
data/
  MyProject/
    IMG_1234.mov          # optional: video to sample
    images/               # frames (from video or your own .jpg/.JPG)
    images_resized/       # created by pipeline
    images_resized_filtered/
    database.db
    sparse/
    dense/
```

- **From video:** put a `.mov` or `.mp4` in the project folder; the pipeline will sample at 5 fps into `images/`.
- **From images:** put your photos in `data/MyProject/images/` (`.jpg` or `.JPG`) and start from step `images`.

## Usage

### Command line

```bash
# Full pipeline from video
./run.sh MyProject

# Start from existing images (no video)
./run.sh MyProject --from-step images

# Start from resized images, use blur threshold and filtered set
./run.sh MyProject --from-step images_resized --blur-threshold 50 --use-image-set filtered

# Options
./run.sh <project> [--from-step STEP] [--blur-threshold N] [--use-image-set whole|filtered] [--skip-blur-if-plot] [--matcher sequential|exhaustive]
```

Steps: `video` | `images` | `images_resized` | `feature_extraction` | `feature_matching` | `sparse_reconstruction` | `dense_reconstruction`

### GUI

```bash
source venv/bin/activate
python run_gui.py
```

- Choose project, start step, blur threshold, matcher (sequential/exhaustive), image set (whole/filtered).
- **Run pipeline** opens a new terminal and runs the pipeline there (raw output for debugging).
- Overwrite/archive dialog only considers artifacts that would be overwritten by the chosen start step.

If `colmap gui` fails with a `symbol lookup error` in Snap-based terminals (e.g. VS Code Snap), run:

```bash
./scripts/run_colmap_gui_clean.sh
```

## Verify Results (recommended)

Use the helper script to open tools in a clean environment (avoids Snap runtime issues):

```bash
./scripts/open_results_clean.sh <project> <scene_id>
```

Example:

```bash
./scripts/open_results_clean.sh home 1
```

Expected result:

1. COLMAP GUI opens with `sparse/<scene_id>/` already imported (camera poses + sparse points).
2. MeshLab opens `dense/<scene_id>/fused.ply` (dense quality check: coverage, holes, noise).

Notes:

- `house_mesh.ply` is not opened by default.
- If you want it, set `OPEN_MESH=1` before the command.

## Publish to GitHub

I don’t have access to your GitHub account. To turn this into a repo under **oscar gentilhomme**:

1. **Create a new repository** on GitHub (e.g. `3DRecon`), owned by your user. Do **not** add a README or .gitignore there if you already have them locally.

2. **Initialize and push from this folder:**

   ```bash
   cd /path/to/3DRecon
   git init
   git add .
   git commit -m "Initial commit: 3D reconstruction pipeline with COLMAP"
   git branch -M main
   git remote add origin https://github.com/oscargentilhomme/3DRecon.git
   git push -u origin main
   ```

   Use your repo URL if the name or username differs. If you use SSH:

   ```bash
   git remote add origin git@github.com:oscargentilhomme/3DRecon.git
   ```

3. **Credentials:** `git push` will ask for your GitHub login (or use a [personal access token](https://github.com/settings/tokens) / SSH key).

After that, the repo will be on GitHub under your account with the README, `.gitignore`, and `requirements.txt` in place.
