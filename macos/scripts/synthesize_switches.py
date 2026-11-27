#!/usr/bin/env python3
"""Synthesize original switch packs for Kleam.

Each downstroke is two hits, not one enveloped chord:
  - a bright tick at 0 ms into the crack and air modes
  - a softer, low-passed thock a few milliseconds later into the body
Upstrokes are the tick only, a little higher and quieter.
Noise lives only in the first 0.35 ms of the tick.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from dataclasses import dataclass
from pathlib import Path

SR = 44100
VARIANTS = 6
LENGTH_MS = 48.0
SLUGS = (
    "cardboard",
    "cream",
    "crystal-purple",
    "japanese-black",
    "milky-yellow",
    "oreo",
    "super-red",
)

BODY_SPREADS = (0.75, 1.0, 1.5, 2.2)
BODY_DECAYS = (14.0, 11.0, 8.0, 5.5)
BODY_PARTIALS = (0.2, 0.45, 0.18, 0.08)
CRACK_SPREADS = (0.78, 1.0, 1.2, 1.45, 1.85, 2.3)
CRACK_DECAYS = (5.0, 4.2, 3.4, 2.6, 1.8, 1.2)
CRACK_PARTIALS = (0.7, 1.3, 1.05, 0.65, 0.35, 0.18)
AIR_SPREADS = (1.0, 1.35, 1.8)
AIR_DECAYS = (1.6, 1.1, 0.7)
AIR_PARTIALS = (0.35, 0.18, 0.08)


@dataclass(frozen=True)
class Pack:
    slug: str
    thock_ms: float
    body_centers: tuple[float, ...]
    crack_down: tuple[float, ...]
    crack_up: tuple[float, ...]
    body_gain: float
    crack_gain: float
    air_gain: float
    noise: float
    air_hz: float
    air_hz_up: float
    body_decay: float
    crack_decay: float
    length_ms: float = LENGTH_MS
    # 0 = no tactile bump. Oreo uses one between the tick and the thock.
    bump_ms: float = 0.0
    # Click-bar: a second tick into a narrow high mode (Japanese Black).
    click_bar: bool = False


PACKS: dict[str, Pack] = {
    "cardboard": Pack(
        slug="cardboard",
        thock_ms=0.6,
        body_centers=(180, 210, 240, 280, 320, 360),
        crack_down=(520, 620, 720, 840, 960, 1100),
        crack_up=(640, 760, 880, 1020, 1160, 1300),
        body_gain=0.08,
        crack_gain=1.15,
        air_gain=0.35,
        noise=0.45,
        air_hz=1800,
        air_hz_up=2200,
        body_decay=0.45,
        crack_decay=0.55,
        length_ms=32.0,
    ),
    "cream": Pack(
        slug="cream",
        thock_ms=2.2,
        body_centers=(70, 85, 100, 120, 140, 160),
        crack_down=(640, 740, 860, 980, 1120, 1260),
        crack_up=(720, 840, 980, 1120, 1280, 1440),
        body_gain=1.15,
        crack_gain=0.55,
        air_gain=0.22,
        noise=0.2,
        air_hz=2000,
        air_hz_up=2400,
        body_decay=1.45,
        crack_decay=1.2,
        length_ms=64.0,
    ),
    "crystal-purple": Pack(
        slug="crystal-purple",
        thock_ms=0.45,
        body_centers=(140, 170, 200, 240, 280, 320),
        crack_down=(1400, 1600, 1850, 2100, 2400, 2700),
        crack_up=(1600, 1850, 2100, 2400, 2750, 3100),
        body_gain=0.12,
        crack_gain=0.85,
        air_gain=1.35,
        noise=0.35,
        air_hz=3400,
        air_hz_up=4200,
        body_decay=0.55,
        crack_decay=0.7,
        length_ms=36.0,
    ),
    "japanese-black": Pack(
        slug="japanese-black",
        thock_ms=0.9,
        body_centers=(90, 120, 150, 180, 210, 240),
        crack_down=(1100, 1300, 1500, 1750, 2000, 2300),
        crack_up=(1300, 1550, 1800, 2100, 2400, 2700),
        body_gain=0.16,
        crack_gain=0.7,
        air_gain=0.85,
        noise=0.3,
        air_hz=2600,
        air_hz_up=3200,
        body_decay=0.6,
        crack_decay=0.65,
        length_ms=36.0,
        click_bar=True,
    ),
    "milky-yellow": Pack(
        slug="milky-yellow",
        thock_ms=1.3,
        body_centers=(85, 105, 130, 155, 180, 210),
        crack_down=(780, 900, 1040, 1180, 1340, 1500),
        crack_up=(880, 1020, 1180, 1360, 1540, 1740),
        body_gain=0.55,
        crack_gain=0.9,
        air_gain=0.28,
        noise=0.22,
        air_hz=2100,
        air_hz_up=2500,
        body_decay=1.05,
        crack_decay=0.95,
        length_ms=46.0,
    ),
    "oreo": Pack(
        slug="oreo",
        thock_ms=3.5,
        bump_ms=2.0,
        body_centers=(80, 100, 125, 150, 175, 205),
        crack_down=(900, 1050, 1200, 1380, 1560, 1760),
        crack_up=(1000, 1180, 1360, 1560, 1780, 2000),
        body_gain=0.62,
        crack_gain=0.95,
        air_gain=0.4,
        noise=0.28,
        air_hz=2400,
        air_hz_up=3000,
        body_decay=1.05,
        crack_decay=0.9,
        length_ms=52.0,
    ),
    "super-red": Pack(
        slug="super-red",
        thock_ms=1.4,
        body_centers=(70, 90, 115, 140, 160, 185),
        crack_down=(880, 980, 1080, 1180, 1280, 1380),
        crack_up=(920, 1020, 1120, 1220, 1320, 1420),
        body_gain=0.42,
        crack_gain=1.15,
        air_gain=0.55,
        noise=0.32,
        air_hz=2800,
        air_hz_up=3400,
        body_decay=1.0,
        crack_decay=1.0,
        length_ms=48.0,
    ),
}


def tick_excitation(seed: int, noise_mix: float) -> list[float]:
    """0.3 ms asymmetric impact plus noise only in the first 0.35 ms."""
    rise = max(1, int(SR * 0.00008))
    fall = max(1, int(SR * 0.00022))
    samples = rise + fall + 4
    out = [0.0] * samples
    for n in range(rise):
        out[n] = n / rise
    for n in range(fall):
        out[rise + n] = 1.0 - n / fall
    rng = random.Random(seed)
    previous = 0.0
    edge = int(SR * 0.00035)
    for n in range(min(edge, samples)):
        white = rng.uniform(-1, 1)
        highpass = white - 0.86 * previous
        previous = white
        out[n] += noise_mix * highpass * (1 - n / edge) ** 2
    return out


def lowpass(samples: list[float], coeff: float = 0.82) -> list[float]:
    out: list[float] = []
    state = 0.0
    for sample in samples:
        state = state + (1 - coeff) * (sample - state)
        out.append(state)
    return out


def place(excitation: list[float], delay_samples: int, length: int) -> list[float]:
    out = [0.0] * length
    for index, sample in enumerate(excitation):
        at = index + delay_samples
        if 0 <= at < length:
            out[at] += sample
    return out


def add(into: list[float], layer: list[float], gain: float) -> None:
    for index, sample in enumerate(layer):
        into[index] += gain * sample


def resonate(excitation: list[float], freq: float, decay_ms: float, gain: float) -> list[float]:
    length = len(excitation)
    out = [0.0] * length
    decay = math.exp(-1.0 / (SR * max(decay_ms, 0.4) / 1000))
    cos_w = math.cos(2 * math.pi * freq / SR)
    y1 = 0.0
    y2 = 0.0
    for n, drive in enumerate(excitation):
        y0 = drive + 2 * decay * cos_w * y1 - decay * decay * y2
        out[n] = gain * y0
        y2 = y1
        y1 = y0
    return out


def cluster(
    excitation: list[float],
    center: float,
    spreads: tuple[float, ...],
    decays: tuple[float, ...],
    gains: tuple[float, ...],
    decay_scale: float,
) -> list[float]:
    mixed = [0.0] * len(excitation)
    for spread, decay, gain in zip(spreads, decays, gains):
        layer = resonate(excitation, center * spread, decay * decay_scale, gain)
        add(mixed, layer, 1.0)
    return mixed


def click_bar(excitation: list[float], delay_ms: float) -> list[float]:
    """Narrow ~2.4 kHz click, struck twice about 0.6 ms apart."""
    length = len(excitation)
    second = place(excitation, int(SR * delay_ms / 1000), length)
    drive = [a + b for a, b in zip(excitation, second)]
    bar = resonate(drive, 2400, 1.7, 1.0)
    return bar


def render(pack: Pack, kind: str, variant: int, *, mouse: bool = False) -> list[float]:
    length = int(SR * pack.length_ms / 1000)
    if mouse:
        length = max(int(SR * 0.016), int(length * 0.4))
    # Variants only nudge the thock gap and the crack center.
    gap = pack.thock_ms + (variant - 2.5) * 0.06
    crack_scale = 0.965 + variant * 0.014
    crack_center = (pack.crack_down if kind == "down" else pack.crack_up)[variant] * crack_scale
    if kind == "up":
        crack_center *= 1.06
    body_center = pack.body_centers[variant]

    seed = 40 + variant * 7 + (0 if kind == "down" else 19) + (sum(ord(c) for c in pack.slug) % 80)
    tick = place(tick_excitation(seed, pack.noise if not mouse else pack.noise * 0.4), 0, length)
    mixed = [0.0] * length

    crack = cluster(tick, crack_center, CRACK_SPREADS, CRACK_DECAYS, CRACK_PARTIALS, pack.crack_decay)
    air_hz = pack.air_hz if kind == "down" else pack.air_hz_up
    air = cluster(tick, air_hz, AIR_SPREADS, AIR_DECAYS, AIR_PARTIALS, pack.crack_decay)
    add(mixed, crack, pack.crack_gain)
    add(mixed, air, pack.air_gain)

    if pack.click_bar and not mouse:
        bar_gap = 0.6 if kind == "down" else 0.0
        if kind == "down":
            add(mixed, click_bar(tick, bar_gap), 0.85)
        else:
            add(mixed, resonate(tick, 2500, 1.2, 1.0), 0.45)

    # Downstroke bottom-out. Upstrokes stay a tick so the release is not a second press.
    if kind == "down" and not mouse:
        thock = place(lowpass(tick_excitation(seed + 3, 0.0)), max(0, int(SR * gap / 1000)), length)
        body = cluster(thock, body_center, BODY_SPREADS, BODY_DECAYS, BODY_PARTIALS, pack.body_decay)
        add(mixed, body, pack.body_gain)
        if pack.bump_ms > 0:
            bump_at = int(SR * (pack.bump_ms + (variant - 2.5) * 0.04) / 1000)
            bump = place(lowpass(tick_excitation(seed + 9, 0.05), 0.7), bump_at, length)
            bump_crack = cluster(
                bump, crack_center * 0.85, CRACK_SPREADS[:4], CRACK_DECAYS[:4], CRACK_PARTIALS[:4], pack.crack_decay * 0.7
            )
            add(mixed, bump_crack, pack.crack_gain * 0.35)

    if kind == "up":
        level = 0.5 if mouse else 0.76
    elif mouse:
        level = 0.48
    else:
        level = 0.9
    return normalize(mixed, level)


def normalize(samples: list[float], level: float) -> list[float]:
    peak = max(abs(sample) for sample in samples) or 1.0
    return [sample / peak * level for sample in samples]


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1, min(1, sample)) * 32767)) for sample in samples
    )
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(frames)


def destinations(root: Path, slug: str) -> list[Path]:
    return [
        root / "public" / "sounds" / slug,
        root / "macos" / "Kleam" / "Resources" / "sounds" / slug,
    ]


def generate_pack(root: Path, pack: Pack) -> None:
    folders = destinations(root, pack.slug)
    for folder in folders:
        folder.mkdir(parents=True, exist_ok=True)
        leftover = folder / "SOURCE.json"
        if leftover.exists():
            leftover.unlink()
    for kind in ("down", "up"):
        for variant in range(VARIANTS):
            samples = render(pack, kind, variant)
            for folder in folders:
                write_wav(folder / f"{kind}-{variant}.wav", samples)
    for kind, label in (("down", "mouse-down"), ("up", "mouse-up")):
        samples = render(pack, kind, variant=2, mouse=True)
        for folder in folders:
            write_wav(folder / f"{label}.wav", samples)


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    legacy = root / "macos" / "Kleam" / "Resources"
    for kind in ("down", "up"):
        for variant in range(VARIANTS):
            path = legacy / f"{kind}-{variant}.wav"
            if path.exists():
                path.unlink()
    for slug in SLUGS:
        generate_pack(root, PACKS[slug])
        print(f"wrote {slug}")
    print(f"wrote {len(SLUGS)} packs")


if __name__ == "__main__":
    main()
