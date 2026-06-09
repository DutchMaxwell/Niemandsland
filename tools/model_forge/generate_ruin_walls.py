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
    path = OUT_DIR / f"{name}.webp"
    if img.mode == "RGBA":
        # Lossless keeps the hard alpha edges the scissor threshold relies on.
        img.save(path, "WEBP", lossless=True, method=6)
    else:
        img.save(path, "WEBP", quality=92, method=6)
    LOG.info("wrote %s", path.relative_to(OUT_DIR.parent.parent.parent))


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", choices=["all", "masonry", "window", "variants"], default="all",
                    help="run a single stage (variants/window reuse the committed masonry)")
    ap.add_argument("--force", action="store_true",
                    help="re-render Gemini stages even if masonry_source.webp exists")
    args = ap.parse_args(argv)

    masonry_path = OUT_DIR / "masonry_source.webp"
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
            LOG.info("masonry_source.webp exists; reusing (use --force to re-render)")
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
