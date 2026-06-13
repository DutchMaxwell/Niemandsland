#!/usr/bin/env python3
"""Publish a faction's converted GLBs to R2 and MERGE them into the manifest.

publish_manifest.build_manifest rebuilds from scratch by scanning every
assets/miniatures/*/glb/*.glb. Since other factions are purged locally (R2-only), a
plain run would wipe their entries — so we copy in just THIS faction's GLBs (named by
display name), build a faction-only manifest, MERGE it into model_manifest.json, then
stage + upload only the new GLBs (immutable sha256 keys -> existing are skipped).

Usage: faction_publish.py <session_dir_name>
  e.g. faction_publish.py robot_legions_20260606_210603
"""
from __future__ import annotations
import json
import shutil
import sys
from pathlib import Path

import cdn_config
import publish_manifest as pm

if len(sys.argv) < 2:
    print("usage: faction_publish.py <session_dir_name>", file=sys.stderr)
    raise SystemExit(2)

SESSION = sys.argv[1]
THIS = Path(".").resolve()
PROJECT_ROOT = THIS.parents[1]
MINI = PROJECT_ROOT / "assets" / "miniatures"
MANIFEST = PROJECT_ROOT / "assets" / "model_manifest.json"
SDIR = THIS / "state" / SESSION
BASE_URL = cdn_config.base_url("/")

sess = json.loads((SDIR / "session.json").read_text())
faction = str(sess.get("faction_folder", "")).strip().lower()
if not faction:
    print("session has no faction_folder", file=sys.stderr)
    raise SystemExit(1)
kmap = {u["unit_key"]: u["unit_name"] for u in sess.get("units", [])
        if isinstance(u, dict) and u.get("unit_key") and u.get("unit_name")}

# 1) Copy GLBs into the faction dir under their display names (manifest key = filename).
dest = MINI / faction / "glb"
dest.mkdir(parents=True, exist_ok=True)
copied = 0
for g in sorted((SDIR / "glb_final").glob("*.glb")):
    name = kmap.get(g.stem, g.stem)
    shutil.copy(g, dest / f"{name}.glb")
    copied += 1
print(f"copied {copied} GLBs -> {dest.relative_to(PROJECT_ROOT)}")

# 2) Build a faction-only manifest (only this faction has local glb/ files now).
built = pm.build_manifest(MINI, base_url=BASE_URL)
prefix = faction + "/"
bad = [k for k in built["models"] if not k.startswith(prefix)]
assert not bad, "unexpected non-%s entries: %s" % (faction, ", ".join(bad))
print(f"{faction} manifest entries: {len(built['models'])}")

# 3) Merge into the existing manifest (preserve the other factions).
existing = json.loads(MANIFEST.read_text())
before = len(existing["models"])
existing["models"].update(built["models"])
existing["base_url"] = existing.get("base_url") or BASE_URL
existing["version"] = existing.get("version", 1)
after = len(existing["models"])
MANIFEST.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
print(f"manifest merged: {before} -> {after} models")

# 4) Stage content-addressed + upload to R2 (existing hashes skipped).
files = pm.stage_content_addressed(MINI, MANIFEST.parent / ".manifest_upload")
print(f"staged content-addressed: {len(files)} files")
rc = pm._upload_r2(files, pm._load_r2_config("", ""))
print(f"R2 upload rc={rc}")
raise SystemExit(rc)
