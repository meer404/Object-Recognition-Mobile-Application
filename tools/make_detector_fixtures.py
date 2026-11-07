"""Generate reference data for the Dart detector tests (test/fixtures/).

Numbers only: no image or model file is written to the repository.

  preprocess_64x48_to_32.json  A synthetic RGB image and the letterboxed input
      tensor from cv2, the resizer Ultralytics uses. Checks the Dart resize.
  detector_bus_320.json        Real raw output of yolo26n_320_fp32.tflite on
      Ultralytics' bus.jpg (only anchors with any score >= SCORE_FLOOR) and the
      detections an independent Python decode + NMS finds. Checks the Dart decode.

Needs build/models/yolo26n_320_fp32.tflite (tools/export_model.py), plus
ultralytics, opencv-python and ai-edge-litert (all work on Windows). Run from
the repository root:

    python tools/make_detector_fixtures.py
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
import ultralytics
from ai_edge_litert.interpreter import Interpreter

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "test" / "fixtures"
MODEL = REPO / "build" / "models" / "yolo26n_320_fp32.tflite"
SIZE = 320
PAD = 114
SCORE_FLOOR = 0.01
CONF = 0.25
NMS_IOU = 0.7
PHOTO_MIN_CONFIDENCE = 0.5
PHOTO_CLASSES = {0, 5}  # person, bus


def letterbox(rgb: np.ndarray, size: int) -> tuple[np.ndarray, tuple[int, int, int, int]]:
    """Ultralytics' LetterBox: returns the image and (new_w, new_h, left, top)."""
    h, w = rgb.shape[:2]
    r = min(size / w, size / h)
    nw, nh = round(w * r), round(h * r)
    resized = cv2.resize(rgb, (nw, nh), interpolation=cv2.INTER_LINEAR)
    left, top = round((size - nw) / 2 - 0.1), round((size - nh) / 2 - 0.1)
    canvas = np.full((size, size, 3), PAD, dtype=np.uint8)
    canvas[top : top + nh, left : left + nw] = resized
    return canvas, (nw, nh, left, top)


def to_tensor(rgb: np.ndarray) -> np.ndarray:
    return (rgb.astype(np.float32) / 255.0).transpose(2, 0, 1)[None]


def iou(a: np.ndarray, b: np.ndarray) -> float:
    low, high = np.maximum(a[:2], b[:2]), np.minimum(a[2:], b[2:])
    wh = np.maximum(high - low, 0)
    inter = wh[0] * wh[1]
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return float(inter / union) if union > 0 else 0.0


def preprocess_fixture() -> None:
    w, h, size = 64, 48, 32
    x, y = np.meshgrid(np.arange(w), np.arange(h))
    rgb = np.stack([x * 255 // (w - 1), y * 255 // (h - 1), (x + y) * 255 // (w + h - 2)], 2).astype(np.uint8)
    canvas, (nw, nh, left, top) = letterbox(rgb, size)
    data = {
        "width": w,
        "height": h,
        "size": size,
        "rgb": rgb.reshape(-1).tolist(),
        "new_width": nw,
        "new_height": nh,
        "left": left,
        "top": top,
        "tensor_uint8_rgb": canvas.reshape(-1).tolist(),
    }
    (OUT / "preprocess_64x48_to_32.json").write_text(json.dumps(data), encoding="utf-8")


def detector_fixture() -> None:
    image = Path(ultralytics.__file__).parent / "assets" / "bus.jpg"
    rgb = cv2.cvtColor(cv2.imread(str(image)), cv2.COLOR_BGR2RGB)
    height, width = rgb.shape[:2]
    canvas, (nw, nh, left, top) = letterbox(rgb, SIZE)

    interpreter = Interpreter(model_path=str(MODEL))
    interpreter.allocate_tensors()
    interpreter.set_tensor(interpreter.get_input_details()[0]["index"], to_tensor(canvas))
    interpreter.invoke()
    raw = interpreter.get_tensor(interpreter.get_output_details()[0]["index"])[0]
    channels, anchors = raw.shape

    # Independent decode: centre xywh normalized to the input, scores already 0-1.
    scores = raw[4:]
    classes, confidence = scores.argmax(0), scores.max(0)
    keep = np.nonzero(confidence >= CONF)[0]
    boxes = raw[:4, keep].T
    xyxy = np.stack(
        [
            boxes[:, 0] - boxes[:, 2] / 2,
            boxes[:, 1] - boxes[:, 3] / 2,
            boxes[:, 0] + boxes[:, 2] / 2,
            boxes[:, 1] + boxes[:, 3] / 2,
        ],
        1,
    )
    kept: list[int] = []
    for i in confidence[keep].argsort()[::-1]:
        same_class = [j for j in kept if classes[keep[j]] == classes[keep[i]]]
        if all(iou(xyxy[i], xyxy[j]) <= NMS_IOU for j in same_class):
            kept.append(int(i))

    expected = []
    for i in kept:
        # Input-normalized -> normalized to the upright image, clamped.
        x1, y1, x2, y2 = xyxy[i]
        expected.append(
            {
                "class": int(classes[keep[i]]),
                "confidence": float(confidence[keep[i]]),
                "box": [
                    float(np.clip((x1 * SIZE - left) / nw, 0, 1)),
                    float(np.clip((y1 * SIZE - top) / nh, 0, 1)),
                    float(np.clip((x2 * SIZE - left) / nw, 0, 1)),
                    float(np.clip((y2 * SIZE - top) / nh, 0, 1)),
                ],
            }
        )

    sparse = []
    for anchor in np.nonzero(confidence >= SCORE_FLOOR)[0]:
        sparse.append(
            {
                "anchor": int(anchor),
                "box": [float(v) for v in raw[:4, anchor]],
                "scores": {
                    str(c): float(scores[c, anchor]) for c in np.nonzero(scores[:, anchor] >= SCORE_FLOOR)[0]
                },
            }
        )
    data = {
        "source": "yolo26n_320_fp32.tflite on Ultralytics assets/bus.jpg",
        "image_width": width,
        "image_height": height,
        "size": SIZE,
        "channels": int(channels),
        "anchors": int(anchors),
        "conf": CONF,
        "nms_iou": NMS_IOU,
        "sparse_output": sparse,
        "expected": expected,
    }
    (OUT / "detector_bus_320.json").write_text(json.dumps(data), encoding="utf-8")
    print(f"{len(sparse)} of {anchors} anchors kept, {len(expected)} expected detections")


def photo_frames() -> None:
    """Real camera-like frames for the detector's end-to-end test, in build/.

    Not committed, because they contain Ultralytics' example photo. `expected` is
    the reference decode's detections at a confidence the model keeps reliably.
    """
    out = REPO / "build" / "fixtures"
    out.mkdir(parents=True, exist_ok=True)
    image = Path(ultralytics.__file__).parent / "assets" / "bus.jpg"
    bgr = cv2.imread(str(image))
    h, w = bgr.shape[:2]
    # About the size of a medium camera preset, with an even height for YUV.
    width, height = 480, round(h * 480 / w)
    height += height % 2
    small = cv2.resize(bgr, (width, height), interpolation=cv2.INTER_AREA)
    (out / "photo_upright.bgra").write_bytes(cv2.cvtColor(small, cv2.COLOR_BGR2BGRA).tobytes())

    # The sensor image that becomes `small` when turned 90 degrees clockwise.
    sensor = cv2.rotate(small, cv2.ROTATE_90_COUNTERCLOCKWISE).astype(np.float32)
    b, g, r = sensor[:, :, 0], sensor[:, :, 1], sensor[:, :, 2]
    # Full-range BT.601, what Android cameras produce.
    y = 0.299 * r + 0.587 * g + 0.114 * b
    u = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
    v = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b

    def plane(values: np.ndarray) -> bytes:
        return np.clip(values + 0.5, 0, 255).astype(np.uint8).tobytes()

    (out / "photo_sensor.y").write_bytes(plane(y))
    half = (y.shape[1] // 2, y.shape[0] // 2)
    (out / "photo_sensor.u").write_bytes(plane(cv2.resize(u, half, interpolation=cv2.INTER_AREA)))
    (out / "photo_sensor.v").write_bytes(plane(cv2.resize(v, half, interpolation=cv2.INTER_AREA)))

    expected = json.loads((OUT / "detector_bus_320.json").read_text(encoding="utf-8"))["expected"]
    confident = [e for e in expected if e["confidence"] >= PHOTO_MIN_CONFIDENCE and e["class"] in PHOTO_CLASSES]
    (out / "photo_frames.json").write_text(
        json.dumps({"width": width, "height": height, "expected": confident}), encoding="utf-8"
    )
    print(f"photo frames {width}x{height}, {len(confident)} reference detections")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    preprocess_fixture()
    detector_fixture()
    photo_frames()
    for path in sorted(OUT.glob("*.json")):
        print(f"wrote {path.relative_to(REPO)} ({path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
