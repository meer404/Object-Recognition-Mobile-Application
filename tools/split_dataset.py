"""Split a labelled image folder into train/val/test without near-duplicate
leakage.

Photos of the same scene taken seconds apart (or frames of one video) are
almost identical. If one lands in training and its twin in test, test scores
are inflated. So images are grouped first and whole groups are assigned:

- **Perceptual hash:** a 64-bit dHash per image. Images whose hashes differ in
  at most `--max-distance` bits (default 8) are grouped (transitively, with
  union-find). On the synthetic test scenes, near-copies (3 px shift, +10 %
  brightness) were 0-7 bits apart and distinct scenes at least 9, hence 8.
  Real photos may differ: the report lists the closest pairs that still ended
  up in different splits, to check by eye before trusting a split.
- **Recording folder:** images in the same sub-folder of the dataset root (one
  session or one video) are grouped too, unless `--no-folder-groups`.

Groups are shuffled with `--seed` and each goes to the split furthest below its
target share, so the split is deterministic and close to the ratios.

Labels are YOLO .txt (one `class cx cy w h` line per box) with the image's
stem, next to the image or in a mirrored `labels/` folder in place of `images/`.

Usage:
    python tools/split_dataset.py <dataset-root> [--out DIR] [--seed 0]
        [--ratios 0.7 0.15 0.15] [--max-distance 8] [--no-folder-groups]
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLITS = ("train", "val", "test")
HASH_WIDTH = 9  # 9 x 8 pixels -> 8 comparisons per row x 8 rows = 64 bits
HASH_HEIGHT = 8
CHECK_DISTANCE = 12  # Cross-split pairs this close are listed for a manual look.


def dhash(path: Path) -> int:
    """64-bit difference hash: is each pixel brighter than its right neighbour?

    Robust to scaling, small crops and brightness changes; different scenes
    differ in many bits.
    """
    with Image.open(path) as image:
        small = image.convert("L").resize((HASH_WIDTH, HASH_HEIGHT), Image.Resampling.LANCZOS)
        pixels = small.tobytes()  # One byte per pixel in mode "L".
    bits = 0
    for row in range(HASH_HEIGHT):
        for col in range(HASH_WIDTH - 1):
            left = pixels[row * HASH_WIDTH + col]
            right = pixels[row * HASH_WIDTH + col + 1]
            bits = (bits << 1) | (1 if left > right else 0)
    return bits


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


class UnionFind:
    def __init__(self, n: int) -> None:
        self.parent = list(range(n))

    def find(self, i: int) -> int:
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def union(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            # Smaller index wins, so groups are named deterministically.
            self.parent[max(ra, rb)] = min(ra, rb)


def find_images(root: Path) -> list[Path]:
    images = [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES]
    return sorted(images, key=lambda p: p.relative_to(root).as_posix())


def label_path(image: Path) -> Path | None:
    """The YOLO label for an image: next to it, or in a mirrored labels/ folder."""
    beside = image.with_suffix(".txt")
    if beside.exists():
        return beside
    parts = list(image.parts)
    if "images" in parts:
        i = len(parts) - 1 - parts[::-1].index("images")
        mirrored = Path(*parts[:i], "labels", *parts[i + 1 :]).with_suffix(".txt")
        if mirrored.exists():
            return mirrored
    return None


def read_classes(label: Path) -> list[int]:
    classes = []
    for line in label.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if fields:
            classes.append(int(float(fields[0])))
    return classes


def group_images(
    root: Path, images: list[Path], hashes: list[int], max_distance: int, folder_groups: bool
) -> list[list[int]]:
    """Indices of images, grouped by near-duplicate hash and recording folder."""
    uf = UnionFind(len(images))
    for i in range(len(images)):
        for j in range(i + 1, len(images)):
            if hamming(hashes[i], hashes[j]) <= max_distance:
                uf.union(i, j)
    if folder_groups:
        first_in_folder: dict[str, int] = {}
        for i, p in enumerate(images):
            folder = p.parent.relative_to(root).as_posix()
            if folder in (".", "", "images"):
                continue  # Loose files in the root are not one session.
            if folder in first_in_folder:
                uf.union(first_in_folder[folder], i)
            else:
                first_in_folder[folder] = i
    groups: dict[int, list[int]] = {}
    for i in range(len(images)):
        groups.setdefault(uf.find(i), []).append(i)
    return sorted(groups.values(), key=lambda g: g[0])


def assign(groups: list[list[int]], ratios: tuple[float, float, float], seed: int) -> list[str]:
    """Split name per image. Each group goes where the image count is furthest
    below its target share, largest groups first, ties broken by the seeded order."""
    rng = random.Random(seed)
    order = groups[:]
    rng.shuffle(order)
    order.sort(key=len, reverse=True)  # stable: keeps the shuffled order among equals
    total = sum(len(g) for g in groups)
    counts = dict.fromkeys(SPLITS, 0)
    result: list[str] = [""] * total
    for group in order:
        deficits = {s: ratios[k] * total - counts[s] for k, s in enumerate(SPLITS)}
        chosen = max(SPLITS, key=lambda s: (deficits[s], -SPLITS.index(s)))
        counts[chosen] += len(group)
        for i in group:
            result[i] = chosen
    return result


def split(
    root: Path,
    out: Path,
    *,
    ratios: tuple[float, float, float] = (0.7, 0.15, 0.15),
    seed: int = 0,
    max_distance: int = 8,
    folder_groups: bool = True,
) -> dict:
    if abs(sum(ratios) - 1) > 1e-6:
        raise ValueError(f"ratios must sum to 1, got {ratios}")
    images = find_images(root)
    if not images:
        raise ValueError(f"no images under {root}")
    hashes = [dhash(p) for p in images]
    groups = group_images(root, images, hashes, max_distance, folder_groups)
    assignment = assign(groups, ratios, seed)

    out.mkdir(parents=True, exist_ok=True)
    rel = [p.relative_to(root).as_posix() for p in images]
    for name in SPLITS:
        lines = [rel[i] for i in range(len(images)) if assignment[i] == name]
        (out / f"{name}.txt").write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")

    missing_labels = []
    classes_per_split = {name: Counter() for name in SPLITS}
    images_per_split = Counter(assignment)
    for i, image in enumerate(images):
        label = label_path(image)
        if label is None:
            missing_labels.append(rel[i])
            continue
        classes_per_split[assignment[i]].update(read_classes(label))

    largest = sorted(groups, key=len, reverse=True)[:10]
    close_across = sorted(
        (hamming(hashes[i], hashes[j]), rel[i], rel[j])
        for i in range(len(images))
        for j in range(i + 1, len(images))
        if assignment[i] != assignment[j] and hamming(hashes[i], hashes[j]) <= CHECK_DISTANCE
    )[:20]
    report = {
        "root": str(root),
        "seed": seed,
        "ratios": dict(zip(SPLITS, ratios)),
        "max_distance": max_distance,
        "folder_groups": folder_groups,
        "images": len(images),
        "groups": len(groups),
        "images_per_split": {s: images_per_split.get(s, 0) for s in SPLITS},
        "boxes_per_class_per_split": {
            s: {str(c): n for c, n in sorted(classes_per_split[s].items())} for s in SPLITS
        },
        "missing_labels": missing_labels,
        "largest_groups": [[rel[i] for i in g] for g in largest if len(g) > 1],
        "closest_pairs_across_splits": [
            {"distance": d, "a": a, "b": b} for d, a, b in close_across
        ],
    }
    (out / "split_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("root", type=Path, help="dataset folder with images and YOLO labels")
    p.add_argument("--out", type=Path, help="output folder (default: <root>/splits)")
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--ratios", type=float, nargs=3, default=(0.7, 0.15, 0.15), metavar=("TRAIN", "VAL", "TEST"))
    p.add_argument("--max-distance", type=int, default=8, help="max dHash bits apart for near-duplicates (of 64)")
    p.add_argument("--no-folder-groups", action="store_true", help="do not group images by sub-folder")
    args = p.parse_args(argv)
    report = split(
        args.root,
        args.out or args.root / "splits",
        ratios=tuple(args.ratios),
        seed=args.seed,
        max_distance=args.max_distance,
        folder_groups=not args.no_folder_groups,
    )
    print(f"{report['images']} images in {report['groups']} groups -> {report['images_per_split']}")
    if report["closest_pairs_across_splits"]:
        print(
            f"CHECK: {len(report['closest_pairs_across_splits'])} similar pairs are in different splits "
            f"(closest_pairs_across_splits in split_report.json)"
        )
    if report["missing_labels"]:
        print(f"WARNING: {len(report['missing_labels'])} images have no label file (see split_report.json)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
