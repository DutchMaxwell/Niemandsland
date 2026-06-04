#!/usr/bin/env python3
"""Batch 1% base/membrane trim over all GLBs in a session glb dir (idempotent, atomic).

For each <unit>.glb without a <unit>.glb.debased marker: run glb_debase (headless Blender) to a temp
file; if it succeeds (non-trivial size), atomically replace the original and drop the marker. Safe to
run repeatedly (skips already-trimmed) and concurrently with an ongoing convert (only touches files
that exist). The models are already base-less from image-stage finalize; this is the membrane safety net.

Usage: _ah_debase.py <session_id>
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

THIS = Path(__file__).resolve().parent
GLB_DEBASE = THIS / "glb_debase.py"


def main() -> int:
    glb_dir = THIS / "state" / sys.argv[1] / "glb"
    glbs = sorted(p for p in glb_dir.glob("*.glb") if not p.name.endswith(".tmp.glb"))
    done = trimmed = failed = 0
    for glb in glbs:
        marker = glb.with_suffix(".glb.debased")
        if marker.exists():
            done += 1
            continue
        tmp = glb.with_suffix(".tmp.glb")
        rc = subprocess.call(
            ["blender", "-b", "-P", str(GLB_DEBASE), "--", str(glb), str(tmp), "1.25", "0.01"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if rc == 0 and tmp.exists() and tmp.stat().st_size > 100_000:
            tmp.replace(glb)
            marker.write_text("1")
            trimmed += 1
            print(f"  trimmed {glb.name}", flush=True)
        else:
            if tmp.exists():
                tmp.unlink()
            failed += 1
            print(f"  FAILED {glb.name} (rc={rc}) — left original untouched", flush=True)
    print(f"debase: {trimmed} trimmed, {done} already done, {failed} failed (of {len(glbs)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
