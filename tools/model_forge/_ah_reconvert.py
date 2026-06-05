#!/usr/bin/env python3
"""Re-convert a session's units from scratch (sharp textures) — autonomous.

The first pass washed textures out via a Blender de-base re-encode. This: backs up the soft GLBs,
re-runs TRELLIS on the (unchanged, sharp) input images, and applies glb_sharpen (pure-Python unsharp,
no Blender) — NO lossy de-base. Loops convert_batch with Space restarts until all units have a GLB,
then sharpens. Resume-safe.

Usage: _ah_reconvert.py <session_id>
"""
from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

from huggingface_hub import HfApi
from pipeline_state import PipelineSession, UnitStatus
from trellis_bridge import convert_batch

THIS = Path(__file__).resolve().parent
STATE = THIS / "state"
TOKEN = (THIS / ".hf_token").read_text(encoding="utf-8").strip()
SPACE = (THIS / ".trellis_space").read_text(encoding="utf-8").strip()
MAX_ITERS = 6


def wait_running(api, restart=False):
    if restart:
        try:
            api.restart_space(SPACE, token=TOKEN); print("  restart issued", flush=True)
        except Exception as e:
            print("  restart err", e, flush=True)
    deadline = time.time() + 600
    while time.time() < deadline:
        st = str(api.get_space_runtime(SPACE, token=TOKEN).stage)
        if st == "RUNNING":
            time.sleep(15); return True
        print("  stage:", st, flush=True); time.sleep(15)
    return False


def main() -> int:
    sid = sys.argv[1]
    session = PipelineSession.load(STATE / sid)
    glb_dir = STATE / sid / "glb"
    backup = STATE / sid / "glb_soft_backup"

    # 1) back up the soft GLBs once, start with a clean glb dir
    if glb_dir.exists() and not backup.exists():
        glb_dir.rename(backup)
        print(f"backed up soft GLBs -> {backup.name}", flush=True)
    glb_dir.mkdir(parents=True, exist_ok=True)

    # 2) every unit that has an input image goes back to IMAGE_APPROVED for re-conversion
    units = [u for u in session.get_all_units() if u.image_path and Path(u.image_path).exists()]
    for u in units:
        session.update_status(u.unit_key, UnitStatus.IMAGE_APPROVED, glb_path=None)
    session.save()
    total = len(units)
    print(f"re-converting {total} units", flush=True)

    api = HfApi()
    prev_done = -1
    for it in range(MAX_ITERS):
        done_now = len(list(glb_dir.glob("*.glb")))
        if done_now >= total:
            break
        print(f"=== iter {it+1}: {done_now}/{total} done ===", flush=True)
        if not wait_running(api, restart=(it > 0)):
            print("  space not RUNNING — skip iter", flush=True); continue

        todo = {u.unit_key: Path(u.image_path) for u in units
                if not (glb_dir / f"{u.unit_key}.glb").exists()}
        classes = {u.unit_key: (u.unit_class or "infantry") for u in units}
        results = convert_batch(
            image_paths=todo, output_dir=glb_dir, hf_token=TOKEN, preprocess=True,
            space_id=SPACE, unit_classes=classes,
            progress_callback=lambda c, t, k: print(f"  [{c}/{t}] {k}", flush=True),
            status_callback=lambda m: print(f"  STATUS {m}", flush=True),
            log_callback=lambda m: print(f"  {m}", flush=True),
        )
        for k, p in results.items():
            if p is not None:
                session.update_status(k, UnitStatus.GLB_READY, glb_path=str(p))
        session.save()
        done = len(list(glb_dir.glob("*.glb")))
        if done == prev_done:
            print("  no progress this iter", flush=True)
        prev_done = done

    # 3) sharpen every GLB in place (pure-Python, no Blender)
    print("=== sharpening textures ===", flush=True)
    sharp = 0
    for glb in sorted(glb_dir.glob("*.glb")):
        rc = subprocess.call(["./venv/bin/python3", "glb_sharpen.py", str(glb), str(glb), "3", "150"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if rc == 0:
            sharp += 1
        else:
            print(f"  sharpen FAILED {glb.name}", flush=True)
    final = len(list(glb_dir.glob("*.glb")))
    print(f"DONE: {final}/{total} GLBs, {sharp} sharpened", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
