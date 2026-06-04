#!/usr/bin/env python3
"""Deploy (or revert) the multi-view endpoint on the TRELLIS.2 HF Space — RUN THIS YOURSELF.

Niemandsland uses single-image TRELLIS today; multi-view (front + back + sides) gives TRELLIS real
back-side data instead of a hallucinated back, which should improve quality — especially for thin
limbs/blades. The TRELLIS.2 pipeline already accepts a list of images in get_cond(); this patch makes
run() forward a list and exposes a /multiimage_to_3d API endpoint (reusing image_to_3d unchanged).

The agent prepared + syntax-validated this but was (correctly) blocked from pushing to your live Space
unattended. Run it yourself when you can watch it:

    cd tools/model_forge
    ./venv/bin/python3 multiview_patch/deploy_multiview.py          # deploy
    ./venv/bin/python3 multiview_patch/deploy_multiview.py --revert # revert to originals

It is idempotent (won't double-patch), backward-compatible (single-image is byte-identical behavior:
a list of 1), syntax-checks before upload, restarts the Space, and verifies both endpoints exist.
Reverting re-uploads the pristine originals saved next to this script.
"""
from __future__ import annotations

import ast
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
TOKEN = (TOOLS / ".hf_token").read_text(encoding="utf-8").strip()
SPACE = (TOOLS / ".trellis_space").read_text(encoding="utf-8").strip()

APP_REMOTE = "app.py"
PIPE_REMOTE = "trellis2/pipelines/trellis2_image_to_3d.py"

PIPE_OLD = ("        torch.manual_seed(seed)\n"
            "        cond_512 = self.get_cond([image], 512)\n"
            "        cond_1024 = self.get_cond([image], 1024) if pipeline_type != '512' else None")
PIPE_NEW = ("        # NIEMANDSLAND: accept a list of images (multi-view) — single image stays [image].\n"
            "        imgs = list(image) if isinstance(image, (list, tuple)) else [image]\n"
            "        torch.manual_seed(seed)\n"
            "        cond_512 = self.get_cond(imgs, 512)\n"
            "        cond_1024 = self.get_cond(imgs, 1024) if pipeline_type != '512' else None")

APP_RET = "    return state, full_html\n"
APP_FN = '''
def multiimage_to_3d(
    multiimages,
    seed: int,
    resolution: str,
    ss_guidance_strength: float,
    ss_guidance_rescale: float,
    ss_sampling_steps: int,
    ss_rescale_t: float,
    shape_slat_guidance_strength: float,
    shape_slat_guidance_rescale: float,
    shape_slat_sampling_steps: int,
    shape_slat_rescale_t: float,
    tex_slat_guidance_strength: float,
    tex_slat_guidance_rescale: float,
    tex_slat_sampling_steps: int,
    tex_slat_rescale_t: float,
    req: gr.Request,
    progress=gr.Progress(track_tqdm=True),
) -> str:
    # NIEMANDSLAND multi-view: condition on several views (front + back) of the SAME object.
    imgs = []
    for item in (multiimages or []):
        img = item[0] if isinstance(item, (list, tuple)) else item
        if isinstance(img, str):
            img = Image.open(img)
        imgs.append(img.convert("RGBA"))
    if not imgs:
        raise gr.Error("multiimage_to_3d: no images provided")
    return image_to_3d(
        imgs, seed, resolution,
        ss_guidance_strength, ss_guidance_rescale, ss_sampling_steps, ss_rescale_t,
        shape_slat_guidance_strength, shape_slat_guidance_rescale, shape_slat_sampling_steps, shape_slat_rescale_t,
        tex_slat_guidance_strength, tex_slat_guidance_rescale, tex_slat_sampling_steps, tex_slat_rescale_t,
        req, progress,
    )

'''
APP_CLICK = ("        extract_glb,\n"
             "        inputs=[output_buf, decimation_target, texture_size],\n"
             "        outputs=[glb_output, download_btn],\n"
             "    )\n")
APP_WIRING = '''
    # NIEMANDSLAND: API-only multi-view endpoint (hidden UI), reuses output_buf -> extract_glb.
    multiimage_prompt = gr.Gallery(label="Multi-view prompts", visible=False)
    multiimage_btn = gr.Button("multiimage", visible=False)
    multiimage_btn.click(
        multiimage_to_3d,
        inputs=[
            multiimage_prompt, seed, resolution,
            ss_guidance_strength, ss_guidance_rescale, ss_sampling_steps, ss_rescale_t,
            shape_slat_guidance_strength, shape_slat_guidance_rescale, shape_slat_sampling_steps, shape_slat_rescale_t,
            tex_slat_guidance_strength, tex_slat_guidance_rescale, tex_slat_sampling_steps, tex_slat_rescale_t,
        ],
        outputs=[output_buf, preview_output],
        api_name="multiimage_to_3d",
    )
'''


def _patch_pipe(text: str) -> str:
    if "imgs = list(image)" in text:
        return text  # already patched
    assert text.count(PIPE_OLD) == 1, "pipeline anchor not found (Space code changed?)"
    return text.replace(PIPE_OLD, PIPE_NEW)


def _patch_app(text: str) -> str:
    if "def multiimage_to_3d(" in text:
        return text  # already patched
    assert text.count(APP_RET) == 1, "image_to_3d return anchor not found"
    assert text.count(APP_CLICK) == 1, "extract_glb click anchor not found"
    text = text.replace(APP_RET, APP_RET + APP_FN, 1)
    text = text.replace(APP_CLICK, APP_CLICK + APP_WIRING, 1)
    return text


def _wait_running(api, deadline_s: float = 600) -> str:
    deadline = time.time() + deadline_s
    stage = "?"
    while time.time() < deadline:
        stage = str(api.get_space_runtime(SPACE, token=TOKEN).stage)
        print("  stage:", stage, flush=True)
        if stage == "RUNNING":
            return stage
        time.sleep(15)
    return stage


def main() -> int:
    from huggingface_hub import HfApi, hf_hub_download
    api = HfApi()
    revert = "--revert" in sys.argv

    if revert:
        api.upload_file(path_or_fileobj=str(HERE / "app.py.orig"), path_in_repo=APP_REMOTE,
                        repo_id=SPACE, repo_type="space", token=TOKEN,
                        commit_message="Revert multiimage_to_3d patch")
        api.upload_file(path_or_fileobj=str(HERE / "trellis2_image_to_3d.py.orig"), path_in_repo=PIPE_REMOTE,
                        repo_id=SPACE, repo_type="space", token=TOKEN,
                        commit_message="Revert multiimage_to_3d patch")
        print("reverted to originals.")
    else:
        app = Path(hf_hub_download(SPACE, APP_REMOTE, repo_type="space", token=TOKEN)).read_text()
        pipe = Path(hf_hub_download(SPACE, PIPE_REMOTE, repo_type="space", token=TOKEN)).read_text()
        app2, pipe2 = _patch_app(app), _patch_pipe(pipe)
        ast.parse(app2)
        ast.parse(pipe2)
        if app2 == app and pipe2 == pipe:
            print("already patched — nothing to upload (will still restart + verify).")
        else:
            (HERE / "_app_upload.py").write_text(app2)
            (HERE / "_pipe_upload.py").write_text(pipe2)
            api.upload_file(path_or_fileobj=str(HERE / "_app_upload.py"), path_in_repo=APP_REMOTE,
                            repo_id=SPACE, repo_type="space", token=TOKEN,
                            commit_message="Add multiimage_to_3d endpoint (multi-view, backward-compatible)")
            api.upload_file(path_or_fileobj=str(HERE / "_pipe_upload.py"), path_in_repo=PIPE_REMOTE,
                            repo_id=SPACE, repo_type="space", token=TOKEN,
                            commit_message="run(): forward image list to get_cond (multi-view)")
            print("uploaded patched app.py + pipeline.")

    print("restarting Space...")
    api.restart_space(SPACE, token=TOKEN)
    stage = _wait_running(api)
    if stage != "RUNNING":
        print(f"WARNING: Space stage={stage} (build may still be running — check the HF Space page).")
        return 1

    import os
    os.environ["HF_TOKEN"] = TOKEN
    from gradio_client import Client
    eps = list(Client(SPACE).view_api(print_info=False, return_format="dict").get("named_endpoints", {}))
    print("endpoints:", eps)
    has_img = any("image_to_3d" in e for e in eps)
    has_multi = any("multiimage" in e for e in eps)
    print(f"image_to_3d present: {has_img} | multiimage_to_3d present: {has_multi}")
    print("OK" if (has_img and (revert or has_multi)) else "VERIFY MANUALLY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
