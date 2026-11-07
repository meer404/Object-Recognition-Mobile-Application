"""Tests for analyze_metrics.py, run on the session the Dart logger writes.

test/fixtures/metrics_session/ is produced by the Dart test
test/metrics/csv_metrics_logger_test.dart (reference session), so this checks
that the analyzer reads exactly what the app writes. Expected values follow
from that test's numbers: frame i (0-9) has preprocess 5+i ms, inference
20+2i ms, postprocess 1 ms, and speech latency 100+10i ms on every third frame.

Run from the repository root:
    python tools/test_analyze_metrics.py
"""

import statistics
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze_metrics as am  # noqa: E402

FIXTURE = Path(__file__).resolve().parents[1] / "test" / "fixtures" / "metrics_session"


class AnalyzeReferenceSession(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.r = am.analyze(FIXTURE)

    def test_counts(self):
        self.assertEqual(self.r["frames"], 10)
        self.assertEqual(self.r["frames_with_speech"], 4)  # i = 0, 3, 6, 9

    def test_stage_medians(self):
        lat = self.r["latency_ms"]
        self.assertAlmostEqual(lat["preprocess_ms"]["median"], 9.5)  # 5..14
        self.assertAlmostEqual(lat["inference_ms"]["median"], 29.0)  # 20..38 step 2
        self.assertAlmostEqual(lat["postprocess_ms"]["median"], 1.0)
        self.assertAlmostEqual(lat["total_ms"]["median"], 39.5)

    def test_p95_uses_linear_interpolation(self):
        # Ranks 0..9: P95 sits at 8.55, between 13 and 14 -> 13.55.
        self.assertAlmostEqual(self.r["latency_ms"]["preprocess_ms"]["p95"], 13.55)

    def test_empty_speech_cells_are_skipped_not_zero(self):
        speech = self.r["latency_ms"]["frame_to_speech_start_ms"]
        self.assertEqual(speech["n"], 4)
        self.assertAlmostEqual(speech["median"], statistics.median([100, 130, 160, 190]))
        self.assertAlmostEqual(speech["min"], 100)

    def test_rates_skip_the_first_sample(self):
        self.assertEqual(self.r["camera_fps"]["n"], 2)
        self.assertAlmostEqual(self.r["inference_fps"]["median"], 3.875)  # 3.75, 4.0

    def test_drops_memory_battery(self):
        self.assertEqual(self.r["dropped_busy"], 3)  # 0 + 1 + 2
        self.assertEqual(self.r["dropped_rate"], 520)
        self.assertEqual(self.r["rss_mb"], {"start": 300.0, "end": 310.0, "max": 310.0})
        self.assertEqual(self.r["battery_percent"]["start"], 90.0)
        self.assertEqual(self.r["battery_percent"]["end"], 88.0)
        self.assertAlmostEqual(self.r["battery_percent"]["duration_s"], 20.0)

    def test_session_fields(self):
        s = self.r["session"]
        self.assertEqual(s["build_mode"], "profile")
        self.assertTrue(s["valid_for_performance_claims"])
        self.assertEqual(s["accelerator"], "gpu (OpenGL/OpenCL)")

    def test_markdown_report(self):
        md = am.to_markdown(self.r)
        self.assertIn("| inference_ms | 10 | 29.0 |", md)
        self.assertNotIn("NOT valid", md)

    def test_debug_sessions_are_flagged(self):
        r = dict(self.r)
        r["session"] = dict(self.r["session"], valid_for_performance_claims=False)
        self.assertIn("NOT valid for performance claims", am.to_markdown(r))


class Percentile(unittest.TestCase):
    def test_single_value(self):
        self.assertEqual(am.percentile([7.0], 95), 7.0)

    def test_matches_numpy_linear(self):
        # numpy.percentile([1, 2, 3, 4], 95) == 3.85
        self.assertAlmostEqual(am.percentile([1, 2, 3, 4], 95), 3.85)

    def test_empty_summary(self):
        self.assertEqual(am.summary([])["median"], None)


if __name__ == "__main__":
    unittest.main()
