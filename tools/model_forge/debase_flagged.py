#!/usr/bin/env python3
"""Debase the R2 models flagged kind=debase in the browser — remove the baked TRELLIS shadow disc.

For each rework_flags.json entry with kind=debase: download the GLB from R2, run glb_debase.py via
headless Blender, and if a disc was trimmed, re-upload the cleaned GLB under a new content-addressed
key, update assets/model_manifest.json, delete the orphaned old R2 object, and clear the flag. Models
with no detectable disc are reported and left flagged (handle manually / tune the threshold).

  ./venv/bin/python debase_flagged.py            # dry run: download + debase + report, no changes
  ./venv/bin/python debase_flagged.py --apply     # upload cleaned GLBs, update manifest, clear flags

`blender` must be on PATH. After --apply, commit assets/model_manifest.json to main.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import publish_manifest as pm

THIS = Path(__file__).resolve().parent
PROJECT_ROOT = THIS.parents[1]
MANIFEST = PROJECT_ROOT / "assets" / "model_manifest.json"
REWORK = THIS / "rework_flags.json"
TMP = THIS / ".bbtmp" / "debase"
APPLY = "--apply" in sys.argv


def r2_client():
    cfg = pm._load_r2_config("", "")
    import boto3
    from botocore.config import Config
    s3 = boto3.client("s3", endpoint_url=cfg["endpoint"], aws_access_key_id=cfg["access_key"],
                      aws_secret_access_key=cfg["secret_key"], region_name="auto",
                      config=Config(signature_version="s3v4"))
    return s3, cfg["bucket"]


def main() -> int:
    if not REWORK.exists():
        print("no rework_flags.json"); return 0
    flags = json.loads(REWORK.read_text())
    debase = {k: v for k, v in flags.items() if v.get("kind") == "debase"}
    if not debase:
        print("no kind=debase flags"); return 0
    manifest = json.loads(MANIFEST.read_text())
    TMP.mkdir(parents=True, exist_ok=True)
    s3, bucket = r2_client()
    print(f"{'APPLY' if APPLY else 'DRY RUN'}: {len(debase)} debase-flagged model(s)\n")

    trimmed, noop, changed_manifest = [], [], False
    for key in sorted(debase):
        entry = manifest["models"].get(key)
        if not entry:
            print(f"  ?? {key}: not in manifest, skip"); continue
        in_glb = TMP / "in.glb"
        out_glb = TMP / "out.glb"
        in_glb.write_bytes(s3.get_object(Bucket=bucket, Key=entry["url"])["Body"].read())
        res = subprocess.run(["blender", "-b", "-P", str(THIS / "glb_debase.py"), "--",
                              str(in_glb), str(out_glb)], capture_output=True, text=True)
        line = next((l for l in res.stdout.splitlines() if "trim" in l.lower() or "Cutting" in l), "")
        did_trim = out_glb.exists() and ("Cutting" in line or "trim" in line.lower()) and "Nothing to trim" not in line
        if not did_trim:
            print(f"  -- {key}: no disc — {line.strip() or 'no-op'} (left flagged)")
            noop.append(key); continue
        new_sha = hashlib.sha256(out_glb.read_bytes()).hexdigest()
        new_url = new_sha + ".glb"
        size = out_glb.stat().st_size
        print(f"  OK {key}: {line.strip()}  ({entry['size']/1e6:.1f}->{size/1e6:.1f}MB)")
        if APPLY:
            s3.put_object(Bucket=bucket, Key=new_url, Body=out_glb.read_bytes(),
                          ContentType="model/gltf-binary")
            old_url = entry["url"]
            entry.update({"url": new_url, "sha256": new_sha, "size": size})
            changed_manifest = True
            if old_url != new_url:
                try:
                    s3.delete_object(Bucket=bucket, Key=old_url)
                except Exception as e:  # noqa: BLE001
                    print(f"     (old object delete failed: {e})")
            flags.pop(key, None)
        trimmed.append(key)

    if APPLY and changed_manifest:
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        REWORK.write_text(json.dumps(flags, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("\nmanifest + rework_flags updated. Commit assets/model_manifest.json to main.")
    print(f"\nsummary: {len(trimmed)} trimmed, {len(noop)} no-disc"
          + ("" if APPLY else "  (dry run — re-run with --apply to ship)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
