#!/usr/bin/env python3
"""Fetch the CC0 battlefield-ambience recordings and prepare them for the game.

All sources are CC0 (public domain) recordings from freesound.org — verified on each
sound page; the HQ preview MP3s are downloaded (no login needed), loudness-trimmed,
loops trimmed (noise beds wrap inaudibly) and encoded to OGG Vorbis for runtime
loading (AudioStreamOggVorbis). These REPLACE the procedural AmbienceSynth sounds at
runtime once cached; the synth stays as the offline fallback.

Output:  assets/audio/ambience/<name>.ogg  (git-ignored, delivered via R2)
Manifest: assets/ambience_manifest.json
Upload:  --upload-r2 pushes to terrain-source/ambience/.

Sources (all CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/):
- war_artillery_a: "R12-31-Artillery Guns Firing" by craigsmith
    https://freesound.org/people/craigsmith/sounds/486027/
- war_artillery_b: "Explosion Distant" by Johnnyfarmer
    https://freesound.org/people/Johnnyfarmer/sounds/209769/
- war_mg_a: "S20-23 distant sound of a Bren machine gun" by craigsmith
    https://freesound.org/people/craigsmith/sounds/675591/
- war_mg_b: "Distant Machine Gun Firing" by qubodup
    https://freesound.org/people/qubodup/sounds/854635/
- thunder_a: "Long Rumbling Thunder" by billgrip
    https://freesound.org/people/billgrip/sounds/151447/
- thunder_b: "thunder rumble 1" by FenrirFangs
    https://freesound.org/people/FenrirFangs/sounds/234736/
- rain_loop: "Soft Rain Loop" by _lynks
    https://freesound.org/people/_lynks/sounds/595717/
- fire_crackle: "Campfire 01" by HECKFRICKER
    https://freesound.org/people/HECKFRICKER/sounds/729395/
- menu_drone: "Dark Ambient Loop" by goulven
    https://freesound.org/people/goulven/sounds/371277/
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

import cdn_config

ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR = ROOT / "assets" / "audio" / "ambience"
MANIFEST_PATH = ROOT / "assets" / "ambience_manifest.json"
TMP_DIR = Path(__file__).resolve().parent / ".bbtmp" / "ambience_fetch"
R2_PREFIX = "terrain-source/ambience"
BASE_URL = cdn_config.base_url("/terrain-source/ambience")
USER_AGENT = "Mozilla/5.0 (Niemandsland asset fetch)"

# name -> { page, loop (make seamless + flag), max_s (trim) }
SOUNDS = {
    "war_artillery_a": {"page": "https://freesound.org/people/craigsmith/sounds/486027/",
                        "loop": False, "max_s": 8.0},
    "war_artillery_b": {"page": "https://freesound.org/people/Johnnyfarmer/sounds/209769/",
                        "loop": False, "max_s": 8.0},
    "war_mg_a": {"page": "https://freesound.org/people/craigsmith/sounds/675591/",
                 "loop": False, "max_s": 8.0},
    "war_mg_b": {"page": "https://freesound.org/people/qubodup/sounds/854635/",
                 "loop": False, "max_s": 8.0},
    "thunder_a": {"page": "https://freesound.org/people/billgrip/sounds/151447/",
                  "loop": False, "max_s": 14.0},
    "thunder_b": {"page": "https://freesound.org/people/FenrirFangs/sounds/234736/",
                  "loop": False, "max_s": 14.0},
    "rain_loop": {"page": "https://freesound.org/people/_lynks/sounds/595717/",
                  "loop": True, "max_s": 40.0},
    "fire_crackle": {"page": "https://freesound.org/people/HECKFRICKER/sounds/729395/",
                     "loop": True, "max_s": 25.0},
    "menu_drone": {"page": "https://freesound.org/people/goulven/sounds/371277/",
                   "loop": True, "max_s": 60.0},
}

LOG = logging.getLogger("fetch_ambience_audio")


def _http_get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def _preview_url(page_url: str) -> str:
    html = _http_get(page_url).decode("utf-8", errors="replace")
    if "Creative Commons 0" not in html and "publicdomain/zero" not in html:
        raise RuntimeError(f"NOT CC0 (refusing): {page_url}")
    match = re.search(r'https://cdn\.freesound\.org/previews/[^"]+-hq\.mp3', html)
    if not match:
        raise RuntimeError(f"no HQ preview found on {page_url}")
    return match.group(0)


def _duration_s(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


def _prepare(name: str, spec: dict, raw: Path) -> Path:
    """Trim, peak-normalize and (for loops) crossfade the tail into the head."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{name}.ogg"
    duration = min(_duration_s(raw), spec["max_s"])

    if spec["loop"]:
        # Loops: trim + normalize WITHOUT fades. The rain source is authored as a
        # loop, and for noise beds (rain, crackle) a plain cut wrap is inaudible —
        # an ffmpeg acrossfade seam turned out brittle (empty output when the tail
        # length equals the fade) and unnecessary here.
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-i", str(raw), "-t", f"{duration}",
             "-af", "alimiter=limit=0.9,loudnorm=I=-18:TP=-2",
             "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", str(out)], check=True)
    else:
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-i", str(raw), "-t", f"{duration}",
             "-af", "alimiter=limit=0.9,loudnorm=I=-18:TP=-2,afade=t=out:st="
             f"{max(0.0, duration - 0.4)}:d=0.4",
             "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", str(out)], check=True)
    LOG.info("wrote %s (%.1f s, %d KB)", out.relative_to(ROOT), duration,
             out.stat().st_size // 1024)
    return out


def write_manifest(paths: dict[str, Path]) -> None:
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest.setdefault("sounds", {})
    else:
        manifest = {"version": 1, "base_url": BASE_URL, "sounds": {}}
    for name, path in sorted(paths.items()):
        data = path.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        manifest["sounds"][name] = {
            # Version query busts the CDN edge cache on re-publish (stale-byte guard).
            "url": f"{name}.ogg?v={sha[:8]}",
            "sha256": sha,
            "size": len(data),
            "loop": SOUNDS[name]["loop"],
        }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    LOG.info("wrote %s (%d sounds)", MANIFEST_PATH.relative_to(ROOT), len(paths))


def upload_r2(paths: dict[str, Path]) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from publish_manifest import _load_r2_config  # noqa: PLC0415

    cfg = _load_r2_config("", "")
    if any(not cfg[k] for k in ("access_key", "secret_key", "endpoint", "bucket")):
        LOG.error("missing R2 config")
        return 2
    import boto3  # noqa: PLC0415
    from botocore.config import Config  # noqa: PLC0415

    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    for name, path in sorted(paths.items()):
        s3.put_object(
            Bucket=cfg["bucket"], Key=f"{R2_PREFIX}/{name}.ogg", Body=path.read_bytes(),
            ContentType="audio/ogg",
            CacheControl="public, max-age=86400",
        )
        LOG.info("uploaded %s/%s.ogg", R2_PREFIX, name)
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true", help="re-fetch even if a file exists")
    ap.add_argument("--upload-r2", action="store_true", help="push to R2 + manifest")
    args = ap.parse_args(argv)

    TMP_DIR.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for name, spec in SOUNDS.items():
        out = OUT_DIR / f"{name}.ogg"
        if out.exists() and not args.force:
            LOG.info("skip (exists): %s", out.relative_to(ROOT))
            paths[name] = out
            continue
        LOG.info("fetching %s ...", name)
        preview = _preview_url(spec["page"])
        raw = TMP_DIR / f"{name}.mp3"
        raw.write_bytes(_http_get(preview))
        paths[name] = _prepare(name, spec, raw)

    write_manifest(paths)
    if args.upload_r2:
        return upload_r2(paths)
    return 0


if __name__ == "__main__":
    sys.exit(main())
