"""Generate PLACEHOLDER audio clips so speech playback can be tested before
real Sorani recordings exist.

The clips are tones, not speech. Each placeholder file name starts with the
key it stands in for and lives under assets/audio/placeholder/, so it can
never be mistaken for a real recording. Real recordings replace them (see
docs/audio_recording.md).

Deterministic: same parameters -> byte-identical files. Standard library only.

Usage (from the repository root):
    python tools/make_placeholder_clips.py
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE_HZ = 22_050
AMPLITUDE = 0.4  # fraction of full scale; leaves headroom
FADE_MS = 8  # avoids clicks at tone edges

OUT_DIR = Path("assets/audio/placeholder")

# key -> list of (frequency Hz, duration ms); frequency 0 = silence.
# "test_sentence" stands in for «لەبەردەمت مێزێک هەیە» (3 words = 3 tones).
CLIPS: dict[str, list[tuple[float, int]]] = {
    "test_sentence": [(660, 180), (0, 70), (550, 180), (0, 70), (440, 260)],
}


def _tone(freq_hz: float, duration_ms: int) -> list[int]:
    n = int(SAMPLE_RATE_HZ * duration_ms / 1000)
    fade = int(SAMPLE_RATE_HZ * FADE_MS / 1000)
    samples = []
    for i in range(n):
        if freq_hz == 0:
            samples.append(0)
            continue
        envelope = min(1.0, i / fade, (n - 1 - i) / fade) if fade else 1.0
        value = AMPLITUDE * envelope * math.sin(2 * math.pi * freq_hz * i / SAMPLE_RATE_HZ)
        samples.append(int(value * 32767))
    return samples


def write_clip(path: Path, segments: list[tuple[float, int]]) -> None:
    samples: list[int] = []
    for freq, ms in segments:
        samples.extend(_tone(freq, ms))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)  # 16-bit PCM
        wav.setframerate(SAMPLE_RATE_HZ)
        wav.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def main() -> None:
    for key, segments in CLIPS.items():
        path = OUT_DIR / f"{key}.wav"
        write_clip(path, segments)
        print(f"wrote {path} ({sum(ms for _, ms in segments)} ms)")


if __name__ == "__main__":
    main()
