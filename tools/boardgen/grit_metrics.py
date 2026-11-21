#!/usr/bin/env python3
"""grit_metrics.py STILLS [MASKS] [--out FILE]: the ground instrument of the ruin town (plan PLAN_RUINTOWN_GRIT, G0).

STILLS is a capture folder of tools/boardgen/bg_capture_town.gd (manifest.json + <still>.jpg). MASKS (default STILLS) holds the debug stills <still>_grit.png of a
`grit_debug=1` capture of the SAME cameras: the board shader paints every street pixel in the flat colour of its grit class (emission only, linear tonemap, every light off), so
the class of a pixel is read exactly, not guessed. Masks are geometry only: a look still of one build may be measured with the masks of another build of the same board.

One row per still that has a mask, written to FILE (default STILLS/grit_metrics.txt):
  pristine / missing / sunken / cracked / repair / mud / wet / puddle   share of the street pixels (debug still)
  sat, hue_sd    mean HSV saturation and circular std of hue (degrees) of the LIT street pixels of the look still (luminance > 0.06)
  luma           their mean luminance (Rec. 709 of the sRGB values)
  midvar         std / mean of the luminance means of 1 in blocks (blocks at least half street; px per inch from the manifest's still_info)
  accent         share of all lit pixels of the look still with saturation > 0.6
Targets (style bible) are checked where they apply and marked PASS / FAIL; `--self-test` proves on planted images that every check can fail.
"""
import json, math, os, sys

import numpy as np
from PIL import Image

# Class colours of the shader's grit_debug (ruintown_grit.gdshaderinc): channel levels 0 / mid / full -> 0 / 1 / 2
CLASSES = {(2, 2, 2): "pristine", (1, 1, 1): "worn", (1, 1, 0): "mud", (0, 0, 2): "wet", (0, 1, 2): "puddle", (1, 0, 1): "soot", (0, 2, 0): "moss",
           (2, 0, 0): "missing", (0, 2, 2): "sunken", (2, 0, 2): "cracked", (2, 2, 0): "repair"}
TARGETS = {"pristine": (0.15, 0.35), "missing": (0.04, 0.08), "sunken": (0.10, 0.15), "sat": (0.20, 0.30), "hue_sd": (18.0, 360.0), "accent": (0.0, 0.03)}


def levels(png):
    a = np.asarray(Image.open(png).convert("RGB"), dtype=np.float32) / 255.0
    return np.where(a < 0.25, 0, np.where(a > 0.75, 2, 1)).astype(np.int8)


def classify(lv):
    """{class name: bool mask}; `street` = every pixel of a known class except black; `other` = an unknown colour (a lantern glow, a bloom edge)."""
    out, known = {}, np.zeros(lv.shape[:2], bool)
    for key, name in CLASSES.items():
        m = np.all(lv == np.array(key, np.int8), axis=2)
        out[name] = m
        known |= m
    out["street"] = known
    out["other"] = ~known & np.any(lv > 0, axis=2)
    return out


def hsv(rgb):
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6.0, np.where(mx == g, (b - r) / d + 2.0, (r - g) / d + 4.0)) * 60.0
    return h, sat


def measure(look, cls, px_per_in):
    row = {}
    street = cls["street"]
    n = max(int(street.sum()), 1)
    for name in ["pristine", "worn", "mud", "wet", "puddle", "soot", "moss", "missing", "sunken", "cracked", "repair"]:
        row[name] = float(cls[name].sum()) / n
    row["street_px"] = int(street.sum())
    if look is None:
        return row
    rgb = np.asarray(Image.open(look).convert("RGB"), dtype=np.float32) / 255.0
    if rgb.shape[:2] != street.shape:
        rgb = np.asarray(Image.open(look).convert("RGB").resize((street.shape[1], street.shape[0])), dtype=np.float32) / 255.0
    luma = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    lit = luma > 0.06
    sel = street & lit
    h, s = hsv(rgb)
    if sel.sum() > 0:
        row["sat"] = float(s[sel].mean())
        ang = np.deg2rad(h[sel])
        rlen = math.hypot(float(np.cos(ang).mean()), float(np.sin(ang).mean()))
        row["hue_sd"] = math.degrees(math.sqrt(max(-2.0 * math.log(max(rlen, 1e-9)), 0.0)))
        row["luma"] = float(luma[sel].mean())
    row["accent"] = float((s[lit] > 0.6).mean()) if lit.sum() > 0 else 0.0
    b = max(int(round(px_per_in)), 2)
    means = []
    for y in range(0, street.shape[0] - b + 1, b):
        for x in range(0, street.shape[1] - b + 1, b):
            m = street[y:y + b, x:x + b]
            if m.mean() >= 0.5:
                means.append(float(luma[y:y + b, x:x + b][m].mean()))
    if len(means) >= 4:
        row["midvar"] = float(np.std(means) / max(np.mean(means), 1e-6))
        row["dark"] = float(np.mean(np.array(means) < 18.0 / 255.0))   # lead rule 21.11.: no walkable street region under ~18 / 255 mean (share of 1 in blocks below it)
        row["p10_255"] = float(np.percentile(means, 10) * 255.0)
    return row


def repetition(look, px_per_in, period_in, frac=(0.2, 0.8, 0.3, 0.7)):
    """How strongly a still repeats at the texture's period (plan W0): the horizontal autocorrelation of the luminance of the central crop (x 20-80 %, y 30-70 %), every row high-passed (minus its moving mean over one period), at the lag of one period (the best lag within +-12 % of it), normalised by the lag-0 value. ~1 = a wallpaper, ~0 = no repeat at that period."""
    rgb = np.asarray(Image.open(look).convert("L"), dtype=np.float32) / 255.0
    h, w = rgb.shape
    c = rgb[int(h * frac[2]):int(h * frac[3]), int(w * frac[0]):int(w * frac[1])]
    p = period_in * px_per_in
    k = max(int(round(p)), 1)   # high-pass: minus the moving mean over one period (keeps the periodic part, drops the slow drift of light and tone)
    ker = np.ones(k, np.float32) / k
    c = c - np.apply_along_axis(lambda r: np.convolve(r, ker, mode="same"), 1, c)
    c = c[:, k:-k] if c.shape[1] > 3 * k else c
    best = -1.0
    var = float((c * c).mean())
    for lag in range(max(int(p * 0.88), 1), min(int(p * 1.12) + 1, c.shape[1] - 8)):
        best = max(best, float((c[:, :-lag] * c[:, lag:]).mean()) / max(var, 1e-9))
    return best


def verdicts(row):
    out = []
    for key, (lo, hi) in TARGETS.items():
        if key in row:
            out.append("%s %s" % (key, "PASS" if lo <= row[key] <= hi else "FAIL"))
    return out


def fmt(name, row):
    keys = ["pristine", "worn", "missing", "sunken", "cracked", "repair", "mud", "wet", "puddle", "sat", "hue_sd", "luma", "midvar", "dark", "p10_255", "accent"]
    vals = " ".join("%s %s" % (k, ("%.1f" % row[k]) if k in ("hue_sd", "p10_255") else ("%.3f" % row[k])) for k in keys if k in row)
    return "%-28s street_px %7d | %s | %s" % (name, row.get("street_px", 0), vals, " ".join(verdicts(row)))


def run(stills, masks, out):
    man = json.load(open(os.path.join(stills, "manifest.json")))
    info = man.get("still_info", {})
    mman = os.path.join(masks, "manifest.json")
    if os.path.exists(mman):
        info = json.load(open(mman)).get("still_info", info)   # the masks' capture knows the camera (same cameras, maybe a newer capture)
    lines = []
    for still in man["stills"]:
        if "_macro_wall" in still:   # plan W0: the wall's repetition at the coursed-stone set's period (manifest tile_in 1.3 in)
            ppi = float(info.get(still, {}).get("px_per_in", 8.0))
            lines.append("%-28s repeat@1.3in %.3f  (px per in %.1f)" % (still, repetition(os.path.join(stills, still), ppi, 1.3, (0.15, 0.85, 0.25, 0.58)), ppi))
            continue
        png = os.path.join(masks, os.path.splitext(still)[0] + "_grit.png")
        if not os.path.exists(png):
            continue
        cls = classify(levels(png))
        row = measure(os.path.join(stills, still), cls, float(info.get(still, {}).get("px_per_in", 8.0)))
        lines.append(fmt(still, row))
    if not lines:
        lines.append("no still of %s has a debug still in %s" % (stills, masks))
    open(out, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if lines and not lines[0].startswith("no still") else 1


def self_test():
    """Planted images: a street that is all pristine and orange must FAIL pristine / sat / hue; a mixed, cold one must PASS them."""
    import tempfile
    d = tempfile.mkdtemp()
    H = W = 200
    mask = np.zeros((H, W, 3), np.uint8)
    mask[50:150, :] = 255   # street band, all pristine
    look = np.zeros((H, W, 3), np.uint8)
    look[50:150, :] = (150, 100, 50)   # orange
    Image.fromarray(mask).save(os.path.join(d, "a_grit.png"))
    Image.fromarray(look).save(os.path.join(d, "a.png"))
    bad = measure(os.path.join(d, "a.png"), classify(levels(os.path.join(d, "a_grit.png"))), 10)
    mask2 = mask.copy()
    mask2[50:100, :] = (255, 0, 0)   # 5 / 100 rows missing would be 5 %: paint 6 rows red, 12 rows cyan, 52 rows mud, keep 30 white
    mask2[50:150, :] = (122, 122, 0)
    mask2[50:56, :] = (255, 0, 0)
    mask2[56:68, :] = (0, 255, 255)
    mask2[68:93, :] = (255, 255, 255)
    rng = np.random.default_rng(1)
    look2 = np.zeros((H, W, 3), np.uint8)
    for y in range(50, 150):
        base = rng.choice([(110, 112, 118), (120, 112, 100), (130, 105, 80), (95, 105, 120)])
        look2[y, :] = base
    Image.fromarray(mask2).save(os.path.join(d, "b_grit.png"))
    Image.fromarray(look2).save(os.path.join(d, "b.png"))
    good = measure(os.path.join(d, "b.png"), classify(levels(os.path.join(d, "b_grit.png"))), 10)
    print("planted brand-new:", fmt("a", bad))
    print("planted gritty:   ", fmt("b", good))
    vb, vg = " ".join(verdicts(bad)), " ".join(verdicts(good))
    ok = all(("%s FAIL" % k) in vb for k in ["pristine", "sat", "hue_sd", "missing", "sunken"]) and all(("%s PASS" % k) in vg for k in ["pristine", "sat", "hue_sd", "missing", "sunken"])
    rng = np.random.default_rng(7)   # the repetition: a tiled wallpaper must read high, the same tile under a random per-band offset low
    tile = (rng.random((40, 40)) * 255).astype(np.uint8)
    wall = np.tile(tile, (6, 12))
    Image.fromarray(wall).save(os.path.join(d, "wall.png"))
    broken = wall.copy()
    for y in range(0, broken.shape[0], 40):
        for x0 in range(0, broken.shape[1], 40):
            broken[y:y + 40, x0:x0 + 40] = np.roll(np.roll(tile, rng.integers(5, 35), axis=1), rng.integers(5, 35), axis=0)
    Image.fromarray(broken).save(os.path.join(d, "broken.png"))
    r_tiled = repetition(os.path.join(d, "wall.png"), 40 / 1.3, 1.3, (0.0, 1.0, 0.0, 1.0))
    r_broken = repetition(os.path.join(d, "broken.png"), 40 / 1.3, 1.3, (0.0, 1.0, 0.0, 1.0))
    print("planted repetition: tiled %.3f, phase per tile %.3f" % (r_tiled, r_broken))
    ok = ok and r_tiled > 0.9 and r_broken < 0.5
    print("SELF_TEST", "OK" if ok else "BROKEN")
    return 0 if ok else 1


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--self-test":
        sys.exit(self_test())
    out = None
    if "--out" in a:
        i = a.index("--out")
        out = a[i + 1]
        a = a[:i] + a[i + 2:]
    stills = a[0]
    masks = a[1] if len(a) > 1 else stills
    sys.exit(run(stills, masks, out or os.path.join(stills, "grit_metrics.txt")))
