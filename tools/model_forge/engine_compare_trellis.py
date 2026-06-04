#!/usr/bin/env python3
"""Run TRELLIS on the approved Battle Brothers hero image for the engine comparison.

Loads the HF token + space exactly like batch_generate.py, converts the hero image to a
GLB, and writes it (plus timing) to engine_comparison/trellis/. Standalone so it can run
in the background while the rest of the comparison proceeds.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from huggingface_hub import HfApi
from trellis_bridge import convert_image_to_glb

THIS_DIR = Path(__file__).resolve().parent
# Optional CLI overrides: argv[1] = input image, argv[2] = output dir.
HERO = Path(sys.argv[1]) if len(sys.argv) > 1 else THIS_DIR / "references" / "battle_brothers" / "01_hero_FINAL.png"
OUT_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else THIS_DIR / "engine_comparison" / "trellis"
TOKEN_FILE = THIS_DIR / ".hf_token"
SPACE_FILE = THIS_DIR / ".trellis_space"

# The A100 Space sleeps when idle; a cold boot + model load takes minutes, during which
# the first /convert call ReadTimeouts. Wait for RUNNING (+buffer), then convert with retries.
BOOT_TIMEOUT_S = 600.0
POLL_S = 12.0
POST_RUNNING_BUFFER_S = 20.0
MAX_ATTEMPTS = 3
RETRY_BACKOFF_S = 25.0


def _read(p: Path) -> str | None:
    if p.exists():
        v = p.read_text(encoding="utf-8").strip()
        return v or None
    return None


def _wait_running(api: HfApi, space: str, token: str | None) -> str:
    """Poll the Space until stage==RUNNING (or timeout). Returns the final stage."""
    deadline = time.time() + BOOT_TIMEOUT_S
    stage = "?"
    while time.time() < deadline:
        try:
            stage = str(api.get_space_runtime(space, token=token).stage)
        except Exception as exc:  # noqa: BLE001
            stage = f"?({type(exc).__name__})"
        print(f"[trellis] Space stage={stage} (+{int(time.time() - (deadline - BOOT_TIMEOUT_S))}s)", flush=True)
        if stage == "RUNNING":
            print(f"[trellis] RUNNING — buffering {POST_RUNNING_BUFFER_S:.0f}s for model load", flush=True)
            time.sleep(POST_RUNNING_BUFFER_S)
            return stage
        time.sleep(POLL_S)
    return stage


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    token = _read(TOKEN_FILE)
    space = _read(SPACE_FILE)
    print(f"hero    : {HERO}  (exists={HERO.exists()})")
    print(f"space   : {space or 'DEFAULT'}")
    print(f"token   : {'present' if token else 'MISSING'}")
    print(f"out_dir : {OUT_DIR}")

    if space:
        _wait_running(HfApi(), space, token)

    t0 = time.time()
    glb = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        print(f"[trellis] convert attempt {attempt}/{MAX_ATTEMPTS}", flush=True)
        try:
            glb = convert_image_to_glb(
                HERO,
                OUT_DIR,
                hf_token=token,
                preprocess=True,
                space_id=space,
                unit_class="infantry",
                log_callback=lambda m: print(f"[trellis] {m}", flush=True),
            )
        except Exception as exc:  # noqa: BLE001
            print(f"[trellis] attempt {attempt} raised {type(exc).__name__}: {exc}", flush=True)
            glb = None
        if glb is not None:
            break
        if attempt < MAX_ATTEMPTS:
            print(f"[trellis] retrying in {RETRY_BACKOFF_S:.0f}s…", flush=True)
            time.sleep(RETRY_BACKOFF_S)
    elapsed = time.time() - t0

    result = {
        "engine": "TRELLIS",
        "ok": glb is not None,
        "glb": str(glb) if glb else None,
        "size_bytes": glb.stat().st_size if glb else None,
        "seconds": round(elapsed, 1),
    }
    (OUT_DIR / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"RESULT: {json.dumps(result)}")
    return 0 if glb else 1


if __name__ == "__main__":
    raise SystemExit(main())
