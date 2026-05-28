"""Single-Class-Run mit konfigurierbarem Reference + Decimation.

CLI:
    test_single_class.py <class_name> [dec=100000] [tex=4096]

Beispiele:
    test_single_class.py aircraft
    test_single_class.py titan 300000
"""

from __future__ import annotations

import os
import random
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_DIR = PROJECT_ROOT / "assets" / "3d_pipeline"
sys.path.insert(0, str(PIPELINE_DIR))

import trellis_core  # noqa: E402
from trellis_core import preprocess_image  # noqa: E402

from gradio_client import Client as GradioClient  # noqa: E402
from gradio_client import handle_file  # noqa: E402


REFS = {
    "infantry": "_reference.webp",
    "walker":   "_reference_walker.webp",
    "vehicle":  "_reference_vehicle.webp",
    "aircraft": "_reference_aircraft.webp",
    "titan":    "_reference_titan.webp",
}


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in REFS:
        print(f"usage: test_single_class.py <{'/'.join(REFS)}> [dec] [tex]")
        return 1
    cls = sys.argv[1]
    dec = int(sys.argv[2]) if len(sys.argv) > 2 else 100000
    tex = int(sys.argv[3]) if len(sys.argv) > 3 else 4096

    mf = PROJECT_ROOT / "tools" / "model_forge"
    hf_token = _read(mf / ".hf_token")
    space = _read(mf / ".trellis_space") or trellis_core.DEFAULT_TRELLIS_SPACE
    if not hf_token:
        print("FEHLER: .hf_token fehlt")
        return 1
    os.environ["HF_TOKEN"] = hf_token

    ref = PROJECT_ROOT / "assets" / "miniatures" / "dao_union" / REFS[cls]
    if not ref.exists():
        print("FEHLER: Reference fehlt:", ref)
        return 1

    out_dir = Path(f"/tmp/trellis_{cls}")
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Class:    {cls}")
    print(f"Space:    {space}")
    print(f"Settings: DEC={dec}, TEX={tex}")
    print(f"Ref:      {ref}")

    processed = preprocess_image(ref)
    client = GradioClient(space)
    print("Connected.")

    seed = random.randint(0, 2147483647)
    print(f"Seed: {seed}, image_to_3d ...")
    client.predict(
        image=handle_file(str(processed)),
        seed=seed,
        resolution=trellis_core.RESOLUTION,
        ss_guidance_strength=7.5,
        ss_guidance_rescale=0.7,
        ss_sampling_steps=12,
        ss_rescale_t=5.0,
        shape_slat_guidance_strength=7.5,
        shape_slat_guidance_rescale=0.5,
        shape_slat_sampling_steps=12,
        shape_slat_rescale_t=3.0,
        tex_slat_guidance_strength=1.0,
        tex_slat_guidance_rescale=0.0,
        tex_slat_sampling_steps=12,
        tex_slat_rescale_t=3.0,
        api_name="/image_to_3d",
    )

    print(f"extract_glb (dec={dec}, tex={tex}) ...")
    glb_result = client.predict(
        decimation_target=dec,
        texture_size=tex,
        api_name="/extract_glb",
    )
    src = glb_result[0] if isinstance(glb_result, tuple) else glb_result
    dst = out_dir / f"{cls}_dec{dec}.glb"
    shutil.copy(src, dst)
    size_mb = dst.stat().st_size / (1024 * 1024)
    print(f"  -> {dst.name} ({size_mb:.2f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
