# EvoVista

End-to-end 3D reconstruction pipeline from video or photos:

1. optional video frame sampling
2. image resize
3. blur analysis
4. COLMAP feature extraction and matching
5. sparse reconstruction
6. dense reconstruction (`fused.ply`)
7. optional mesh generation with MeshLab server (`house_mesh.ply`)

## Requirements

- Python 3.9+ (scripts and GUI)
- COLMAP (local binary and/or Docker image)
- Docker (optional fallback backend)
- ffmpeg (only if starting from video)
- MeshLab (`meshlab` / `meshlabserver`) optional for mesh generation and visual checks

## Installation

### Python dependencies

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### COLMAP

- Official: <https://colmap.github.io/install>
- macOS (Homebrew): `brew install colmap`
- Linux: install the package/binary so `colmap` is in `PATH`

Check:

```bash
colmap -h
```

### Docker (optional but recommended)

Docker is used when local CUDA-enabled COLMAP is not detected.

Check:

```bash
docker info
```

### ffmpeg (video input only)

- macOS: `brew install ffmpeg`
- Linux: `sudo apt install ffmpeg`

### MeshLab (optional)

- Linux: `sudo apt install meshlab`

Check:

```bash
which meshlab
which meshlabserver
```

## Data layout

Each project goes under `data/<project>/`.

```text
data/
  MyProject/
    *.mov | *.mp4                 # optional if starting from video
    images/                       # your photos or sampled frames
    images_resized/               # generated
    images_resized_filtered/      # optional, generated with blur threshold
    database.db                   # COLMAP database
    sparse/
    dense/
    logs/
```

## Running the pipeline

### Common commands

```bash
# Full pipeline from video
./run.sh MyProject

# Start from photos already present in data/MyProject/images
./run.sh MyProject --from-step images

# Start from resized images
./run.sh MyProject --from-step images_resized

# Use filtered images from blur threshold
./run.sh MyProject --from-step images_resized --blur-threshold 50 --use-image-set filtered

# Faster matching for video-like sequences
./run.sh MyProject --from-step images --matcher sequential
```

Available steps:
`video`, `images`, `images_resized`, `feature_extraction`, `feature_matching`, `sparse_reconstruction`, `dense_reconstruction`.

### Backend selection (local vs docker)

`run.sh` supports:

- `COLMAP_BACKEND=auto` (default)
- `COLMAP_BACKEND=local`
- `COLMAP_BACKEND=docker`

`auto` behavior:

1. use local only if `colmap version` explicitly reports CUDA support
2. otherwise fallback to Docker
3. otherwise fail with a clear message

Examples:

```bash
# Force local COLMAP
COLMAP_BACKEND=local ./run.sh MyProject --from-step images

# Force Docker COLMAP
COLMAP_BACKEND=docker ./run.sh MyProject --from-step images
```

## Failure modes and what to do

### Docker unavailable + local CUDA COLMAP unavailable

Error:

```text
Error: local COLMAP with CUDA not detected and Docker is unavailable.
```

Fix:

- start/install Docker, or
- install a CUDA-enabled local COLMAP, or
- force another backend explicitly with `COLMAP_BACKEND=...`

### `colmap gui` / `meshlabserver` symbol lookup error from Snap terminals

This often happens in Snap-based environments (example: VS Code Snap) due to mixed runtime libraries.

Use clean environment wrappers:

- GUI open helper: `./scripts/open_results_clean.sh <project> <scene>`
- Mesh generation command with clean env:

```bash
env -i PATH=/usr/bin:/bin HOME="$HOME" USER="$USER" DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
  /usr/bin/meshlabserver -i dense/0/fused.ply -o dense/0/house_mesh.ply -s /absolute/path/to/resources/poisson.mlx
```

### `meshlabserver` missing

Dense reconstruction still succeeds. `fused.ply` remains the primary output.

Mesh generation is optional and non-blocking in the pipeline.

## MeshLab server in this project

### What `meshlabserver` is used for

After COLMAP dense reconstruction, the pipeline can convert `fused.ply` (dense point cloud) into `house_mesh.ply` (surface mesh) using Poisson reconstruction.

### Why this step is optional

- `fused.ply` is already usable for many workflows
- Poisson meshing is a post-process convenience step
- if it fails, pipeline should not lose dense reconstruction results

### Poisson script and parameters

Script path:

- `resources/poisson.mlx`

The script uses `Surface Reconstruction: Screened Poisson` with explicit parameters required by this MeshLab plugin build:

- `depth=8`: octree max depth. Higher = more detail + more RAM/time.
- `fullDepth=5`: complete octree depth before adaptive refinement.
- `cgDepth=0`: depth until conjugate-gradient solver is used.
- `scale=1.1`: reconstruction cube scale vs data bounding box.
- `samplesPerNode=1.5`: sampling density target per octree node.
- `pointWeight=4`: interpolation weight (0 is unscreened Poisson).
- `iters=8`: Gauss-Seidel relaxations.
- `confidence=false`: do not use vertex quality as normal confidence weight.
- `preClean=true`: removes invalid/unreferenced points before solve.
- `visibleLayer=false`: use only current layer (not all visible layers).

These defaults are stable and conservative for typical phone/video captures.

## Visualizing results

Use the helper:

```bash
./scripts/open_results_clean.sh <project> <scene_id>
```

It opens:

1. COLMAP GUI with sparse import
2. MeshLab on `fused.ply`
3. MeshLab on `house_mesh.ply` automatically if present (`OPEN_MESH=auto`)

`OPEN_MESH` modes:

- `OPEN_MESH=auto` (default): open mesh if it exists
- `OPEN_MESH=1`: try to open mesh and warn if missing
- `OPEN_MESH=0`: never open mesh

## Resume strategy after failure

- If failure happened after dense fusion and `dense/<scene>/fused.ply` exists, do not rerun dense.
- Run only meshing with `meshlabserver` on existing `fused.ply`.
- If you rerun `--from-step dense_reconstruction`, COLMAP dense steps are recomputed.

## GUI

```bash
source venv/bin/activate
python run_gui.py
```

## Publish to GitHub

```bash
git init
git add .
git commit -m "Initial commit: 3D reconstruction pipeline with COLMAP"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```
