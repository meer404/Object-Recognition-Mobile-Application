"""Tests for evaluate.py on hand-built predictions and labels.

Run from the repository root:
    python tools/test_evaluate.py
"""

import json
import random
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evaluate as ev  # noqa: E402

CHAIR, TABLE, BUS = 56, 60, 5
BOX = [0.2, 0.2, 0.4, 0.4]  # Label box used below, normalized xyxy.
PERFECT_AP = 0.995  # Ultralytics' method caps a perfect detector here (see evaluate.py).


def yolo(c, box):
    x1, y1, x2, y2 = box
    return f"{c} {(x1 + x2) / 2} {(y1 + y2) / 2} {x2 - x1} {y2 - y1}\n"


class EvaluateTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def run_eval(self, images, threshold=0.5):
        """images: list of (labels [(class, box)], detections [(class, conf, box)])."""
        records = []
        for i, (labels, dets) in enumerate(images):
            (self.root / f"{i}.txt").write_text("".join(yolo(c, b) for c, b in labels))
            records.append(
                {
                    "file": f"{i}.jpg",
                    "detections": [{"class": c, "confidence": s, "box": b} for c, s, b in dets],
                }
            )
        p = self.root / "predictions.json"
        p.write_text(json.dumps({"root": str(self.root), "classes": [CHAIR, TABLE], "images": records}))
        return ev.evaluate(p, threshold)

    def test_perfect_detection(self):
        r = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, BOX)])])
        m = r["per_class"][CHAIR]
        self.assertAlmostEqual(m["ap50"], PERFECT_AP, places=6)
        self.assertEqual((m["tp"], m["fp"], m["missed"]), (1, 0, 0))
        self.assertEqual((m["precision"], m["recall"]), (1.0, 1.0))
        self.assertAlmostEqual(r["map50"], PERFECT_AP, places=6)

    def test_nothing_detected(self):
        m = self.run_eval([([(CHAIR, BOX)], [])])["per_class"][CHAIR]
        self.assertEqual(m["ap50"], 0.0, "not 0.5 from the curve padding")
        self.assertEqual((m["tp"], m["missed"]), (0, 1))
        self.assertIsNone(m["precision"], "no predictions: precision undefined, not 0")
        self.assertEqual(m["recall"], 0.0)

    def test_a_duplicate_detection_is_a_false_positive(self):
        m = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, BOX), (CHAIR, 0.8, BOX)])])["per_class"][CHAIR]
        self.assertEqual((m["tp"], m["fp"]), (1, 1))

    def test_the_wrong_class_is_a_miss_and_a_false_positive(self):
        r = self.run_eval([([(CHAIR, BOX)], [(TABLE, 0.9, BOX)])])
        self.assertEqual(r["per_class"][CHAIR]["missed"], 1)
        self.assertEqual(r["per_class"][TABLE]["fp"], 1)

    def test_iou_just_below_and_above_half(self):
        # Same height; width overlap chosen for IoU = 0.48 and 0.52.
        def shifted(iou):
            w = 0.2
            # Two w x w boxes offset by d have IoU (w-d)/(w+d).
            d = w * (1 - iou) / (1 + iou)
            return [0.2 + d, 0.2, 0.4 + d, 0.4]

        below = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, shifted(0.48))])])["per_class"][CHAIR]
        above = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, shifted(0.52))])])["per_class"][CHAIR]
        self.assertEqual(below["tp"], 0)
        self.assertEqual(above["tp"], 1)

    def test_low_confidence_counts_for_ap_but_not_for_what_is_spoken(self):
        m = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.3, BOX)])])["per_class"][CHAIR]
        self.assertAlmostEqual(m["ap50"], PERFECT_AP, places=6)
        self.assertEqual((m["tp"], m["missed"]), (0, 1), "below 0.5 the app stays silent")
        self.assertAlmostEqual(m["best_f1_threshold"], 0.3)

    def test_each_label_is_matched_once_highest_confidence_first(self):
        far = [0.6, 0.6, 0.8, 0.8]
        m = self.run_eval([([(CHAIR, BOX), (CHAIR, far)], [(CHAIR, 0.6, BOX), (CHAIR, 0.9, BOX)])])["per_class"][CHAIR]
        self.assertEqual((m["tp"], m["fp"], m["missed"]), (1, 1, 1))

    def test_other_classes_are_excluded_and_counted(self):
        r = self.run_eval([([(CHAIR, BOX), (BUS, BOX)], [(CHAIR, 0.9, BOX)])])
        self.assertEqual(r["excluded_labels_outside_classes"], 1)
        self.assertEqual(r["per_class"][CHAIR]["labels"], 1)

    def test_map_ignores_classes_without_labels(self):
        r = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, BOX), (TABLE, 0.9, [0.6, 0.6, 0.7, 0.7])])])
        self.assertEqual(r["classes_with_labels"], 1)
        self.assertAlmostEqual(r["map50"], PERFECT_AP, places=6)
        self.assertEqual(r["per_class"][TABLE]["fp"], 1, "still counted as a false positive")

    def test_overall_and_markdown(self):
        r = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, BOX)]), ([(TABLE, BOX)], [])])
        o = r["overall_at_threshold"]
        self.assertEqual((o["tp"], o["missed"], o["labels"]), (1, 1, 2))
        # Chair perfect (0.995), table never predicted (0): mean 0.4975.
        self.assertAlmostEqual(r["map50"], PERFECT_AP / 2, places=6)
        md = ev.to_markdown(r, None)
        self.assertIn("mAP@0.5:** 0.497", md)

    def test_table_hides_classes_with_nothing_to_report(self):
        r = self.run_eval([([(CHAIR, BOX)], [(CHAIR, 0.9, BOX), (TABLE, 0.2, [0.6, 0.6, 0.7, 0.7])])])
        md = ev.to_markdown(r, None)
        self.assertIn("| 56 56 |", md)
        self.assertNotIn("| 60 60 |", md, "a table below the threshold is never spoken")

    def test_ap_matches_hand_computation(self):
        # Two labels; predictions TP (0.9), FP (0.8), TP (0.7).
        far = [0.6, 0.6, 0.8, 0.8]
        m = self.run_eval(
            [([(CHAIR, BOX), (CHAIR, far)], [(CHAIR, 0.9, BOX), (CHAIR, 0.8, [0, 0.9, 0.1, 1]), (CHAIR, 0.7, far)])]
        )["per_class"][CHAIR]
        recall = np.array([0.5, 0.5, 1.0])
        precision = np.array([1.0, 0.5, 2 / 3])
        self.assertAlmostEqual(m["ap50"], ev.compute_ap(recall, precision), places=9)
        self.assertTrue(0.8 < m["ap50"] < 0.85)


class AgreesWithUltralytics(unittest.TestCase):
    def test_compute_ap_matches_ultralytics_on_random_curves(self):
        try:
            from ultralytics.utils.metrics import compute_ap as ul_compute_ap
        except ImportError:
            self.skipTest("ultralytics not installed")
        rng = random.Random(0)
        for _ in range(50):
            n = rng.randint(1, 40)
            tp = np.array([rng.random() < 0.6 for _ in range(n)])
            labels = max(1, int(tp.sum()) + rng.randint(0, 5))
            recall = np.cumsum(tp) / labels
            precision = np.cumsum(tp) / np.arange(1, n + 1)
            ours = ev.compute_ap(recall, precision)
            theirs = ul_compute_ap(list(recall), list(precision))[0]
            self.assertAlmostEqual(ours, float(theirs), places=9)


if __name__ == "__main__":
    unittest.main()
