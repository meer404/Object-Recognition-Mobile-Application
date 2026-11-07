"""Tests for split_dataset.py on synthetic images made at test time.

Run from the repository root:
    python tools/test_split_dataset.py
"""

import json
import random
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageEnhance

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_dataset as sd  # noqa: E402


def scene(seed: int, size: int = 128) -> Image.Image:
    """A smooth, random 'scene': a few random colours upscaled smoothly.

    Raw noise would not do: downscaled for hashing it averages to near-uniform
    grey, so all noise images would look alike.
    """
    rng = random.Random(seed)
    tiny = Image.new("RGB", (5, 5))
    tiny.putdata([tuple(rng.randrange(256) for _ in range(3)) for _ in range(25)])
    return tiny.resize((size, size), Image.Resampling.BICUBIC)


def near_copy(image: Image.Image) -> Image.Image:
    """The same scene a moment later: slightly brighter and shifted by 3 px."""
    w, h = image.size
    shifted = image.crop((3, 0, w, h)).resize((w, h), Image.Resampling.BICUBIC)
    return ImageEnhance.Brightness(shifted).enhance(1.1)


class SplitTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name) / "dataset"
        self.root.mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def save(self, image: Image.Image, rel: str, classes=(0,)) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        path.with_suffix(".txt").write_text("".join(f"{c} 0.5 0.5 0.2 0.2\n" for c in classes))

    def lines(self, out: Path, split: str) -> list[str]:
        return (out / f"{split}.txt").read_text().split()

    def test_hash_separates_scenes_and_matches_near_copies(self):
        a, b = scene(1), scene(2)
        for path, image in (("a.png", a), ("b.png", b), ("a2.png", near_copy(a))):
            image.save(self.root / path)
        ha, hb, ha2 = (sd.dhash(self.root / p) for p in ("a.png", "b.png", "a2.png"))
        self.assertLessEqual(sd.hamming(ha, ha2), 8, "near copy should be close")
        self.assertGreater(sd.hamming(ha, hb), 12, "different scenes should differ")

    def test_near_duplicates_never_cross_splits(self):
        for i in range(30):
            original = scene(100 + i)
            self.save(original, f"img_{i:02d}_a.png")
            self.save(near_copy(original), f"img_{i:02d}_b.png")
        out = self.root / "splits"
        report = sd.split(self.root, out, folder_groups=False)
        where = {}
        for s in sd.SPLITS:
            for line in self.lines(out, s):
                where[line] = s
        for i in range(30):
            self.assertEqual(where[f"img_{i:02d}_a.png"], where[f"img_{i:02d}_b.png"], i)
        self.assertEqual(report["groups"], 30)

    def test_ratios_are_close_for_distinct_images(self):
        for i in range(100):
            self.save(scene(1000 + i), f"x_{i:03d}.png")
        report = sd.split(self.root, self.root / "splits")
        counts = report["images_per_split"]
        self.assertEqual(sum(counts.values()), 100)
        self.assertEqual(counts, {"train": 70, "val": 15, "test": 15})

    def test_same_seed_same_split_and_other_seed_differs(self):
        for i in range(40):
            self.save(scene(2000 + i), f"y_{i:02d}.png")
        first = sd.split(self.root, self.root / "s1", seed=7)
        second = sd.split(self.root, self.root / "s2", seed=7)
        third = sd.split(self.root, self.root / "s3", seed=8)
        self.assertEqual(self.lines(self.root / "s1", "test"), self.lines(self.root / "s2", "test"))
        self.assertNotEqual(self.lines(self.root / "s1", "test"), self.lines(self.root / "s3", "test"))
        self.assertEqual(first["images_per_split"], second["images_per_split"])
        del third

    def test_a_recording_folder_stays_together(self):
        for i in range(8):
            self.save(scene(3000 + i), f"session_kitchen/frame_{i}.png")
        for i in range(30):
            self.save(scene(4000 + i), f"z_{i:02d}.png")
        out = self.root / "splits"
        sd.split(self.root, out)
        splits_with_kitchen = {
            s for s in sd.SPLITS for line in self.lines(out, s) if line.startswith("session_kitchen/")
        }
        self.assertEqual(len(splits_with_kitchen), 1)

    def test_report_counts_classes_and_missing_labels(self):
        self.save(scene(1), "a.png", classes=(56, 56, 60))
        scene(2).save(self.root / "unlabelled.png")
        out = self.root / "splits"
        report = sd.split(self.root, out, ratios=(1.0, 0.0, 0.0))
        self.assertEqual(report["boxes_per_class_per_split"]["train"], {"56": 2, "60": 1})
        self.assertEqual(report["missing_labels"], ["unlabelled.png"])
        self.assertEqual(json.loads((out / "split_report.json").read_text())["images"], 2)

    def test_labels_in_a_mirrored_folder_are_found(self):
        image = self.root / "images" / "a.png"
        image.parent.mkdir(parents=True)
        scene(1).save(image)
        label = self.root / "labels" / "a.txt"
        label.parent.mkdir(parents=True)
        label.write_text("41 0.5 0.5 0.1 0.1\n")
        self.assertEqual(sd.label_path(image), label)

    def test_report_lists_similar_pairs_that_were_split(self):
        a = scene(5)
        self.save(a, "x/a.png")
        self.save(near_copy(a), "y/b.png")
        report = sd.split(self.root, self.root / "s", ratios=(0.5, 0.5, 0.0), max_distance=0)
        pairs = report["closest_pairs_across_splits"]
        self.assertEqual(len(pairs), 1, "grouping was disabled, so they split and must be flagged")
        self.assertEqual({pairs[0]["a"], pairs[0]["b"]}, {"x/a.png", "y/b.png"})

    def test_bad_ratios_are_rejected(self):
        self.save(scene(1), "a.png")
        with self.assertRaises(ValueError):
            sd.split(self.root, self.root / "s", ratios=(0.5, 0.5, 0.5))


if __name__ == "__main__":
    unittest.main()
