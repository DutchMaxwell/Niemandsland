#!/usr/bin/env python3
"""Merge the ctex blocks from ctex_patches/*.json into assets/model_manifest.json.

Each unit's legacy url/sha256/size are left UNTOUCHED — clients without CtexLoader resolve only
those — and a `ctex` block is added beside them. Deterministic (stable input ordering, 2-space
indent to match the manifest). Safety guard: aborts if any legacy url equals the stripped ctex mesh
(old clients would then fetch a texture-less GLB).

Usage:  python3 tools/merge_ctex_manifest.py
"""
import glob
import json
import sys

MANIFEST = "assets/model_manifest.json"


def main() -> int:
    with open(MANIFEST) as f:
        man = json.load(f)
    models = man["models"]
    patches: dict = {}
    for path in sorted(glob.glob("ctex_patches/*.json")):
        with open(path) as f:
            for key, value in json.load(f).items():
                patches[key] = value
    added = 0
    missing: list = []
    unsafe: list = []
    for key, entry in models.items():
        patch = patches.get(key)
        if patch is None or "ctex" not in patch:
            missing.append(key)
            continue
        ctex = patch["ctex"]
        if ctex.get("mesh", {}).get("sha256") == entry.get("sha256"):
            unsafe.append(key)   # legacy url must NEVER be the stripped ctex mesh
            continue
        entry["ctex"] = ctex     # legacy url/sha256/size stay exactly as they were
        added += 1
    if unsafe:
        print("ABORT — legacy url == ctex.mesh (would break old clients) for:", unsafe[:10])
        return 1
    with open(MANIFEST, "w") as fo:
        json.dump(man, fo, indent=2, ensure_ascii=False)
        fo.write("\n")
    print("merged ctex into %d/%d entries; %d without a patch" % (added, len(models), len(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
