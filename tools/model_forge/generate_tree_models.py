#!/usr/bin/env python3
"""Convert the deciduous-tree side panels into textured 3D meshes via TRELLIS.

Volumetric upgrade over the billboard quads: each keyed tree image (from
generate_trees.py) becomes a real textured tree model — like a model-railroad tree,
matching the tabletop aesthetic. Scenery settings (decimation 80k, texture 2048) keep
the GLBs light next to the 300k/4096 miniature pipeline.

Output:  assets/terrain/props/trees/<name>.glb   (git-ignored, delivered via R2)
Then:    generate_tree_models.py --upload-r2 refreshes assets/trees_manifest.json
         ("models" section) and pushes the GLBs to terrain-source/trees/.

Resume-safe: existing GLBs are skipped (delete to redo). The HF Space auto-wakes.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
import time
from pathlib import Path

THIS = Path(__file__).resolve().parent
PROJECT_ROOT = THIS.parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "assets" / "3d_pipeline"))
sys.path.insert(0, str(THIS))

import trellis_core  # noqa: E402
from huggingface_hub import HfApi  # noqa: E402
from gradio_client import Client as GradioClient  # noqa: E402
from gradio_client import handle_file  # noqa: E402
from PIL import Image  # noqa: E402

TREE_DIR = PROJECT_ROOT / "assets" / "terrain" / "props" / "trees"
MANIFEST_PATH = PROJECT_ROOT / "assets" / "trees_manifest.json"
PREP_DIR = THIS / ".bbtmp" / "prep_trees"
VARIANTS = ["tree_a", "tree_b", "tree_c",
            "desert_tree_a", "desert_tree_b", "desert_tree_c",
            "tundra_tree_a", "tundra_tree_b", "tundra_tree_c"]
SEED, DEC, TEX = 42, 100_000, 4096  # scenery floor: the Space enforces >=100k decimation, >=4096 texture
R2_PREFIX = "terrain-source/trees"


def ensure_running(api: HfApi, space: str, tok: str) -> bool:
    deadline = time.time() + 600
    restarted = False
    while time.time() < deadline:
        st = str(api.get_space_runtime(space, token=tok).stage)
        if st == "RUNNING":
            time.sleep(12)
            return True
        if st == "SLEEPING" and not restarted:
            try:
                api.restart_space(space, token=tok)
                restarted = True
            except Exception as e:  # noqa: BLE001
                print("  restart err", e, flush=True)
        print("  stage:", st, flush=True)
        time.sleep(15)
    return False


def prepare_panel(img_path: Path) -> Path:
    """Square-pad the keyed-alpha panel for TRELLIS, zeroing the RGB under alpha=0.

    trellis_core.preprocess_image is for WHITE-background renders — it would re-opaque
    every non-white pixel, resurrecting the magenta hidden under our keyed alpha. The
    panels are already clean cutouts, so they go to the Space directly.
    """
    PREP_DIR.mkdir(parents=True, exist_ok=True)
    import numpy as np  # noqa: PLC0415

    rgba = np.asarray(Image.open(img_path).convert("RGBA")).copy()
    rgba[rgba[:, :, 3] == 0] = 0  # no colour bleed from fully transparent pixels
    img = Image.fromarray(rgba, "RGBA")

    side = int(max(img.width, img.height) * 1.1)  # ~5% margin around the subject
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    out = PREP_DIR / f"{img_path.stem}_pre.png"
    canvas.save(out)
    return out


def convert_one(client: GradioClient, img_path: Path, out_path: Path) -> None:
    processed = prepare_panel(img_path)
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


def refresh_manifest_models() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    # Merge (don't reset): a themed run must not drop the other theme's models.
    manifest["models"] = manifest.get("models", {})
    for name in VARIANTS:
        glb = TREE_DIR / f"{name}.glb"
        if not glb.exists():
            continue
        data = glb.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        manifest["models"][name] = {
            # Version query busts the CDN edge cache on re-publish (stale-byte guard).
            "url": f"{name}.glb?v={sha[:8]}",
            "sha256": sha,
            "size": len(data),
        }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"manifest: {len(manifest['models'])} models", flush=True)


def upload_r2() -> int:
    from publish_manifest import _load_r2_config  # noqa: PLC0415

    cfg = _load_r2_config("", "")
    if any(not cfg[k] for k in ("access_key", "secret_key", "endpoint", "bucket")):
        print("ERROR: missing R2 config", file=sys.stderr)
        return 2
    import boto3  # noqa: PLC0415
    from botocore.config import Config  # noqa: PLC0415

    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    for name in VARIANTS:
        glb = TREE_DIR / f"{name}.glb"
        if not glb.exists():
            continue
        s3.put_object(
            Bucket=cfg["bucket"], Key=f"{R2_PREFIX}/{name}.glb", Body=glb.read_bytes(),
            ContentType="model/gltf-binary",
            CacheControl="public, max-age=86400",
        )
        print(f"uploaded {R2_PREFIX}/{name}.glb", flush=True)
    return 0


def main() -> int:
    if "--upload-r2" in sys.argv:
        refresh_manifest_models()
        return upload_r2()

    todo = [v for v in VARIANTS if not (TREE_DIR / f"{v}.glb").exists()]
    if not todo:
        print("all tree GLBs exist; nothing to do", flush=True)
        refresh_manifest_models()
        return 0

    import os  # noqa: PLC0415

    tok = (THIS / ".hf_token").read_text(encoding="utf-8").strip()
    space = (THIS / ".trellis_space").read_text(encoding="utf-8").strip()
    os.environ["HF_TOKEN"] = tok
    api = HfApi()
    print(f"trees: {len(todo)} to convert @ {trellis_core.RESOLUTION}/{DEC}/{TEX}", flush=True)
    if not ensure_running(api, space, tok):
        print("space not RUNNING", file=sys.stderr)
        return 1
    client = GradioClient(space)
    for name in todo:
        t0 = time.time()
        convert_one(client, TREE_DIR / f"{name}.webp", TREE_DIR / f"{name}.glb")
        size_mb = (TREE_DIR / f"{name}.glb").stat().st_size / 1e6
        print(f"  OK {name} ({size_mb:.1f}MB, {time.time() - t0:.0f}s)", flush=True)
    refresh_manifest_models()
    return 0


if __name__ == "__main__":
    sys.exit(main())
