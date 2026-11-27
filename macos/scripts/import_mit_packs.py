#!/usr/bin/env python3
"""Unused. Kleam ships original synthesis, not these recordings.

Kept so a future import can be reviewed. Do not run this to replace the
banks unless the project explicitly decides to vendor MIT audio again.

Sources (MIT only — see THIRD_PARTY_NOTICES.md):
  - NovelKeys Cream · tplai / kbsim (via thock-soundpacks)
  - Everglide Crystal Purple · mechvibes
  - Everglide Oreo · mechvibes
  - Cherry MX Black ABS · mechvibes  → Kleam slug japanese-black

Packs without a clear MIT recording (cardboard, milky-yellow, super-red)
keep the in-repo synthesizer output and are not touched here.

Downloads are fetched from kamillobinski/thock-soundpacks (packaged MIT
archives). Klack / GPL / personal-use packs are never imported.
"""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PUBLIC = ROOT / "public" / "sounds"
RESOURCES = ROOT / "macos" / "Kleam" / "Resources" / "sounds"
VARIANTS = 6
SR = 44100

# Pinned thock-soundpacks zip URLs (MIT). Bump only after re-checking license.type.
PACKS = {
    "cream": {
        "url": "https://github.com/kamillobinski/thock-soundpacks/raw/refs/heads/main/keyboard/novelkeys/tplai/cream/f0cc3d8e-5b1e-4412-a3f0-8a4f70912d0e.zip",
        "id": "f0cc3d8e-5b1e-4412-a3f0-8a4f70912d0e",
        "notice": "NovelKeys Cream recordings by Thomas Lai (tplai/kbsim), MIT",
    },
    "crystal-purple": {
        "url": "https://github.com/kamillobinski/thock-soundpacks/raw/refs/heads/main/keyboard/everglide/mechvibes/crystal_purple/7a4c575c-2c5f-49f2-bcd0-966f0ac874a6.zip",
        "id": "7a4c575c-2c5f-49f2-bcd0-966f0ac874a6",
        "notice": "Everglide Crystal Purple recordings from Mechvibes, MIT",
    },
    "oreo": {
        "url": "https://github.com/kamillobinski/thock-soundpacks/raw/refs/heads/main/keyboard/everglide/mechvibes/oreo/c9f8ec9f-4fe0-414b-87ac-4d5b64be84e0.zip",
        "id": "c9f8ec9f-4fe0-414b-87ac-4d5b64be84e0",
        "notice": "Everglide Oreo recordings from Mechvibes, MIT",
    },
    "japanese-black": {
        "url": "https://github.com/kamillobinski/thock-soundpacks/raw/refs/heads/main/keyboard/cherry_mx/mechvibes/black_abs/de401889-0ccb-4522-a213-836aad88c447.zip",
        "id": "de401889-0ccb-4522-a213-836aad88c447",
        "notice": "Cherry MX Black ABS recordings from Mechvibes, MIT (mapped to Japanese Black profile)",
    },
}

LETTER_KEYS = ("a", "s", "d", "f", "j", "k", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p")


def download_zip(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, open(dest, "wb") as handle:
        shutil.copyfileobj(response, handle)


def extract(zip_path: Path, dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(["unzip", "-qo", str(zip_path), "-d", str(dest)], check=True)
    configs = list(dest.rglob("config.json"))
    if not configs:
        raise FileNotFoundError(f"no config.json in {zip_path}")
    return configs[0].parent


def to_mono_44100(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(src),
            "-ac",
            "1",
            "-ar",
            str(SR),
            "-sample_fmt",
            "s16",
            str(dest),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def read_pcm(path: Path) -> list[float]:
    with wave.open(str(path), "rb") as handle:
        assert handle.getnchannels() == 1
        assert handle.getsampwidth() == 2
        assert handle.getframerate() == SR
        raw = handle.readframes(handle.getnframes())
    return [sample / 32768 for sample in struct.unpack("<" + "h" * (len(raw) // 2), raw)]


def write_pcm(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1, min(1, sample)) * 32767)) for sample in samples
    )
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(frames)


def normalize(samples: list[float], level: float = 0.9) -> list[float]:
    peak = max((abs(sample) for sample in samples), default=0.0) or 1.0
    return [sample / peak * level for sample in samples]


def fade_tail(samples: list[float], ms: float = 4.0) -> list[float]:
    fade = max(1, int(SR * ms / 1000))
    out = samples[:]
    for index in range(fade):
        out[-(index + 1)] *= index / fade
    return out


def derive_up(down: list[float]) -> list[float]:
    """When a pack has no key-up, use a quieter shortened press as the release."""
    keep = max(int(len(down) * 0.55), int(SR * 0.012))
    keep = min(keep, len(down))
    return fade_tail([sample * 0.72 for sample in down[:keep]], ms=3.0)


def derive_mouse(samples: list[float], level: float = 0.5) -> list[float]:
    keep = max(int(len(samples) * 0.45), int(SR * 0.008))
    keep = min(keep, len(samples))
    return fade_tail([sample * level for sample in samples[:keep]], ms=2.5)


def collect_named(sounds: dict, stroke: str) -> list[str]:
    files: list[str] = []
    default = sounds.get("default") or {}
    for name in default.get(stroke) or []:
        if name not in files:
            files.append(name)
    for key in LETTER_KEYS:
        entry = sounds.get(key) or {}
        for name in entry.get(stroke) or []:
            if name not in files:
                files.append(name)
    return files


def pad_cycle(items: list, count: int) -> list:
    if not items:
        raise ValueError("empty sample list")
    return [items[index % len(items)] for index in range(count)]


def import_pack(slug: str, meta: dict, work: Path) -> dict:
    zip_path = work / f"{slug}.zip"
    unpack = work / slug
    print(f"fetch {slug}")
    download_zip(meta["url"], zip_path)
    pack_dir = extract(zip_path, unpack)
    config = json.loads((pack_dir / "config.json").read_text())
    license_type = (config.get("license") or {}).get("type", "")
    if license_type.upper() != "MIT":
        raise RuntimeError(f"{slug}: refused non-MIT license {license_type!r}")

    sounds = config["sounds"]
    down_names = collect_named(sounds, "down")
    up_names = collect_named(sounds, "up")
    if not down_names:
        raise RuntimeError(f"{slug}: no down samples in config")

    converted = work / f"{slug}-converted"
    converted.mkdir(parents=True, exist_ok=True)

    def convert(name: str) -> Path:
        src = pack_dir / name
        if not src.exists():
            raise FileNotFoundError(src)
        dest = converted / name.replace("/", "_")
        if not dest.exists():
            to_mono_44100(src, dest)
        return dest

    down_paths = pad_cycle([convert(name) for name in down_names], VARIANTS)
    down_pcm = [normalize(read_pcm(path)) for path in down_paths]

    if up_names:
        up_paths = pad_cycle([convert(name) for name in up_names], VARIANTS)
        up_pcm = [normalize(read_pcm(path)) for path in up_paths]
        up_source = "recorded"
    else:
        up_pcm = [normalize(derive_up(samples)) for samples in down_pcm]
        up_source = "derived-from-down"

    mouse_down = normalize(derive_mouse(down_pcm[0], 0.48))
    mouse_up = normalize(derive_mouse(up_pcm[0], 0.42))

    destinations = [PUBLIC / slug, RESOURCES / slug]
    for folder in destinations:
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True, exist_ok=True)
        for index, samples in enumerate(down_pcm):
            write_pcm(folder / f"down-{index}.wav", samples)
        for index, samples in enumerate(up_pcm):
            write_pcm(folder / f"up-{index}.wav", samples)
        write_pcm(folder / "mouse-down.wav", mouse_down)
        write_pcm(folder / "mouse-up.wav", mouse_up)

    provenance = {
        "slug": slug,
        "source_id": meta["id"],
        "source_url": meta["url"],
        "license": "MIT",
        "notice": meta["notice"],
        "upstream_name": (config.get("metadata") or {}).get("name"),
        "upstream_brand": (config.get("metadata") or {}).get("brand"),
        "upstream_author": (config.get("metadata") or {}).get("author"),
        "up_source": up_source,
        "down_files": down_names[:VARIANTS],
        "up_files": up_names[:VARIANTS],
    }
    print(f"wrote {slug} ({up_source})")
    return provenance


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="kleam-mit-") as tmp:
        work = Path(tmp)
        all_prov = []
        for slug, meta in PACKS.items():
            all_prov.append(import_pack(slug, meta, work))
    index = ROOT / "macos" / "scripts" / "mit_pack_sources.json"
    index.write_text(json.dumps(all_prov, indent=2) + "\n")
    print(f"index {index}")


if __name__ == "__main__":
    main()
