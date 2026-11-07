"""Summarise one evaluation session exported from the app.

Reads the session folder (session.json, frames.csv, device.csv) and reports
median and P95 for every latency stage, as CLAUDE.md requires ("not just
averages"), plus frame rates and memory/battery change.

P95 uses linear interpolation between ranks (`statistics.quantiles(...,
method="inclusive")`, the same as numpy's default). Standard library only.

Usage:
    python tools/analyze_metrics.py <session-folder> [--json]
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
import sys
from datetime import datetime
from pathlib import Path

FRAME_STAGES = ["preprocess_ms", "inference_ms", "postprocess_ms", "total_ms", "frame_to_speech_start_ms"]


def percentile(values: list[float], q: int) -> float:
    """q-th percentile (1-99) with linear interpolation; one value is its own percentile."""
    if len(values) == 1:
        return values[0]
    return statistics.quantiles(values, n=100, method="inclusive")[q - 1]


def summary(values: list[float]) -> dict[str, float | int | None]:
    if not values:
        return {"n": 0, "median": None, "p95": None, "min": None, "max": None}
    return {
        "n": len(values),
        "median": statistics.median(values),
        "p95": percentile(values, 95),
        "min": min(values),
        "max": max(values),
    }


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def column(rows: list[dict[str, str]], name: str) -> list[float]:
    """Numeric values of a column; empty cells (no value) are skipped."""
    return [float(r[name]) for r in rows if r.get(name, "") != ""]


def analyze(folder: Path) -> dict:
    session = json.loads((folder / "session.json").read_text(encoding="utf-8"))
    frames = read_csv(folder / "frames.csv")
    device = read_csv(folder / "device.csv")

    def seconds_between(rows: list[dict[str, str]]) -> float | None:
        if len(rows) < 2:
            return None
        start = datetime.fromisoformat(rows[0]["timestamp_utc"].replace("Z", "+00:00"))
        end = datetime.fromisoformat(rows[-1]["timestamp_utc"].replace("Z", "+00:00"))
        return (end - start).total_seconds()

    rss = column(device, "rss_mb")
    battery = column(device, "battery_percent")
    return {
        "session": {
            "folder": folder.name,
            "build_mode": session.get("build_mode"),
            "valid_for_performance_claims": session.get("valid_for_performance_claims"),
            "device": session.get("device"),
            "os": session.get("os"),
            "accelerator": session.get("accelerator"),
            "model_asset": session.get("model_asset"),
            "git_commit": session.get("git_commit"),
        },
        "frames": len(frames),
        "frames_with_speech": len(column(frames, "frame_to_speech_start_ms")),
        "latency_ms": {stage: summary(column(frames, stage)) for stage in FRAME_STAGES},
        "camera_fps": summary(column(device, "camera_fps")),
        "inference_fps": summary(column(device, "inference_fps")),
        "dropped_busy": int(sum(column(device, "dropped_busy"))),
        "dropped_rate": int(sum(column(device, "dropped_rate"))),
        "rss_mb": {"start": rss[0] if rss else None, "end": rss[-1] if rss else None, "max": max(rss) if rss else None},
        "battery_percent": {
            "start": battery[0] if battery else None,
            "end": battery[-1] if battery else None,
            "duration_s": seconds_between(device),
        },
    }


def _fmt(value: float | int | None, decimals: int = 1) -> str:
    if value is None:
        return "–"
    return f"{value:.{decimals}f}" if isinstance(value, float) else str(value)


def to_markdown(r: dict) -> str:
    s = r["session"]
    lines = [f"## Session {s['folder']}", ""]
    if not s["valid_for_performance_claims"]:
        lines += ["> **Debug build: NOT valid for performance claims (D-021).**", ""]
    lines += [
        f"- Device: {s['device']} ({s['os']})",
        f"- Build: {s['build_mode']}, accelerator: {s['accelerator']}, model: {s['model_asset']}",
        f"- Commit: {s['git_commit']}",
        f"- Frames: {r['frames']} ({r['frames_with_speech']} started speech)",
        "",
        "| Stage | n | Median ms | P95 ms | Min | Max |",
        "|---|---|---|---|---|---|",
    ]
    for stage, v in r["latency_ms"].items():
        lines.append(
            f"| {stage} | {v['n']} | {_fmt(v['median'])} | {_fmt(v['p95'])} | {_fmt(v['min'])} | {_fmt(v['max'])} |"
        )
    cam, inf = r["camera_fps"], r["inference_fps"]
    bat, rss = r["battery_percent"], r["rss_mb"]
    lines += [
        "",
        f"- Camera frames/s: median {_fmt(cam['median'], 2)}, P95 {_fmt(cam['p95'], 2)}",
        f"- Inferences/s: median {_fmt(inf['median'], 2)}, P95 {_fmt(inf['p95'], 2)}",
        f"- Dropped frames: {r['dropped_busy']} while busy, {r['dropped_rate']} by rate limit",
        f"- RSS MB: start {_fmt(rss['start'])}, end {_fmt(rss['end'])}, max {_fmt(rss['max'])}",
        f"- Battery %: {_fmt(bat['start'], 0)} → {_fmt(bat['end'], 0)} over {_fmt(bat['duration_s'], 0)} s",
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("folder", type=Path, help="exported session folder")
    p.add_argument("--json", action="store_true", help="print JSON instead of Markdown")
    args = p.parse_args(argv)
    # Windows consoles default to a legacy code page; the report has non-ASCII text.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    result = analyze(args.folder)
    sys.stdout.write(json.dumps(result, indent=2) + "\n" if args.json else to_markdown(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
