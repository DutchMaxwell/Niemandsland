#!/usr/bin/env python3
"""publish_biomes.py — build (and optionally upload) the Niemandsland biome manifest.

The game loads biome battlemaps on demand (see docs/ASSET_DELIVERY.md): a small bundled
manifest maps each biome to a content-addressed WebP hosted on Cloudflare R2. This scans
assets/terrain/biomes/*.webp, computes their sha256, and writes assets/biome_manifest.json.
With --upload-r2 it also pushes each "<sha>.webp" to the R2 bucket.

Mirrors publish_manifest.py (the miniatures path) and reuses its R2 credential loading.

Examples:
    python publish_biomes.py                                  # build manifest only
    python publish_biomes.py --upload-r2                      # + upload WebPs to R2
    python publish_biomes.py --upload-r2 --bucket niemandsland --endpoint https://<id>.r2.cloudflarestorage.com
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from publish_manifest import _load_r2_config, sha256_of  # reuse the miniatures tooling

THIS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = THIS_DIR.parent.parent
DEFAULT_BIOMES_DIR = PROJECT_ROOT / "assets" / "terrain" / "biomes"
DEFAULT_OUT_MANIFEST = PROJECT_ROOT / "assets" / "biome_manifest.json"
DEFAULT_BASE_URL = "https://<legacy-cdn-host>/"


def build_biome_manifest(biomes_dir: Path, base_url: str) -> dict:
    """Build the manifest dict from assets/terrain/biomes/*.webp (key = filename stem)."""
    biomes: dict[str, dict] = {}
    for webp in sorted(biomes_dir.glob("*.webp")):
        digest = sha256_of(webp)
        biomes[webp.stem] = {
            "url": f"{digest}.webp",
            "sha256": digest,
            "size": webp.stat().st_size,
        }
    return {"version": 1, "base_url": base_url, "biomes": biomes}


def stage_content_addressed(biomes_dir: Path, out_dir: Path) -> list[Path]:
    """Copy each WebP to out_dir/<sha256>.webp (for upload). Returns the staged paths."""
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for webp in sorted(biomes_dir.glob("*.webp")):
        dest = out_dir / f"{sha256_of(webp)}.webp"
        if not dest.exists():
            dest.write_bytes(webp.read_bytes())
        paths.append(dest)
    return paths


def upload_r2(files: list[Path], cfg: dict) -> int:
    """Push content-addressed WebPs to the R2 bucket (S3 API). Immutable; skips existing."""
    missing = [k for k in ("access_key", "secret_key", "endpoint", "bucket") if not cfg[k]]
    if missing:
        print(f"ERROR: missing R2 config: {', '.join(missing)} "
              f"(set env vars or .r2_credentials)", file=sys.stderr)
        return 2
    try:
        import boto3  # noqa: PLC0415
        from botocore.config import Config  # noqa: PLC0415
        from botocore.exceptions import ClientError  # noqa: PLC0415
    except ImportError:
        print("ERROR: boto3 not installed (pip install boto3)", file=sys.stderr)
        return 2

    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    bucket = cfg["bucket"]
    uploaded = 0
    for f in files:
        key = f.name  # "<sha256>.webp"
        try:
            s3.head_object(Bucket=bucket, Key=key)
            print(f"  skip (exists): {key}")
            continue
        except ClientError:
            pass
        s3.put_object(
            Bucket=bucket, Key=key, Body=f.read_bytes(),
            ContentType="image/webp",
            CacheControl="public, max-age=31536000, immutable",
        )
        uploaded += 1
        print(f"  uploaded: {key}")
    print(f"R2: {uploaded} uploaded, {len(files) - uploaded} already present in {bucket}.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Build/upload the Niemandsland biome manifest.")
    ap.add_argument("--biomes-dir", type=Path, default=DEFAULT_BIOMES_DIR,
                    help="directory of <biome>.webp files (default: assets/terrain/biomes)")
    ap.add_argument("--out-manifest", type=Path, default=DEFAULT_OUT_MANIFEST,
                    help="manifest path (default: assets/biome_manifest.json)")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL, help="CDN prefix for the WebPs")
    ap.add_argument("--upload-r2", action="store_true",
                    help="Upload WebPs to the R2 bucket. Needs R2 creds + --bucket/--endpoint or .r2_credentials")
    ap.add_argument("--bucket", default="", help="R2 bucket name (with --upload-r2)")
    ap.add_argument("--endpoint", default="", help="R2 S3 endpoint (with --upload-r2)")
    args = ap.parse_args()

    if not args.biomes_dir.is_dir():
        print(f"ERROR: biomes dir not found: {args.biomes_dir}", file=sys.stderr)
        return 2

    manifest = build_biome_manifest(args.biomes_dir, args.base_url)
    if not manifest["biomes"]:
        print(f"ERROR: no .webp files in {args.biomes_dir} (run generate_battlemaps.py first)",
              file=sys.stderr)
        return 2
    args.out_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.out_manifest} ({len(manifest['biomes'])} biomes).")

    if args.upload_r2:
        files = stage_content_addressed(args.biomes_dir, args.out_manifest.parent / ".biome_upload")
        rc = upload_r2(files, _load_r2_config(args.bucket, args.endpoint))
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
