#!/usr/bin/env python3
"""Synthesize Keychron Super Red down and up strokes.

A Super Red stroke is one impact through a short resonator bank: a low body
and a mid crack that die together. The resonators set the timbre; a measured
RMS envelope sets the loudness curve so the click stays coherent.
"""

import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
VARIANTS = 6
LENGTH = int(SR * 0.05)

# RMS from the peak, 1 ms steps, measured from Super Red preview strokes.
DOWN_RMS = (1.00, 0.72, 0.58, 0.48, 0.28, 0.23, 0.17, 0.15, 0.11, 0.09, 0.06, 0.05, 0.04, 0.03, 0.03, 0.02, 0.02, 0.02, 0.01, 0.01)
UP_RMS = (1.00, 0.48, 0.44, 0.23, 0.15, 0.17, 0.07, 0.06, 0.05, 0.04, 0.03, 0.03, 0.02, 0.02, 0.02, 0.01, 0.01, 0.01, 0.01, 0.01)
ENVS = {"down": DOWN_RMS, "up": UP_RMS}
PEAK_MS = {"down": 1.6, "up": 2.2}

BODY_CENTERS = (70, 90, 115, 140, 160, 185)
CRACK_CENTERS = {
    "down": (880, 980, 1080, 1180, 1280, 1380),
    "up": (920, 1020, 1120, 1220, 1320, 1420),
}


def impulse(samples, seed):
    out = [0.0] * samples
    rise = max(1, int(SR * 0.00008))
    fall = max(1, int(SR * 0.00022))
    for n in range(rise):
        out[n] = n / rise
    for n in range(fall):
        out[rise + n] = 1.0 - n / fall
    rng = random.Random(seed)
    previous = 0.0
    edge = int(SR * 0.00045)
    for n in range(edge):
        white = rng.uniform(-1, 1)
        highpass = white - 0.88 * previous
        previous = white
        out[n] += 0.55 * highpass * (1 - n / edge) ** 2
    return out


def resonate(excitation, freq, decay_ms, gain):
    out = [0.0] * LENGTH
    decay = math.exp(-1.0 / (SR * decay_ms / 1000))
    cos_w = math.cos(2 * math.pi * freq / SR)
    y1 = 0.0
    y2 = 0.0
    for n in range(LENGTH):
        drive = excitation[n] if n < len(excitation) else 0.0
        y0 = drive + 2 * decay * cos_w * y1 - decay * decay * y2
        out[n] = gain * y0
        y2 = y1
        y1 = y0
    return out


def cluster(excitation, center, spreads, decays, gains):
    mixed = [0.0] * LENGTH
    for spread, decay, gain in zip(spreads, decays, gains):
        layer = resonate(excitation, center * spread, decay, gain)
        for n in range(LENGTH):
            mixed[n] += layer[n]
    return mixed


def highpass_edge(excitation, gain):
    out = [0.0] * LENGTH
    previous = 0.0
    for n, sample in enumerate(excitation):
        if n >= LENGTH:
            break
        highpass = sample - 0.9 * previous
        previous = sample
        out[n] = gain * highpass
    return out


def crackle(seed, kind):
    """Short irregular edge so the onset is a click, not a pure tone."""
    rng = random.Random(seed)
    out = [0.0] * LENGTH
    previous = 0.0
    duration = int(SR * (0.004 if kind == "down" else 0.003))
    for n in range(duration):
        white = rng.uniform(-1, 1)
        highpass = white - 0.78 * previous
        previous = white
        fade = (1 - n / duration) ** 1.2
        out[n] = highpass * fade
    return out


def flatten(samples, window_ms=1.0):
    """Strip the resonators' natural envelope so the measured curve can own loudness."""
    radius = max(1, int(SR * window_ms / 1000 / 2))
    out = [0.0] * LENGTH
    for n in range(LENGTH):
        left = max(0, n - radius)
        right = min(LENGTH, n + radius + 1)
        window = samples[left:right]
        rms = math.sqrt(sum(sample * sample for sample in window) / len(window))
        out[n] = samples[n] / max(rms, 1e-5)
    return out


def amplitude_envelope(kind):
    peak_index = int(SR * PEAK_MS[kind] / 1000)
    curve = ENVS[kind]
    env = [0.0] * LENGTH
    for n in range(peak_index):
        progress = n / max(1, peak_index)
        env[n] = progress ** 0.6
    for n in range(peak_index, LENGTH):
        age_ms = (n - peak_index) / SR * 1000
        left = int(age_ms)
        if left >= len(curve) - 1:
            env[n] = curve[-1] * math.exp(-(age_ms - (len(curve) - 1)) / 4)
        else:
            frac = age_ms - left
            env[n] = curve[left] * (1 - frac) + curve[left + 1] * frac
    return env


def normalize(samples, level=0.9):
    peak = max(abs(sample) for sample in samples) or 1
    return [sample / peak * level for sample in samples]


def render(kind, variant):
    excitation = impulse(int(SR * 0.0012), seed=40 + variant * 7 + (0 if kind == "down" else 13))
    body_center = BODY_CENTERS[variant]
    crack_center = CRACK_CENTERS[kind][variant]

    if kind == "down":
        body = cluster(
            excitation,
            body_center,
            spreads=(0.75, 1.0, 1.5, 2.2),
            decays=(14.0, 11.0, 8.0, 5.5),
            gains=(0.2, 0.45, 0.18, 0.08),
        )
        crack = cluster(
            excitation,
            crack_center,
            spreads=(0.78, 1.0, 1.2, 1.45, 1.85, 2.3),
            decays=(5.0, 4.2, 3.4, 2.6, 1.8, 1.2),
            gains=(0.7, 1.3, 1.05, 0.65, 0.35, 0.18),
        )
        air = cluster(
            excitation,
            2800,
            spreads=(1.0, 1.35, 1.8, 2.3),
            decays=(1.8, 1.3, 0.9, 0.6),
            gains=(0.3, 0.2, 0.12, 0.06),
        )
        edge = highpass_edge(excitation, 0.18)
        noise = crackle(80 + variant * 5, kind)
        body_gain, crack_gain, air_gain, noise_gain = 0.1, 1.3, 0.9, 0.85
    else:
        body = cluster(
            excitation,
            body_center * 1.2,
            spreads=(0.9, 1.0, 1.55),
            decays=(8.0, 6.0, 4.5),
            gains=(0.08, 0.16, 0.06),
        )
        crack = cluster(
            excitation,
            crack_center,
            spreads=(0.72, 1.0, 1.18, 1.4, 1.7),
            decays=(3.4, 2.8, 2.1, 1.5, 1.1),
            gains=(0.75, 1.15, 1.2, 0.85, 0.45),
        )
        air = cluster(
            excitation,
            3600,
            spreads=(0.85, 1.1, 1.45, 1.9, 2.4),
            decays=(1.6, 1.2, 0.85, 0.6, 0.45),
            gains=(0.65, 0.5, 0.35, 0.22, 0.12),
        )
        edge = highpass_edge(excitation, 0.25)
        noise = crackle(90 + variant * 5, kind)
        body_gain, crack_gain, air_gain, noise_gain = 0.04, 1.25, 1.4, 1.15

    mixed = [0.0] * LENGTH
    for n in range(LENGTH):
        mixed[n] = (
            body_gain * body[n]
            + crack_gain * crack[n]
            + air_gain * air[n]
            + edge[n]
            + noise_gain * noise[n]
        )
    carrier = flatten(mixed, window_ms=0.9)
    envelope = amplitude_envelope(kind)
    shaped = [sample * gain for sample, gain in zip(carrier, envelope)]
    return normalize(shaped)


def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1, min(1, sample)) * 32767)) for sample in samples
    )
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(frames)


def main():
    root = Path(__file__).resolve().parents[2]
    destinations = [
        root / "public" / "sounds" / "super-red",
        root / "macos" / "Kleam" / "Resources",
    ]
    for kind in ("down", "up"):
        for variant in range(VARIANTS):
            samples = render(kind, variant)
            name = f"{kind}-{variant}.wav"
            for folder in destinations:
                write_wav(folder / name, samples)
    print(f"wrote {VARIANTS} down and up variants")


if __name__ == "__main__":
    main()
