"""
Compute Laplacian variance (blur) for images, save histogram plot.
When threshold N is set: create a folder with images not below threshold (optional: delete blurry from input).
"""
import argparse
import shutil
from pathlib import Path

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from tqdm import tqdm


def plot_blur_histogram(blur_values, bins=30, title="Image Blur Distribution", out_path=None):
    plt.figure(figsize=(10, 6))
    plt.hist(blur_values, bins=bins, color="steelblue", edgecolor="black", alpha=0.7)
    plt.xlabel("Blur Value", fontsize=12)
    plt.ylabel("Frequency", fontsize=12)
    plt.title(title, fontsize=14, fontweight="bold")
    plt.grid(axis="y", alpha=0.3, linestyle="--")
    mean_blur = np.mean(blur_values)
    median_blur = np.median(blur_values)
    std_blur = np.std(blur_values)
    stats_text = f"Mean: {mean_blur:.2f}\nMedian: {median_blur:.2f}\nStd Dev: {std_blur:.2f}"
    plt.text(
        0.02, 0.98, stats_text, transform=plt.gca().transAxes,
        verticalalignment="top", bbox=dict(boxstyle="round", facecolor="wheat", alpha=0.5),
        fontsize=10,
    )
    plt.tight_layout()
    if out_path:
        plt.savefig(out_path, dpi=100)
        plt.close()
    else:
        plt.show()


def main():
    parser = argparse.ArgumentParser(description="Blur analysis: histogram + optional filtered folder.")
    parser.add_argument("--input", "-i", default="images_resized", help="Input image directory")
    parser.add_argument("--output-plot", "-o", default=None, help="Path for blur histogram PNG")
    parser.add_argument("--threshold", "-t", type=float, default=None, help="Blur threshold (images >= this are kept in filtered dir)")
    parser.add_argument("--output-filtered-dir", default="images_resized_filtered", help="Folder for images not below threshold (only if --threshold set)")
    parser.add_argument("--skip-if-plot-exists", action="store_true", help="Skip analysis if output plot already exists")
    parser.add_argument("--bins", type=int, default=60, help="Histogram bins")
    args = parser.parse_args()

    input_dir = Path(args.input)
    if not input_dir.is_dir():
        raise SystemExit(f"Input directory not found: {input_dir}")

    out_plot = args.output_plot
    if out_plot is None:
        out_plot = input_dir.parent / "blur_histogram.png"
    else:
        out_plot = Path(out_plot)
    out_plot.parent.mkdir(parents=True, exist_ok=True)

    if args.skip_if_plot_exists and out_plot.is_file():
        print(f"Blur plot already exists: {out_plot}. Skipping blur analysis.")
        return

    blur_values = []
    path_blur = []  # (path, blur_value)

    # Support both .jpg and .JPG (and .jpeg/.JPEG)
    patterns = ("*.jpg", "*.JPG", "*.jpeg", "*.JPEG")
    img_paths = []
    for pat in patterns:
        img_paths.extend(input_dir.glob(pat))

    for img_path in tqdm(sorted(img_paths), desc="Blur analysis"):
        img = cv2.imread(str(img_path), cv2.IMREAD_GRAYSCALE)
        if img is None:
            continue
        lap_var = cv2.Laplacian(img, cv2.CV_64F).var()
        blur_values.append(lap_var)
        path_blur.append((img_path, lap_var))

    if not blur_values:
        raise SystemExit("No images found.")

    plot_blur_histogram(
        blur_values,
        bins=args.bins,
        title=f"Image Blur Distribution — {input_dir.name}",
        out_path=out_plot,
    )
    print(f"Blur histogram saved to {out_plot}")

    if args.threshold is not None:
        filtered_dir = Path(args.output_filtered_dir)
        if not filtered_dir.is_absolute():
            filtered_dir = input_dir.parent / filtered_dir
        filtered_dir.mkdir(parents=True, exist_ok=True)
        # Clear previous filtered images (both .jpg and .JPG, etc.)
        for pat in ("*.jpg", "*.JPG", "*.jpeg", "*.JPEG"):
            for f in filtered_dir.glob(pat):
                f.unlink()
        kept = 0
        for img_path, lap_var in path_blur:
            if lap_var >= args.threshold:
                shutil.copy2(img_path, filtered_dir / img_path.name)
                kept += 1
        print(f"Copied {kept} images (blur >= {args.threshold}) to {filtered_dir}")


if __name__ == "__main__":
    main()
