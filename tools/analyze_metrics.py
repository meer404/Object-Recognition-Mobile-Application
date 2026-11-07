"""Summarise one evaluation session exported from the app.

Reads the session folder (session.json, frames.csv, device.csv) and reports
median and P95 for every latency stage, as CLAUDE.md requires ("not just
averages"), plus frame rates and memory/battery change.

P95 uses linear interpolation between ranks (`statistics.quantiles(...,
method="inclusive")`, the same as numpy's default). Standard library only.

Usage:
    python tools/analyze_metrics.py <session-folder> [--json]
    python tools/analyze_metrics.py compare <session> <session> ... [--charts DIR] [--include-debug]

`compare` prints one row per session and, with --charts, writes a box-plot PNG
per stage (matplotlib, see tools/requirements-tools.txt). Debug sessions are
left out unless --include-debug, since their numbers are not valid (D-021).
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


# ---------------------------------------------------------------------------
# Comparing sessions

# Categorical slots in fixed order (dataviz reference palette, validated for
# colour-vision deficiency on the light surface). Slots 3-5 are below 3:1
# contrast, so every box is also named on its axis: colour is never the only cue.
SESSION_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
SURFACE, INK, INK_MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
STAGE_TITLES = {
    "preprocess_ms": "Preprocessing",
    "inference_ms": "Inference",
    "postprocess_ms": "Postprocessing",
    "total_ms": "Detector total",
    "frame_to_speech_start_ms": "Frame to speech start",
}


def battery_per_hour(r: dict) -> float | None:
    b = r["battery_percent"]
    if b["start"] is None or b["end"] is None or not b["duration_s"]:
        return None
    return (b["start"] - b["end"]) / b["duration_s"] * 3600


def compare(folders: list[Path], include_debug: bool = False) -> dict:
    """One summary row per session, in the given order. Debug sessions are left
    out unless asked for, since their numbers are not valid (D-021)."""
    rows, skipped = [], []
    for folder in folders:
        r = analyze(folder)
        if not r["session"]["valid_for_performance_claims"] and not include_debug:
            skipped.append(folder.name)
            continue
        rows.append({"folder": folder, "result": r, "battery_per_hour": battery_per_hour(r)})
    return {"rows": rows, "skipped_debug": skipped}


def compare_markdown(c: dict) -> str:
    lines = [
        "## Session comparison",
        "",
        "| Session | Build | Device | Accelerator | Frames | Inference median / P95 ms | "
        "Total median / P95 ms | Speech start median / P95 ms | Inferences/s | RSS max MB | Battery %/h |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in c["rows"]:
        r = row["result"]
        s, lat = r["session"], r["latency_ms"]

        def mp(stage):
            v = lat[stage]
            return f"{_fmt(v['median'])} / {_fmt(v['p95'])}"

        lines.append(
            f"| {s['folder']} | {s['build_mode']} | {s['device']} | {s['accelerator']} | {r['frames']} | "
            f"{mp('inference_ms')} | {mp('total_ms')} | {mp('frame_to_speech_start_ms')} | "
            f"{_fmt(r['inference_fps']['median'], 2)} | {_fmt(r['rss_mb']['max'])} | {_fmt(row['battery_per_hour'])} |"
        )
    if c["skipped_debug"]:
        lines += ["", f"Left out (debug builds, not valid for performance claims): {', '.join(c['skipped_debug'])}"]
    return "\n".join(lines) + "\n"


def write_charts(c: dict, out: Path) -> list[Path]:
    """One box-plot PNG per stage: a box per session, whiskers at P5-P95, no
    outlier dots (P95 is what the tables report). Static, light, for print."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out.mkdir(parents=True, exist_ok=True)
    if len(c["rows"]) > len(SESSION_COLORS):
        raise ValueError(f"at most {len(SESSION_COLORS)} sessions per chart; split them into several charts")
    written = []
    for stage, title in STAGE_TITLES.items():
        data, names = [], []
        for row in c["rows"]:
            values = column(read_csv(row["folder"] / "frames.csv"), stage)
            if values:
                data.append(values)
                names.append(row["result"]["session"]["folder"])
        if not data:
            continue
        fig, ax = plt.subplots(
            figsize=(max(4.0, 1.4 * len(data) + 1.5), 3.6), dpi=200, layout="constrained"
        )
        fig.patch.set_facecolor(SURFACE)
        ax.set_facecolor(SURFACE)
        boxes = ax.boxplot(
            data,
            whis=(5, 95),
            showfliers=False,
            widths=0.5,
            patch_artist=True,
            medianprops={"color": INK, "linewidth": 2},
            whiskerprops={"color": INK_MUTED, "linewidth": 1},
            capprops={"color": INK_MUTED, "linewidth": 1},
            boxprops={"linewidth": 0},
        )
        for i, patch in enumerate(boxes["boxes"]):
            patch.set_facecolor(SESSION_COLORS[i])
            patch.set_alpha(0.85)
        ax.set_xticks(range(1, len(names) + 1), names, color=INK, fontsize=8)
        ax.set_ylabel("ms", color=INK_MUTED, fontsize=9)
        # Short headline plus a smaller key line, so neither is cut off at any width.
        fig.suptitle(f"{title} latency", color=INK, fontsize=10, x=0.02, ha="left")
        ax.set_title("box P25–P75 · line median · whiskers P5–P95", color=INK_MUTED, fontsize=7, loc="left")
        ax.set_ylim(bottom=0)
        ax.yaxis.grid(True, color=GRID, linewidth=0.8)
        ax.set_axisbelow(True)
        for side in ("top", "right", "left"):
            ax.spines[side].set_visible(False)
        ax.spines["bottom"].set_color(GRID)
        ax.tick_params(axis="y", colors=INK_MUTED, labelsize=8, length=0)
        ax.tick_params(axis="x", length=0)

        path = out / f"latency_{stage}.png"
        fig.savefig(path, facecolor=SURFACE)
        plt.close(fig)
        written.append(path)
    return written


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    # Windows consoles default to a legacy code page; the report has non-ASCII text.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if argv and argv[0] == "compare":
        p = argparse.ArgumentParser(prog="analyze_metrics.py compare", description="Compare sessions.")
        p.add_argument("folders", type=Path, nargs="+", help="exported session folders, in display order")
        p.add_argument("--charts", type=Path, help="write box-plot PNGs per stage here")
        p.add_argument("--include-debug", action="store_true", help="also show debug-build sessions")
        args = p.parse_args(argv[1:])
        c = compare(args.folders, args.include_debug)
        sys.stdout.write(compare_markdown(c))
        if args.charts:
            for path in write_charts(c, args.charts):
                sys.stdout.write(f"wrote {path}\n")
        return 0
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("folder", type=Path, help="exported session folder (or: compare <folders...>)")
    p.add_argument("--json", action="store_true", help="print JSON instead of Markdown")
    args = p.parse_args(argv)
    result = analyze(args.folder)
    sys.stdout.write(json.dumps(result, indent=2) + "\n" if args.json else to_markdown(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
