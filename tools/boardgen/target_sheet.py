#!/usr/bin/env python3
"""target_sheet.py OUT TARGETS [--also LABEL=DIR ...]: the acceptance sheets of the ruin town (plan PLAN_RUINTOWN_TARGET_C, T2).

OUT holds the stills of tools/boardgen/target_run.sh (any sub-folder, e.g. OUT/cap_s41/s41_street.jpg) and OUT/sha.txt. TARGETS is the folder of the target images (outside the
repo). For each of the six acceptance cameras it writes OUT/sheet_<camera>.jpg: the town under test on the left, the target on the right, same height, a caption bar with the
camera, the seed and the commit; then OUT/sheet_all.jpg (all six stacked, written LAST = the result artefact). `--also LABEL=DIR` puts the same camera of another capture folder
(e.g. CURRENT=<main's OUT>) in front, so a sheet reads CURRENT | THIS | TARGET. A missing still or target: exit 1 with its name.
NUMBERS (T3): the style spec of the plan - boxes (fractions of the frame), pixel classes and bands - one row per number with every column, C and PASS / FAIL of THIS, written to
OUT/target_numbers.txt and drawn as a footer under each sheet. Classes per pixel (800 x 450, sRGB, HSV, luma = Rec. 709, lit = luma > 0.06): rust = hue < 25 or > 340, sat > 0.45,
luma < 0.6; warm = hue 25-55, sat > 0.35; cool = hue 185-260, sat > 0.12; green = hue 70-170, sat > 0.18. sky_blue = blue minus red of the box's mean sRGB (0-255).
`--self-test`: planted images prove that every band can FAIL and that the classes count what they claim.
"""
import glob, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# camera: (still of the town, seed, target image)
PAIRS = [("street", "s41_street", "street_C1"), ("fountain_eye", "s41_fountain_eye", "fountain_C1"), ("overview45", "s41_overview45", "overview45_C2"),
         ("play", "s41_play", "play_C1"), ("wall", "s25_wall", "wall_C2"), ("top", "s41_top", "top_C2")]
W, H, BAR = 960, 540, 44
EARTH = [("rust", None, 5), ("sat", None, 0.42), ("lum_p50", 0.11, 0.16), ("green", 18, 32)]
# camera: [(box name, box, [(number, low, high)])]   (None = no bound on that side)
SPEC = {"play": [("earth_l", (0.10, 0.80, 0.28, 0.98), EARTH), ("earth_r", (0.78, 0.80, 0.92, 0.98), EARTH),
                 ("board", (0.08, 0.14, 0.95, 1.0), [("rust", None, 3), ("warm", None, 8), ("green", 8, 15), ("lum_p50", 0.165, None), ("lum_p90", None, 0.58)]),
                 ("square", (0.44, 0.33, 0.56, 0.62), [("warm", None, 20), ("cool", 25, None)])],
        "street": [("sky", (0.05, 0.02, 0.58, 0.22), [("sky_blue", 25, None)]), ("upper", (0, 0, 1, 0.5), [("lum_p50", 0.28, None)]),
                   ("ground", (0, 0.75, 0.6, 1), [("warm", None, 10), ("cool", 50, None), ("lum_p50", 0.25, 0.30), ("sat", None, 0.30)]),
                   ("pool", (0.7, 0.7, 1, 0.95), [("warm", 40, 60), ("lum_p50", 0.40, 0.50)])],
        "fountain_eye": [("sky", (0.25, 0.02, 0.75, 0.2), [("sky_blue", 25, None)]),
                         ("ground", (0, 0.75, 0.7, 1), [("warm", None, 15), ("lum_p50", 0.22, 0.28), ("sat", None, 0.28)])],
        "overview45": [],   # the C image is zoomed against its input: no band
        "wall": [("whole", (0, 0, 1, 1), [("green", 3, 5), ("warm", None, 17), ("lum_p90", None, 0.50)])],
        "top": [("board", (0.14, 0.06, 0.87, 0.96), [("rust", None, 4), ("green", 3, 6), ("lum_p90", None, 0.52)])]}


def numbers(img, box):
    """The style-spec numbers of one box of an image (PIL RGB): shares in percent, luma / saturation 0..1, sky_blue 0..255."""
    a = np.asarray(img.convert("RGB").resize((800, 450)), dtype=float) / 255.0
    x0, y0, x1, y1 = box
    a = a[int(y0 * 450):int(y1 * 450), int(x0 * 800):int(x1 * 800)]
    luma = a @ np.array([0.2126, 0.7152, 0.0722])
    mx, mn = a.max(-1), a.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    hue = np.asarray(Image.fromarray((a * 255).astype("uint8")).convert("HSV"), dtype=float)[..., 0] * 360.0 / 255.0
    lit = luma > 0.06
    share = lambda m: 100.0 * float((m & lit).mean())
    mean = a.reshape(-1, 3).mean(0) * 255.0
    return {"rust": share(((hue < 25) | (hue > 340)) & (sat > 0.45) & (luma < 0.6)), "warm": share((hue >= 25) & (hue < 55) & (sat > 0.35)),
            "cool": share((hue > 185) & (hue < 260) & (sat > 0.12)), "green": share((hue > 70) & (hue < 170) & (sat > 0.18)), "sat": float(sat.mean()),
            "lum_p50": float(np.percentile(luma, 50)), "lum_p90": float(np.percentile(luma, 90)), "sky_blue": float(mean[2] - mean[0])}


def passes(v, lo, hi):
    return (lo is None or v >= lo) and (hi is None or v <= hi)


def band(lo, hi):
    return ">= %g" % lo if hi is None else "<= %g" % hi if lo is None else "%g-%g" % (lo, hi)


def rows(cam, imgs, target):
    """[(text, passed, footer text)] per spec number: every column's value (imgs = [(label, PIL image)], THIS last), C, band, PASS / FAIL of THIS."""
    out = []
    for name, box, checks in SPEC[cam]:
        vals = [(label, numbers(im, box)) for label, im in imgs] + [("C", numbers(target, box))]
        for key, lo, hi in checks:
            ok = passes(vals[-2][1][key], lo, hi)
            fmt = "%.1f" if key in ("rust", "warm", "cool", "green", "sky_blue") else "%.3f"
            cols = " ".join("%s %s" % (label, fmt % v[key]) for label, v in vals)
            short = "%s %s %s (C %s) %s %s" % (name, key, fmt % vals[-2][1][key], fmt % vals[-1][1][key], band(lo, hi), "PASS" if ok else "FAIL")
            out.append(("%s %s: %s [%s] %s" % (name, key, cols, band(lo, hi), "PASS" if ok else "FAIL"), ok, short))
    return out


def self_test():
    """Planted frames: a rust-filled, a flat grey, a green, a blue, an amber, a white and a black frame. Every band of SPEC must FAIL on at least one of them."""
    planted = {c: Image.new("RGB", (800, 450), c) for c in [(150, 40, 20), (90, 90, 90), (40, 140, 40), (40, 60, 160), (200, 150, 40), (255, 255, 255), (0, 0, 0)]}
    assert numbers(planted[(150, 40, 20)], (0, 0, 1, 1))["rust"] > 99.0, "a rust-filled box is not rust"
    assert abs(numbers(planted[(90, 90, 90)], (0, 0, 1, 1))["sky_blue"]) < 0.5, "a flat grey sky has a blue cast"
    assert numbers(planted[(90, 90, 90)], (0, 0, 1, 1))["green"] == 0.0, "a green-free board has green"
    assert numbers(planted[(40, 140, 40)], (0, 0, 1, 1))["green"] > 99.0, "a green board is not green"
    n = 0
    for cam, spec in SPEC.items():
        for name, box, checks in spec:
            for key, lo, hi in checks:
                assert any(not passes(numbers(im, box)[key], lo, hi) for im in planted.values()), "%s %s %s can never FAIL" % (cam, name, key)
                n += 1
    print("SELF_TEST PASS: %d bands can fail, the classes count planted colours" % n)
    return 0


def font(size):
    for path in ["/usr/share/fonts/google-noto/NotoSans-Bold.ttf", "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf"]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def find_still(folder, stem):
    hits = sorted(glob.glob(os.path.join(folder, "**", stem + ".jpg"), recursive=True))
    return hits[0] if hits else None


def sha_of(folder):
    p = os.path.join(folder, "sha.txt")
    return open(p).read().strip() if os.path.exists(p) else "?"


def tile(path, caption, fnt):
    im = Image.open(path).convert("RGB").resize((W, H), Image.LANCZOS)
    out = Image.new("RGB", (W, H + BAR), (0, 0, 0))
    out.paste(im, (0, BAR))
    ImageDraw.Draw(out).text((10, 6), caption, fill=(255, 220, 120), font=fnt)
    return out


def main(argv):
    if argv[:1] == ["--self-test"]:
        return self_test()
    if len(argv) < 2:
        print(__doc__)
        return 2
    out, targets = argv[0], argv[1]
    columns = [tuple(a.split("=", 1)) for a in argv[2:] if "=" in a] + [("THIS", out)]
    fnt = font(26)
    missing, sheets, report = [], [], []
    for cam, stem, target in PAIRS:
        paths = [(label, folder, find_still(folder, stem)) for label, folder in columns]
        tpath = os.path.join(targets, target + ".jpg")
        missing += ["%s still %s in %s" % (label, stem, folder) for label, folder, p in paths if p is None]
        if not os.path.exists(tpath):
            missing.append("target " + tpath)
        if missing:
            continue
        tiles = [tile(p, "%s  %s  seed %s  @ %s" % (label, cam, stem.split("_")[0][1:], sha_of(folder)), fnt) for label, folder, p in paths]
        tiles.append(tile(tpath, "TARGET C  %s  [%s]" % (cam, target), fnt))
        found = rows(cam, [(label, Image.open(p)) for label, folder, p in paths], Image.open(tpath))
        report += ["%s %s" % (cam, r) for r, ok, short in found]
        per = max(1, W * len(tiles) // 470)   # footer: the THIS value, C and the band of every number, as many per line as fit
        lines = [" | ".join(f[2] for f in found[i:i + per]) for i in range(0, len(found), per)] or ["(no bands for this camera)"]
        sheet = Image.new("RGB", (W * len(tiles), H + BAR + 30 * len(lines) + 10), (20, 20, 20))
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * W, 0))
        for i, line in enumerate(lines):
            ImageDraw.Draw(sheet).text((10, H + BAR + 6 + 30 * i), line, fill=(230, 230, 230), font=font(18))
        sheet.save(os.path.join(out, "sheet_%s.jpg" % cam), quality=90)
        sheets.append(sheet)
    if missing:
        print("MISSING: " + "; ".join(missing), file=sys.stderr)
        return 1
    open(os.path.join(out, "target_numbers.txt"), "w").write("\n".join(report) + "\nPASS %d / %d\n" % (sum("PASS" in r[-4:] for r in report), len(report)))
    allsheet = Image.new("RGB", (sheets[0].width, sum(s.height for s in sheets)), (20, 20, 20))
    y = 0
    for s in sheets:
        allsheet.paste(s, (0, y))
        y += s.height
    allsheet.resize((allsheet.width // 2, allsheet.height // 2), Image.LANCZOS).save(os.path.join(out, "sheet_all.jpg"), quality=88)
    print("SHEETS %d -> %s" % (len(sheets), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
