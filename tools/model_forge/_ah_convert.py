#!/usr/bin/env python3
"""Overnight TRELLIS conversion of all IMAGE_APPROVED units in a session (single-view).

Mirrors review_app._convert_worker: builds image_paths from the session's approved images and runs
convert_batch (which has the A100 auto-restart logic), resume-safe (skips existing GLBs). Updates each
unit to GLB_READY. Run after the images are generated.

Usage: _ah_convert.py <session_id>
"""
from __future__ import annotations

import sys
from pathlib import Path

from pipeline_state import PipelineSession, UnitStatus
from prompt_engine import load_design_language
from trellis_bridge import convert_batch

THIS = Path(__file__).resolve().parent
STATE_DIR = THIS / "state"
DESIGN_DIR = THIS / "design_languages"


def main() -> int:
    session_id = sys.argv[1]
    session = PipelineSession.load(STATE_DIR / session_id)
    glb_dir = STATE_DIR / session_id / "glb"
    glb_dir.mkdir(parents=True, exist_ok=True)

    approved = session.get_units_by_status(UnitStatus.IMAGE_APPROVED)
    print(f"{len(approved)} IMAGE_APPROVED units")

    image_paths: dict[str, Path] = {}
    unit_classes: dict[str, str] = {}
    skipped = 0
    for u in approved:
        existing = glb_dir / f"{u.unit_key}.glb"
        if existing.exists() and existing.stat().st_size > 0:
            skipped += 1
            continue
        if u.image_path and Path(u.image_path).exists():
            image_paths[u.unit_key] = Path(u.image_path)
            unit_classes[u.unit_key] = u.unit_class or "infantry"
    print(f"resume: {skipped} GLBs already exist, {len(image_paths)} to convert")
    if not image_paths:
        print("nothing to convert")
        return 0

    token = (THIS / ".hf_token").read_text(encoding="utf-8").strip()
    space = (THIS / ".trellis_space").read_text(encoding="utf-8").strip()

    def prog(cur, tot, key):
        print(f"  [{cur}/{tot}] {key}", flush=True)

    def status(msg):
        print(f"  STATUS: {msg}", flush=True)

    results = convert_batch(
        image_paths=image_paths,
        output_dir=glb_dir,
        hf_token=token,
        preprocess=True,
        progress_callback=prog,
        space_id=space,
        unit_classes=unit_classes,
        status_callback=status,
        log_callback=lambda m: print(f"  {m}", flush=True),
    )

    ok = fail = 0
    for key, glb in results.items():
        if glb is not None:
            session.update_status(key, UnitStatus.GLB_READY, glb_path=str(glb))
            ok += 1
        else:
            fail += 1
    session.save()
    print(f"DONE: {ok} converted, {fail} failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
