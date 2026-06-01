#!/usr/bin/env python3
"""
publish_manifest.py — build (and optionally upload) the OpenTTS model manifest.

The game loads 3D miniatures on demand (see docs/ASSET_DELIVERY.md): a small
bundled manifest maps each unit to a content-addressed GLB hosted on a CDN
(GitHub Releases). This scans the generated GLBs, computes their sha256, and
writes assets/model_manifest.json. With --upload it also pushes the GLBs to a
GitHub release via `gh`.

Manifest entry keys match ModelLibrary.make_key():  "<faction>/<unit name>"
(both lower-cased). GLB filenames follow "<NN>_<Unit Name>.glb".

Examples:
    python publish_manifest.py ../../assets/miniatures ../../assets/model_manifest.json \\
        --base-url https://github.com/OWNER/REPO/releases/download/models-v1/
    python publish_manifest.py ../../assets/miniatures ../../assets/model_manifest.json \\
        --base-url https://github.com/OWNER/REPO/releases/download/models-v1/ \\
        --upload --tag models-v1 --repo OWNER/REPO
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

NUMBERED_PREFIX = re.compile(r"^\d+_")


def unit_name_from_filename(glb: Path) -> str:
    """'01_Hive Lord.glb' -> 'Hive Lord'."""
    return NUMBERED_PREFIX.sub("", glb.stem).strip()


def model_key(faction: str, unit_name: str) -> str:
    """Mirror of ModelLibrary.make_key() (case-insensitive)."""
    return f"{faction.strip().lower()}/{unit_name.strip().lower()}"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(miniatures_dir: Path, base_url: str = "") -> dict:
    """Builds the manifest dict from assets/miniatures/<faction>/glb/*.glb."""
    models: dict[str, dict] = {}
    for glb in sorted(miniatures_dir.glob("*/glb/*.glb")):
        faction = glb.parent.parent.name
        unit_name = unit_name_from_filename(glb)
        if not unit_name:
            continue
        digest = sha256_of(glb)
        models[model_key(faction, unit_name)] = {
            "url": f"{digest}.glb",
            "sha256": digest,
            "size": glb.stat().st_size,
        }
    return {"version": 1, "base_url": base_url, "models": models}


def stage_content_addressed(miniatures_dir: Path, out_dir: Path) -> list[Path]:
    """Copies each GLB to out_dir/<sha256>.glb (for upload). Returns the paths."""
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for glb in sorted(miniatures_dir.glob("*/glb/*.glb")):
        dest = out_dir / f"{sha256_of(glb)}.glb"
        if not dest.exists():
            dest.write_bytes(glb.read_bytes())
        paths.append(dest)
    return paths


def _upload(tag: str, repo: str, files: list[Path]) -> None:
    if not files:
        return
    cmd = ["gh", "release", "upload", tag, "--repo", repo, "--clobber",
           *[str(f) for f in files]]
    subprocess.run(cmd, check=True)


def main() -> int:
    ap = argparse.ArgumentParser(description="Build/upload the OpenTTS model manifest.")
    ap.add_argument("miniatures_dir", type=Path, help=".../assets/miniatures")
    ap.add_argument("out_manifest", type=Path, help=".../assets/model_manifest.json")
    ap.add_argument("--base-url", default="",
                    help="CDN prefix, e.g. https://github.com/<o>/<r>/releases/download/<tag>/")
    ap.add_argument("--upload", action="store_true", help="Upload GLBs to a GitHub release via gh")
    ap.add_argument("--tag", default="", help="Release tag (with --upload)")
    ap.add_argument("--repo", default="", help="owner/repo (with --upload)")
    args = ap.parse_args()

    manifest = build_manifest(args.miniatures_dir, args.base_url)
    args.out_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.out_manifest} ({len(manifest['models'])} models).")

    if args.upload:
        if not args.tag or not args.repo:
            print("ERROR: --upload requires --tag and --repo", file=sys.stderr)
            return 2
        files = stage_content_addressed(args.miniatures_dir, args.out_manifest.parent / ".manifest_upload")
        _upload(args.tag, args.repo, files)
        print(f"Uploaded {len(files)} GLBs to {args.repo} release {args.tag}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
