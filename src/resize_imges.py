from PIL import Image
from pathlib import Path
from tqdm import tqdm
import argparse

MAX_SIZE = 2000  # max width or height


def main():
    parser = argparse.ArgumentParser(description="Resize images for COLMAP.")
    parser.add_argument(
        "--input", "-i",
        default="images",
        help="Input directory (default: images). Relative to cwd when run from project dir.",
    )
    parser.add_argument(
        "--output", "-o",
        default="images_resized",
        help="Output directory (default: images_resized). Relative to cwd.",
    )
    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = Path(args.output)
    if not input_dir.is_dir():
        raise SystemExit(f"Input directory not found: {input_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Support both .jpg and .JPG (and .jpeg/.JPEG) so we can use photo sets
    patterns = ("*.jpg", "*.JPG", "*.jpeg", "*.JPEG")
    img_paths = []
    for pat in patterns:
        img_paths.extend(input_dir.glob(pat))

    for img_path in tqdm(sorted(img_paths)):
        img = Image.open(img_path)
        img.thumbnail((MAX_SIZE, MAX_SIZE), Image.LANCZOS)
        img.save(output_dir / img_path.name, quality=95, subsampling=0)


if __name__ == "__main__":
    main()
