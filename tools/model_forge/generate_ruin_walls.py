#!/usr/bin/env python3
"""Generate the Niemandsland ruin-wall texture set: one tileable mossy masonry sheet + an
inset two-light Gothic window, then derive the per-cell damage / opening / crumble panels
and a normal map. Output -> assets/terrain/props/ruins/<name>.webp (the approved art set).

This consolidates the iterative prototyping into one reproducible pipeline. Every panel is
derived from a SINGLE Gemini masonry render, so the whole set is internally consistent and
re-deriving the variants (step 3+4) is free once the masonry exists.

Pipeline
--------
  1. MASONRY  (Gemini) - one seamless top-down "medium mossy grey coursed stone" wall sheet
                         -> masonry_source.webp  (also the basis for everything below).
  2. WINDOW   (Gemini + PIL) - a front-on two-light Gothic tracery window whose glazed
                         lights are flat MAGENTA and whose surround is flat GREEN. PIL
                         chroma-keys the magenta to see-through alpha, crops the green away,
                         colour-harmonises the window stone to the wall, and insets it on a
                         solid masonry panel -> window.webp  (RGBA, alpha-scissor).
  3. VARIANTS (PIL) - block-aligned panels the renderer picks per wall cell:
                         solid_a / solid_b  (full, B is an offset variant of A)
                         topdmg_a           (top course knocked out)
                         opening_a          (a doorway column removed)
                         crumble_a/b/steep  (stepped diagonal taper toward a free end)
                         Removed stone becomes alpha=0 (TRANSPARENCY_ALPHA_SCISSOR in 3D).
  4. NORMAL   (PIL) - normal map baked from the masonry's own luminance (recessed mortar
                         joints read as lower) so the flat panels catch raking light.

Design note (do not "fix"): the damage/crumble grid is NEVER drawn onto the texture. The
user explicitly rejected overlaid lines / a "CAD" look. The grid only decides which WHOLE
stones to knock out of the alpha, so breakage follows the photographed courses. Likewise
the stone scale is deliberately MEDIUM (~6 stones across) and dirty/mossy - earlier "fine"
and "large" renders were both rejected.

Run with the model_forge venv (needs google-genai + Pillow + numpy + a Gemini key in
.gemini_key, or the GEMINI_API_KEY / GOOGLE_API_KEY env var):

    cd tools/model_forge && ./venv/bin/python3 generate_ruin_walls.py
    ./venv/bin/python3 generate_ruin_walls.py --only variants   # re-derive PIL panels only
    ./venv/bin/python3 generate_ruin_walls.py --only window      # re-key the window only
    ./venv/bin/python3 generate_ruin_walls.py --force            # re-render from Gemini too

The textures are committed under assets/terrain/props/ruins/ (small, ~4 MB) and are the
authoritative art; this script documents and reproduces how they were made. See
docs/HANDOFF_RUIN_WALLS.md for how the renderer consumes them.
"""
from __future__ import annotations

import argparse
import io
import logging
import os
import random
import sys
from pathlib import Path

import numpy as np
from google import genai
from google.genai import types
from PIL import Image, ImageDraw, ImageFilter

THIS_DIR: Path = Path(__file__).resolve().parent
GEMINI_KEY_FILE: Path = THIS_DIR / ".gemini_key"
OUT_DIR: Path = THIS_DIR.parent.parent / "assets" / "terrain" / "props" / "ruins"

# Nano Banana Pro first (highest native res + flexible aspect), classic flash-image as a
# fallback for keys without Pro access.
MODELS: list[str] = ["gemini-3-pro-image", "gemini-2.5-flash-image"]

# Working resolution for the derived panels. 800x720 ~= the 3" x 2.5" wall-cell aspect.
PANEL_W: int = 800
PANEL_H: int = 720

# Medium-stone damage grid (matches the ~6-stones-across masonry). Tuning these changes how
# coarse the knocked-out blocks are; keep in step with the masonry stone size.
GRID_ROW_H: float = PANEL_H / 11.0   # nominal course height
GRID_BLOCK_W: float = PANEL_W / 6.0  # nominal block width

# --- Gemini prompts (verbatim - these produced the approved art) ---------------------------

MASONRY_PROMPT: str = (
    "Seamless tileable top-down orthographic texture of an old weathered castle wall of "
    "MEDIUM coursed grey stone blocks, roughly 6 stones across the width (medium size, not "
    "large, not tiny). Weathered and dirty: patches of green moss and lichen, dark grime and "
    "water staining, soil packed into the recessed mortar joints. Natural deep recessed "
    "joints. Photorealistic, detailed, flat even lighting with no directional shadows, tiles "
    "seamlessly. No drawn lines, no grid overlay, no text, no border, no watermark."
)

# The two glazed lights are flat magenta and the surround flat green so PIL can key both
# (magenta -> see-through opening, green -> outside-the-frame crop).
WINDOW_PROMPT: str = (
    "Front-on orthographic view of a two-light Gothic tracery window built of the SAME rough "
    "grey weathered castle stone as a medieval wall (grey limestone, NOT sandstone): pointed "
    "equilateral outer arch, slender central mullion, two narrow pointed lancet lights, "
    "intersecting bar tracery at the head. The two glazed light openings are filled FLAT PURE "
    "MAGENTA (255,0,255). The entire area outside the window's outer stone frame is FLAT PURE "
    "GREEN (0,255,0). Only the grey stone window is stone-coloured. Even flat lighting, no "
    "shadows, no background, no text, centered, fills the frame vertically."
)

LOG = logging.getLogger("generate_ruin_walls")


# ==============================================================================
# GEMINI
# ==============================================================================

def _load_key() -> str:
    if GEMINI_KEY_FILE.exists():
        key = GEMINI_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""


def _generate(client: genai.Client, prompt: str, aspects: list[str]) -> bytes | None:
    """Return raw image bytes for the first model/aspect that yields an image."""
    for model in MODELS:
        for aspect in aspects:
            try:
                cfg = types.GenerateContentConfig(
                    response_modalities=["IMAGE"],
                    image_config=types.ImageConfig(aspect_ratio=aspect, image_size="2K"),
                )
                resp = client.models.generate_content(model=model, contents=[prompt], config=cfg)
                for cand in (resp.candidates or []):
                    for part in (cand.content.parts or []):
                        data = getattr(getattr(part, "inline_data", None), "data", None)
                        if data:
                            LOG.info("rendered via %s (%s)", model, aspect)
                            return data
            except Exception as exc:  # noqa: BLE001 - best-effort across models/aspects
                LOG.warning("%s/%s failed: %s", model, aspect, str(exc)[:120])
    return None


def generate_masonry(client: genai.Client) -> Image.Image:
    """Render the base masonry sheet and persist it as masonry_source.webp."""
    data = _generate(client, MASONRY_PROMPT, ["1:1"])
    if not data:
        raise RuntimeError("Gemini returned no masonry image")
    img = Image.open(io.BytesIO(data)).convert("RGB")
    _save(img, "masonry_source")
    LOG.info("masonry %s", img.size)
    return img


def generate_window(client: genai.Client, base: Image.Image) -> None:
    """Render the Gothic window, chroma-key it, harmonise it to `base`, inset -> window.webp."""
    data = _generate(client, WINDOW_PROMPT, ["2:3", "3:4", "1:1"])
    if not data:
        raise RuntimeError("Gemini returned no window image")
    wimg = Image.open(io.BytesIO(data)).convert("RGB")

    # Fit the window inside the panel (97% tall, centered), on a solid masonry base.
    th = int(PANEL_H * 0.97)
    tw = min(int(th * wimg.width / wimg.height), int(PANEL_W * 0.92))
    wimg = wimg.resize((tw, th), Image.LANCZOS)
    panel = base.convert("RGB").resize((PANEL_W, PANEL_H), Image.LANCZOS)

    w = np.asarray(wimg).astype(np.int16)
    magenta = (w[:, :, 0] > 150) & (w[:, :, 1] < 95) & (w[:, :, 2] > 150)   # glazed lights
    green = (w[:, :, 0] < 95) & (w[:, :, 1] > 150) & (w[:, :, 2] < 95)       # outside frame
    stone = ~(magenta | green)
    # Erode the stone mask to bite off the chroma-key fringe around the frame edges.
    stone_e = np.asarray(
        Image.fromarray((stone * 255).astype("uint8"), "L").filter(ImageFilter.MinFilter(7))
    ) > 127

    # Colour-harmonise the window stone toward the wall's mean so it reads as the same rock.
    win = np.asarray(wimg).astype(np.float32)
    wall_mean = np.asarray(panel).astype(np.float32).reshape(-1, 3).mean(0)
    win_mean = win[stone_e].mean(0) if stone_e.any() else win.reshape(-1, 3).mean(0)
    gain = np.clip(wall_mean / np.maximum(win_mean, 1e-3), 0.6, 1.7)
    gain_soft = 1.0 + (gain - 1.0) * 0.7
    win_adj = np.clip(win * gain_soft, 0, 255)

    res = np.asarray(panel).astype(np.uint8).copy()
    alpha = np.full((PANEL_H, PANEL_W), 255, np.uint8)
    ox = (PANEL_W - tw) // 2
    oy = (PANEL_H - th) // 2
    reg = res[oy:oy + th, ox:ox + tw]
    rega = alpha[oy:oy + th, ox:ox + tw]
    reg[stone_e] = win_adj[stone_e].astype(np.uint8)         # paint the window stone in
    rega[magenta & (~stone_e)] = 0                            # punch the lights see-through
    res[oy:oy + th, ox:ox + tw] = reg
    alpha[oy:oy + th, ox:ox + tw] = rega

    out = Image.fromarray(res, "RGB")
    out.putalpha(Image.fromarray(alpha, "L"))
    _save(out, "window")
    LOG.info("window keyed (stone %.1f%%, lights %.1f%%)",
             100 * stone_e.mean(), 100 * (magenta & ~stone_e).mean())


# ==============================================================================
# PIL VARIANTS + NORMAL (derived from the masonry sheet)
# ==============================================================================

def _block_grid() -> list[tuple[int, float, float, float, float]]:
    """A jittered (row, x0, x1, y0, y1) block grid used ONLY to choose which whole stones to
    knock out. Never drawn. Deterministic so re-runs reproduce the same breakage."""
    lay = random.Random(7)
    rows: list[tuple[float, float]] = []
    y = 0.0
    while y < PANEL_H - 2:
        y1 = min(PANEL_H, y + GRID_ROW_H * lay.uniform(0.82, 1.2))
        rows.append((y, y1))
        y = y1
    rows[-1] = (rows[-1][0], PANEL_H)
    blocks: list[tuple[int, float, float, float, float]] = []
    for r, (y0, y1) in enumerate(rows):
        x = -lay.uniform(0.2, 0.9) * GRID_BLOCK_W
        while x < PANEL_W:
            x1 = x + GRID_BLOCK_W * lay.uniform(0.72, 1.4)
            blocks.append((r, x, x1, y0, y1))
            x = x1
    return blocks


def _alpha_minus(removed: list[tuple[int, float, float, float, float]]) -> Image.Image:
    """Full-opaque alpha with the `removed` blocks punched to 0."""
    a = Image.new("L", (PANEL_W, PANEL_H), 255)
    d = ImageDraw.Draw(a)
    for (_r, x0, x1, y0, y1) in removed:
        d.rectangle([int(x0), int(y0), int(x1), int(y1)], fill=0)
    return a


def build_variants(masonry: Image.Image) -> int:
    """Derive the block-aligned panels from the masonry sheet. Returns the course count."""
    mas = masonry.convert("RGB").resize((PANEL_W, PANEL_H), Image.LANCZOS)
    # Offset variant so neighbouring cells do not read as one repeated tile.
    mas_b = Image.fromarray(np.roll(np.asarray(mas), (PANEL_W // 2, PANEL_H // 3), axis=(1, 0)))

    blocks = _block_grid()
    rows = max(b[0] for b in blocks) + 1

    def save_rgba(rgb: Image.Image, alpha: Image.Image, name: str) -> None:
        img = rgb.copy()
        img.putalpha(alpha)
        _save(img, name)

    full = Image.new("L", (PANEL_W, PANEL_H), 255)
    save_rgba(mas, full, "solid_a")
    save_rgba(mas_b, full, "solid_b")

    # topdmg: a few of the top two courses knocked out (a battered wall-head).
    td = [b for b in blocks if b[0] <= 1 and random.Random(int(b[1]) + 99).random() < 0.4]
    save_rgba(mas, _alpha_minus(td), "topdmg_a")

    # opening: a doorway-like vertical column removed near a random x, mid-height.
    cc = random.Random(21)
    rc = cc.randint(3, 7)
    xc = cc.uniform(0.25, 0.7) * PANEL_W
    op = [b for b in blocks if abs((b[1] + b[2]) / 2 - xc) < GRID_BLOCK_W * 1.4 and abs(b[0] - rc) <= 1]
    save_rgba(mas_b, _alpha_minus(op), "opening_a")

    # crumble: stepped diagonal taper. keep-height ramps from start-frac to end-frac across
    # the width; rows above the kept height are removed -> the wall steps DOWN toward +U.
    def crumble(start_frac: float, end_frac: float, rgb: Image.Image, name: str) -> None:
        removed = []
        for (r, x0, x1, y0, y1) in blocks:
            frac = max(0.0, min(1.0, ((x0 + x1) / 2) / PANEL_W))
            keep = round((start_frac + (end_frac - start_frac) * frac) * rows)
            if r < (rows - keep):
                removed.append((r, x0, x1, y0, y1))
        save_rgba(rgb, _alpha_minus(removed), name)

    crumble(1.0, 0.66, mas, "crumble_a")        # gentle: full -> 2/3
    crumble(0.66, 0.33, mas_b, "crumble_b")      # continues: 2/3 -> 1/3
    crumble(1.0, 0.33, mas, "crumble_steep")     # short arm: full -> 1/3 in one cell

    build_normal(mas)
    LOG.info("variants rebuilt (%d courses, %d blocks)", rows, len(blocks))
    return rows


def build_normal(masonry: Image.Image) -> None:
    """Bake a tangent-space normal map from the masonry luminance (no drawn lines)."""
    lum = np.asarray(masonry.convert("L"), np.float32) / 255.0
    height = np.asarray(
        Image.fromarray((lum * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(1.0)),
        np.float32,
    ) / 255.0
    gy, gx = np.gradient(height)
    strength = 3.5
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([(nx / norm) * 0.5 + 0.5, (ny / norm) * 0.5 + 0.5, (nz / norm) * 0.5 + 0.5], -1)
    _save(Image.fromarray((rgb * 255).astype("uint8"), "RGB"), "normal")


# ==============================================================================
# IO
# ==============================================================================

def _save(img: Image.Image, name: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{NAME_PREFIX}{name}.webp"
    if img.mode == "RGBA":
        # Lossless keeps the hard alpha edges the scissor threshold relies on.
        img.save(path, "WEBP", lossless=True, method=6)
    else:
        img.save(path, "WEBP", quality=92, method=6)
    LOG.info("wrote %s", path.relative_to(OUT_DIR.parent.parent.parent))


# --- Biome themes ---------------------------------------------------------------------------
# A theme renders the SAME panel set (same roles, same PIL damage pipeline) from a
# different masonry + window source, written under a name prefix ("desert_solid_a", ...)
# so the in-game RuinsLibrary can pick the set per table biome.

NAME_PREFIX: str = ""

DESERT_MASONRY_PROMPT: str = (
    "Seamless tileable front-on orthographic texture of an old sun-dried ADOBE mud-brick "
    "desert wall built of HORIZONTAL courses of small flat rectangular mud bricks in "
    "running bond: every brick lies FLAT and is clearly wider than tall, about 18 small "
    "bricks across the width and about 25 thin horizontal courses stacked vertically. "
    "Sandy tan and ochre clay bricks, patches of cracked earthen plaster, wind erosion, "
    "bleached by the sun, pale dust packed into the recessed joints. Natural recessed "
    "joints. Photorealistic, detailed, flat even lighting with no directional shadows, "
    "tiles seamlessly. No drawn lines, no grid overlay, no text, no border, no watermark."
)

## Desert damage grid matching the fine brickwork (~18 bricks across vs the castle's 6),
## so knock-outs and crumble steps still remove WHOLE bricks.
DESERT_GRID_ROW_H: float = PANEL_H / 33.0
DESERT_GRID_BLOCK_W: float = PANEL_W / 18.0

# Tundra: the approved castle masonry, snowed in. Same medium stone scale -> the
# default damage grid applies unchanged.
TUNDRA_MASONRY_PROMPT: str = (
    "Seamless tileable top-down orthographic texture of an old weathered castle wall of "
    "MEDIUM coursed grey stone blocks, roughly 6 stones across the width (medium size, not "
    "large, not tiny), IN DEEP WINTER: a layer of fresh snow caught on every ledge and "
    "horizontal mortar joint, frost and thin ice glaze on the stone faces, icicle traces, "
    "cold blue-grey tones. Natural deep recessed joints. Photorealistic, detailed, flat "
    "even lighting with no directional shadows, tiles seamlessly. No drawn lines, no grid "
    "overlay, no text, no border, no watermark."
)

TUNDRA_WINDOW_PROMPT: str = (
    "Front-on orthographic view of a two-light Gothic tracery window built of the SAME "
    "rough grey weathered castle stone as a medieval wall (grey limestone, NOT sandstone), "
    "IN DEEP WINTER: snow piled on the sill and every ledge, frost on the tracery, pointed "
    "equilateral outer arch, slender central mullion, two narrow pointed lancet lights, "
    "intersecting bar tracery at the head. The two glazed light openings are filled FLAT "
    "PURE MAGENTA (255,0,255). The entire area outside the window's outer stone frame is "
    "FLAT PURE GREEN (0,255,0). Only the snowy grey stone window is stone-coloured. Even "
    "flat lighting, no shadows, no background, no text, centered, fills the frame "
    "vertically."
)

DESERT_WINDOW_PROMPT: str = (
    "Front-on orthographic view of a two-light arched window in a thick sun-dried adobe "
    "desert wall of SMALL dense mud bricks (sandy tan clay, NOT grey stone): two narrow "
    "round-arched window lights side by side, divided by a sturdy mud-brick pillar, with a "
    "simple clay arch of small bricks above each light. The two window light openings are filled FLAT PURE MAGENTA "
    "(255,0,255). The entire area outside the window's outer clay frame is FLAT PURE GREEN "
    "(0,255,0). Only the tan adobe window surround is clay-coloured. Even flat lighting, no "
    "shadows, no background, no text, centered, fills the frame vertically."
)


def refresh_manifest_and_upload(do_upload: bool) -> int:
    """Merge the current prefix's 9 runtime panels into assets/ruins_manifest.json and
    optionally push them to R2 (terrain-source/ruins/), mirroring generate_trees.py."""
    import hashlib  # noqa: PLC0415
    import json  # noqa: PLC0415

    manifest_path = THIS_DIR.parent.parent / "assets" / "ruins_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    runtime = ["solid_a", "solid_b", "topdmg_a", "opening_a",
               "crumble_a", "crumble_b", "crumble_steep", "window", "normal"]
    paths: dict[str, Path] = {}
    for base in runtime:
        name = f"{NAME_PREFIX}{base}"
        path = OUT_DIR / f"{name}.webp"
        if not path.exists():
            LOG.error("missing panel %s", path)
            return 1
        data = path.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        manifest["panels"][name] = {
            # Version query busts the CDN edge cache when a named panel is re-published
            # (the edge may serve stale bytes for up to a day -> sha mismatch otherwise).
            "url": f"{name}.webp?v={sha[:8]}",
            "sha256": sha,
            "size": len(data),
        }
        paths[name] = path
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    LOG.info("manifest: +%d panels (%s)", len(paths), NAME_PREFIX or "default")
    if not do_upload:
        return 0

    sys.path.insert(0, str(THIS_DIR))
    from publish_manifest import _load_r2_config  # noqa: PLC0415

    cfg = _load_r2_config("", "")
    if any(not cfg[k] for k in ("access_key", "secret_key", "endpoint", "bucket")):
        LOG.error("missing R2 config")
        return 2
    import boto3  # noqa: PLC0415
    from botocore.config import Config  # noqa: PLC0415

    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    for name, path in sorted(paths.items()):
        s3.put_object(
            Bucket=cfg["bucket"], Key=f"terrain-source/ruins/{name}.webp",
            Body=path.read_bytes(), ContentType="image/webp",
            CacheControl="public, max-age=86400",
        )
        LOG.info("uploaded terrain-source/ruins/%s.webp", name)
    return 0


def main(argv: list[str] | None = None) -> int:
    global NAME_PREFIX, MASONRY_PROMPT, WINDOW_PROMPT

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", choices=["all", "masonry", "window", "variants"], default="all",
                    help="run a single stage (variants/window reuse the committed masonry)")
    ap.add_argument("--force", action="store_true",
                    help="re-render Gemini stages even if masonry_source.webp exists")
    ap.add_argument("--theme", choices=["castle", "desert", "tundra"], default="castle",
                    help="art theme: castle = the approved grey stone set, desert = adobe, "
                         "tundra = the castle stone snowed in")
    ap.add_argument("--upload-r2", action="store_true",
                    help="merge the theme's panels into ruins_manifest.json and push to R2")
    args = ap.parse_args(argv)

    if args.theme == "desert":
        global GRID_ROW_H, GRID_BLOCK_W
        NAME_PREFIX = "desert_"
        MASONRY_PROMPT = DESERT_MASONRY_PROMPT
        WINDOW_PROMPT = DESERT_WINDOW_PROMPT
        GRID_ROW_H = DESERT_GRID_ROW_H
        GRID_BLOCK_W = DESERT_GRID_BLOCK_W
    elif args.theme == "tundra":
        NAME_PREFIX = "tundra_"
        MASONRY_PROMPT = TUNDRA_MASONRY_PROMPT
        WINDOW_PROMPT = TUNDRA_WINDOW_PROMPT

    if args.upload_r2:
        return refresh_manifest_and_upload(True)

    masonry_path = OUT_DIR / f"{NAME_PREFIX}masonry_source.webp"
    need_gemini = args.only in ("all", "masonry", "window")
    client: genai.Client | None = None
    if need_gemini:
        key = _load_key()
        if not key:
            LOG.error("no Gemini key (.gemini_key or GEMINI_API_KEY); cannot run Gemini stages")
            return 2
        client = genai.Client(api_key=key)

    masonry: Image.Image | None = None
    if args.only in ("all", "masonry"):
        if masonry_path.exists() and not args.force and args.only == "all":
            LOG.info("%smasonry_source.webp exists; reusing (use --force to re-render)", NAME_PREFIX)
            masonry = Image.open(masonry_path).convert("RGB")
        else:
            masonry = generate_masonry(client)

    if masonry is None:
        if not masonry_path.exists():
            LOG.error("masonry_source.webp missing; run with --only masonry first")
            return 2
        masonry = Image.open(masonry_path).convert("RGB")

    if args.only in ("all", "variants"):
        build_variants(masonry)
    if args.only in ("all", "window"):
        generate_window(client, masonry)

    LOG.info("done -> %s", OUT_DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
