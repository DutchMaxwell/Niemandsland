#!/usr/bin/env python3
"""Generic faction 3D conversion: every approved image in a session -> TRELLIS at the
validated final settings (resolution 1536, decimation 300000, texture 4096, RAW).

One image_to_3d + one extract_glb per unit. Resume-safe (skips units already in
glb_final/), restarts the Space on outage. Temp goes under .bbtmp (home, not the tiny
tmpfs). Export + R2 publish is a separate step (faction_publish.py).

Usage: faction_finalize.py <session_dir_name>
  e.g. faction_finalize.py robot_legions_20260606_210603
"""
from __future__ import annotations

import os
import shutil
import sys
import time
from pathlib import Path

THIS = Path(__file__).resolve().parent
PROJECT_ROOT = THIS.parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "assets" / "3d_pipeline"))

import trellis_core  # noqa: E402
from trellis_core import preprocess_image  # noqa: E402
from huggingface_hub import HfApi  # noqa: E402
from gradio_client import Client as GradioClient  # noqa: E402
from gradio_client import handle_file  # noqa: E402

if len(sys.argv) < 2:
    print("usage: faction_finalize.py <session_dir_name>", file=sys.stderr)
    raise SystemExit(2)

SESSION = sys.argv[1]
IMG_DIR = THIS / "state" / SESSION / "images"
OUT_DIR = THIS / "state" / SESSION / "glb_final"
SEED, DEC, TEX = 42, 300_000, 4096
MAX_PASSES = 8
PREP_DIR = THIS / ".bbtmp" / ("prep_" + SESSION)


def ensure_running(api, space, tok, restart):
    if restart:
        try:
            api.restart_space(space, token=tok)
            print("  restart issued", flush=True)
        except Exception as e:  # noqa: BLE001
            print("  restart err", e, flush=True)
    deadline = time.time() + 600
    while time.time() < deadline:
        st = str(api.get_space_runtime(space, token=tok).stage)
        if st == "RUNNING":
            time.sleep(12)
            return True
        if st == "SLEEPING" and not restart:
            try:
                api.restart_space(space, token=tok)
            except Exception:
                pass
            restart = True
        print("  stage:", st, flush=True)
        time.sleep(15)
    return False


def convert_one(client, img_path, out_path):
    PREP_DIR.mkdir(parents=True, exist_ok=True)
    processed = preprocess_image(img_path, output_path=PREP_DIR / f"{img_path.stem}_pre.png")
    client.predict(
        image=handle_file(str(processed)), seed=SEED, resolution=trellis_core.RESOLUTION,
        ss_guidance_strength=7.5, ss_guidance_rescale=0.7, ss_sampling_steps=12, ss_rescale_t=5.0,
        shape_slat_guidance_strength=7.5, shape_slat_guidance_rescale=0.5,
        shape_slat_sampling_steps=12, shape_slat_rescale_t=3.0,
        tex_slat_guidance_strength=1.0, tex_slat_guidance_rescale=0.0,
        tex_slat_sampling_steps=12, tex_slat_rescale_t=3.0,
        api_name="/image_to_3d",
    )
    res = client.predict(decimation_target=DEC, texture_size=TEX, api_name="/extract_glb")
    src = res[0] if isinstance(res, (tuple, list)) else res
    shutil.copy(src, out_path)


def main() -> int:
    if not IMG_DIR.is_dir():
        print(f"no images dir: {IMG_DIR}", flush=True)
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tok = (THIS / ".hf_token").read_text(encoding="utf-8").strip()
    space = (THIS / ".trellis_space").read_text(encoding="utf-8").strip()
    os.environ["HF_TOKEN"] = tok
    api = HfApi()

    units = sorted(p.stem for p in IMG_DIR.glob("*.png")
                   if not p.stem.endswith(("_PREB", "_OLD", "_orig"))
                   and "_preprocessed" not in p.stem and "_clean" not in p.stem)
    total = len(units)
    print(f"finalize {SESSION}: {total} units @ {trellis_core.RESOLUTION}/{DEC}/{TEX} RAW", flush=True)

    for p in range(MAX_PASSES):
        todo = [u for u in units if not (OUT_DIR / f"{u}.glb").exists()]
        done = total - len(todo)
        print(f"=== pass {p+1}: {done}/{total} done, {len(todo)} todo ===", flush=True)
        if not todo:
            break
        if not ensure_running(api, space, tok, restart=False):
            print("  space not RUNNING; next pass", flush=True)
            continue
        try:
            client = GradioClient(space)
        except Exception as e:  # noqa: BLE001
            print("  client err", e, flush=True)
            continue
        consec = 0
        for u in todo:
            img = IMG_DIR / f"{u}.png"
            out = OUT_DIR / f"{u}.glb"
            ok = False
            for attempt in range(2):
                try:
                    t0 = time.time()
                    convert_one(client, img, out)
                    ok = True
                    break
                except Exception as e:  # noqa: BLE001
                    print(f"  fail {u} (try {attempt+1}): {repr(e)[:140]}", flush=True)
                    time.sleep(8)
            if ok:
                done += 1
                consec = 0
                print(f"  OK [{done}/{total}] {u} ({out.stat().st_size/1e6:.1f}MB, {time.time()-t0:.0f}s)", flush=True)
            else:
                consec += 1
                print(f"  SKIP {u} after retries (consec={consec})", flush=True)
                if consec >= 4:
                    print("  4 consecutive fails -> space likely down, restart next pass", flush=True)
                    break

    final = len(list(OUT_DIR.glob("*.glb")))
    print(f"FINALIZE DONE: {final}/{total} GLBs in {SESSION}/glb_final", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
