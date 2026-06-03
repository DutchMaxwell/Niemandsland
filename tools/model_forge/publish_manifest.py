#!/usr/bin/env python3
"""
publish_manifest.py — build (and optionally upload) the Niemandsland model manifest.

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
import os
import re
import subprocess
import sys
from pathlib import Path

NUMBERED_PREFIX = re.compile(r"^\d+_")
THIS_DIR = Path(__file__).resolve().parent
# Build-machine-only R2 credentials (NEVER shipped to the client; the public bucket needs
# no key for anonymous GET). Mirrors the .gemini_key secret pattern.
R2_CRED_FILE = THIS_DIR / ".r2_credentials"


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


def _load_r2_config(cli_bucket: str, cli_endpoint: str) -> dict:
    """R2 config from env vars, then .r2_credentials (KEY=VALUE lines); CLI overrides."""
    cfg: dict[str, str] = {}
    if R2_CRED_FILE.exists():
        for line in R2_CRED_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            cfg[key.strip()] = value.strip()

    def get(name: str) -> str:
        return os.environ.get(name) or cfg.get(name, "")

    return {
        "access_key": get("R2_ACCESS_KEY_ID"),
        "secret_key": get("R2_SECRET_ACCESS_KEY"),
        "endpoint": cli_endpoint or get("R2_ENDPOINT"),
        "bucket": cli_bucket or get("R2_BUCKET"),
    }


def _upload_r2(files: list[Path], cfg: dict) -> int:
    """Push the content-addressed GLBs to a Cloudflare R2 bucket (S3 API, via boto3).

    Objects are immutable (named by sha256), so existing keys are skipped, and each gets a
    long immutable Cache-Control so Cloudflare's edge caches it globally.
    """
    missing = [k for k in ("access_key", "secret_key", "endpoint", "bucket") if not cfg[k]]
    if missing:
        print(f"ERROR: missing R2 config: {', '.join(missing)} "
              f"(set env vars or {R2_CRED_FILE.name})", file=sys.stderr)
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
        key = f.name  # "<sha256>.glb"
        try:
            s3.head_object(Bucket=bucket, Key=key)
            print(f"  skip (exists): {key}")
            continue
        except ClientError:
            pass
        s3.put_object(
            Bucket=bucket, Key=key, Body=f.read_bytes(),
            ContentType="model/gltf-binary",
            CacheControl="public, max-age=31536000, immutable",
        )
        uploaded += 1
        print(f"  uploaded: {key}")
    print(f"R2: {uploaded} uploaded, {len(files) - uploaded} already present in {bucket}.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Build/upload the Niemandsland model manifest.")
    ap.add_argument("miniatures_dir", type=Path, help=".../assets/miniatures")
    ap.add_argument("out_manifest", type=Path, help=".../assets/model_manifest.json")
    ap.add_argument("--base-url", default="",
                    help="CDN prefix, e.g. https://github.com/<o>/<r>/releases/download/<tag>/")
    ap.add_argument("--upload", action="store_true", help="Upload GLBs to a GitHub release via gh")
    ap.add_argument("--tag", default="", help="Release tag (with --upload)")
    ap.add_argument("--repo", default="", help="owner/repo (with --upload)")
    ap.add_argument("--upload-r2", action="store_true",
                    help="Upload GLBs to a Cloudflare R2 bucket (S3 API). Needs R2 creds + --bucket/--endpoint or .r2_credentials")
    ap.add_argument("--bucket", default="", help="R2 bucket name (with --upload-r2)")
    ap.add_argument("--endpoint", default="",
                    help="R2 S3 endpoint, e.g. https://<accountid>.r2.cloudflarestorage.com (with --upload-r2)")
    args = ap.parse_args()

    manifest = build_manifest(args.miniatures_dir, args.base_url)
    args.out_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.out_manifest} ({len(manifest['models'])} models).")

    if args.upload or args.upload_r2:
        files = stage_content_addressed(args.miniatures_dir, args.out_manifest.parent / ".manifest_upload")
        if args.upload:
            if not args.tag or not args.repo:
                print("ERROR: --upload requires --tag and --repo", file=sys.stderr)
                return 2
            _upload(args.tag, args.repo, files)
            print(f"Uploaded {len(files)} GLBs to {args.repo} release {args.tag}.")
        if args.upload_r2:
            rc = _upload_r2(files, _load_r2_config(args.bucket, args.endpoint))
            if rc != 0:
                return rc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
