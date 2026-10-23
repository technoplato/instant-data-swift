#!/usr/bin/env python3
"""Wideband PESQ (ITU-T P.862.2) of decoded audio against its 16 kHz reference, in 10 s windows (#1012, ADR 0021).

    score_pesq.py <reference-16k.wav> <decoded-16k.wav> [<decoded-16k.wav> ...]

Prints one JSON line per decoded file: the median and mean MOS-LQO over the windows that hold speech, and the delay
removed before scoring. PESQ is defined for speech; windows quieter than -45 dBFS RMS are skipped as silence.
"""
import json
import sys

import numpy as np
import soundfile as sf
from pesq import pesq
from scipy.signal import correlate

RATE = 16_000
WINDOW = 10 * RATE


def load(path):
    data, rate = sf.read(path, dtype="float32")
    if rate != RATE:
        raise SystemExit(f"{path}: expected {RATE} Hz, got {rate}")
    return data if data.ndim == 1 else data[:, 0]


def delay(reference, degraded, max_shift=RATE // 2):
    """Samples to drop from the start of `degraded` so it lines up with `reference` (positive: degraded is late)."""
    a = reference[: 60 * RATE]
    b = degraded[: 60 * RATE + max_shift]
    corr = correlate(b, a, mode="full", method="fft")
    zero = len(a) - 1
    window = corr[zero - max_shift : zero + max_shift + 1]
    return int(np.argmax(window)) - max_shift


def score(reference, degraded):
    shift = delay(reference, degraded)
    if shift > 0:
        degraded = degraded[shift:]
    elif shift < 0:
        degraded = np.concatenate([np.zeros(-shift, dtype=degraded.dtype), degraded])
    n = min(len(reference), len(degraded))
    scores = []
    for start in range(0, n - WINDOW + 1, WINDOW):
        ref = reference[start : start + WINDOW]
        deg = degraded[start : start + WINDOW]
        rms = float(np.sqrt(np.mean(ref.astype(np.float64) ** 2)))
        if rms < 10 ** (-45 / 20):
            continue
        try:
            scores.append(pesq(RATE, ref, deg, "wb"))
        except Exception:  # NoUtterancesError and friends: no speech PESQ can find
            continue
    return shift, scores


def main():
    reference = load(sys.argv[1])
    for path in sys.argv[2:]:
        shift, scores = score(reference, load(path))
        print(
            json.dumps(
                {
                    "kind": "pesq",
                    "file": path.rsplit("/", 1)[-1],
                    "windows": len(scores),
                    "pesqWBMedian": round(float(np.median(scores)), 3) if scores else None,
                    "pesqWBMean": round(float(np.mean(scores)), 3) if scores else None,
                    "pesqWBMin": round(float(np.min(scores)), 3) if scores else None,
                    "delaySamples": shift,
                },
                sort_keys=True,
            ),
            flush=True,
        )


if __name__ == "__main__":
    main()
