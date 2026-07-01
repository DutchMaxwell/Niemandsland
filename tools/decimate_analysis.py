#!/usr/bin/env python3
"""Per-base-size decimation-threshold analysis.

Reads the renders produced by scenes/ctex_decimate_basesize.tscn
(user://decimate_basesize/base_<mm>/tris_<NNNNNN>.png), and for each base tier
SSIM-diffs every decimation step against the highest-triangle reference in that
tier. Prints a per-base table and the decimation FLOOR — the lowest triangle
count still indistinguishable from full (the point at which we must NOT decimate
further) — at two just-noticeable-difference thresholds. Also writes a per-base
diff montage (full | step | 8x abs-diff) for eyeball confirmation.

Metric: SSIM (structural similarity) over the foreground crop + mean abs diff
over foreground pixels. Numpy-only (skimage not required).

Usage:
    python3 tools/decimate_analysis.py [RENDER_DIR]
Default RENDER_DIR: the flatpak Niemandsland user:// decimate_basesize dir.
"""
from __future__ import annotations

import os
import re
import sys

import numpy as np
from PIL import Image

DEFAULT_DIR = os.path.expanduser(
    "~/.var/app/org.godotengine.Godot/data/godot/app_userdata/"
    "Niemandsland/decimate_basesize"
)
# SSIM thresholds EYE-CALIBRATED on this model/material/lighting (2026-07-01, via the 1x compare
# strips): "invisible" = no perceptible difference at the closest realistic zoom; "floor" = onset of
# visible faceting — do NOT decimate below it. These absolute SSIM values are anchored to this test
# (assault brothers, .ctex material); re-anchor via the montage if the sculpt/material changes.
SSIM_INVISIBLE = 0.74
SSIM_FLOOR = 0.62
BOX = 7           # SSIM window (odd)
BG_TOL = 8        # luminance delta from the corner colour that counts as foreground


def load_luma(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("L"), dtype=np.float64)


def load_rgb(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)


def foreground_mask(img: np.ndarray) -> np.ndarray:
    bg = img[0, 0]
    return np.abs(img - bg) > BG_TOL


def crop_bbox(mask: np.ndarray, pad: int = 8) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    if ys.size == 0:
        return 0, mask.shape[0], 0, mask.shape[1]
    y0 = max(0, ys.min() - pad)
    y1 = min(mask.shape[0], ys.max() + pad + 1)
    x0 = max(0, xs.min() - pad)
    x1 = min(mask.shape[1], xs.max() + pad + 1)
    return y0, y1, x0, x1


def box_blur(a: np.ndarray, k: int) -> np.ndarray:
    """Separable running-mean blur, edge-padded (numpy-only)."""
    r = k // 2
    pad = np.pad(a, ((r, r), (r, r)), mode="edge")
    cs = np.cumsum(np.cumsum(pad, axis=0), axis=1)
    cs = np.pad(cs, ((1, 0), (1, 0)), mode="constant")
    h, w = a.shape
    ys = np.arange(h) + k
    xs = np.arange(w) + k
    y0 = np.arange(h)
    x0 = np.arange(w)
    total = (cs[np.ix_(ys, xs)] - cs[np.ix_(y0, xs)]
             - cs[np.ix_(ys, x0)] + cs[np.ix_(y0, x0)])
    return total / (k * k)


def ssim_map(a: np.ndarray, b: np.ndarray, k: int = BOX) -> np.ndarray:
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    mu_a = box_blur(a, k)
    mu_b = box_blur(b, k)
    mu_a2, mu_b2, mu_ab = mu_a * mu_a, mu_b * mu_b, mu_a * mu_b
    va = box_blur(a * a, k) - mu_a2
    vb = box_blur(b * b, k) - mu_b2
    vab = box_blur(a * b, k) - mu_ab
    return (((2 * mu_ab + c1) * (2 * vab + c2))
            / ((mu_a2 + mu_b2 + c1) * (va + vb + c2)))


def analyse_base(base_dir: str) -> list[dict]:
    files = sorted(
        f for f in os.listdir(base_dir)
        if re.fullmatch(r"tris_\d+\.png", f)
    )
    if not files:
        return []
    tiers = sorted(
        ((int(re.search(r"\d+", f).group()), os.path.join(base_dir, f))
         for f in files),
        reverse=True,   # high tris first = reference
    )
    ref_tris, ref_path = tiers[0]
    ref = load_luma(ref_path)
    mask = foreground_mask(ref)
    y0, y1, x0, x1 = crop_bbox(mask)
    ref_c = ref[y0:y1, x0:x1]
    fg_c = mask[y0:y1, x0:x1]

    rows: list[dict] = []
    for tris, path in tiers:
        img = load_luma(path)[y0:y1, x0:x1]
        smap = ssim_map(ref_c, img)
        ssim = float(smap[fg_c].mean()) if fg_c.any() else float(smap.mean())
        mad = float(np.abs(ref_c - img)[fg_c].mean()) if fg_c.any() else 0.0
        rows.append({"tris": tris, "ssim": ssim, "mad": mad,
                     "path": path, "is_ref": tris == ref_tris})
    return rows


def find_floor(rows: list[dict], threshold: float) -> int | None:
    """Lowest-tris step still >= threshold, scanning high→low, stopping at the
    first drop below it (the floor sits just above the first visible break)."""
    floor = None
    for r in rows:
        if r["ssim"] >= threshold:
            floor = r["tris"]
        else:
            break
    return floor


def montage(base_dir: str, rows: list[dict], out_path: str) -> None:
    ref_path = next(r["path"] for r in rows if r["is_ref"])
    ref = load_rgb(ref_path)
    mask = foreground_mask(np.asarray(Image.open(ref_path).convert("L"),
                                      dtype=np.float64))
    y0, y1, x0, x1 = crop_bbox(mask)
    ref_c = ref[y0:y1, x0:x1]
    h, w = ref_c.shape[:2]
    strips = []
    for r in sorted(rows, key=lambda x: x["tris"]):
        img = load_rgb(r["path"])[y0:y1, x0:x1]
        diff = np.clip(np.abs(ref_c - img) * 8.0, 0, 255)
        strip = np.concatenate([ref_c, img, diff], axis=1).astype(np.uint8)
        strips.append((r, strip))
    if not strips:
        return
    gap = 6
    total_h = len(strips) * h + gap * (len(strips) - 1)
    canvas = np.zeros((total_h, w * 3, 3), dtype=np.uint8)
    y = 0
    for _r, strip in strips:
        canvas[y:y + h] = strip
        y += h + gap
    Image.fromarray(canvas).save(out_path)


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    if not os.path.isdir(root):
        print(f"render dir not found: {root}\n"
              f"Run scenes/ctex_decimate_basesize.tscn (F6) first.")
        return 1
    bases = sorted(
        (int(re.search(r"\d+", d).group()), os.path.join(root, d))
        for d in os.listdir(root)
        if re.fullmatch(r"base_\d+", d)
    )
    if not bases:
        print(f"no base_<mm> subdirs in {root}")
        return 1

    print(f"# Decimation threshold per base size\nsource: {root}\n")
    summary = []
    for base_mm, base_dir in bases:
        rows = analyse_base(base_dir)
        if not rows:
            print(f"## {base_mm} mm — no renders\n")
            continue
        ref_tris = next(r["tris"] for r in rows if r["is_ref"])
        print(f"## {base_mm} mm  (ref = {ref_tris:,} tris)")
        print(f"{'tris':>10} {'SSIM':>8} {'MAD':>7}")
        for r in rows:
            tag = "  <- full" if r["is_ref"] else ""
            print(f"{r['tris']:>10,} {r['ssim']:>8.4f} {r['mad']:>7.3f}{tag}")
        strict = find_floor(rows, SSIM_INVISIBLE)
        loose = find_floor(rows, SSIM_FLOOR)
        summary.append((base_mm, strict, loose, ref_tris))
        print(f"invisible SSIM>={SSIM_INVISIBLE}: "
              f"{strict:,} tris" if strict else
              f"invisible SSIM>={SSIM_INVISIBLE}: none (even top step differs)")
        print(f"HARD floor SSIM>={SSIM_FLOOR}: "
              f"{loose:,} tris" if loose else
              f"HARD floor SSIM>={SSIM_FLOOR}: none")
        out = os.path.join(root, f"montage_base_{base_mm}.png")
        montage(base_dir, rows, out)
        print(f"montage: {out}\n")

    if summary:
        print("## Summary — safe target (invisible) | HARD floor (do NOT go below)")
        print(f"{'base':>6} {'strict':>12} {'loose':>12}")
        for base_mm, strict, loose, _ref in summary:
            s = f"{strict:,}" if strict else "keep full"
            lo = f"{loose:,}" if loose else "keep full"
            print(f"{base_mm:>4} mm {s:>12} {lo:>12}")
        print("\nRead as: a smaller base tolerates more decimation (fewer "
              "on-table pixels); the floor is the point at which reduction "
              "starts to show against the original.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
