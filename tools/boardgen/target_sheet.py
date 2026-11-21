#!/usr/bin/env python3
"""target_sheet.py OUT TARGETS [--also LABEL=DIR ...]: the acceptance sheets of the ruin town (plan PLAN_RUINTOWN_TARGET_C, T2).

OUT holds the stills of tools/boardgen/target_run.sh (any sub-folder, e.g. OUT/cap_s41/s41_street.jpg) and OUT/sha.txt. TARGETS is the folder of the target images (outside the
repo). For each of the six acceptance cameras it writes OUT/sheet_<camera>.jpg: the town under test on the left, the target on the right, same height, a caption bar with the
camera, the seed and the commit; then OUT/sheet_all.jpg (all six stacked, written LAST = the result artefact). `--also LABEL=DIR` puts the same camera of another capture folder
(e.g. CURRENT=<main's OUT>) in front, so a sheet reads CURRENT | THIS | TARGET. A missing still or target: exit 1 with its name.
"""
import glob, os, sys

from PIL import Image, ImageDraw, ImageFont

# camera: (still of the town, seed, target image)
PAIRS = [("street", "s41_street", "street_C1"), ("fountain_eye", "s41_fountain_eye", "fountain_C1"), ("overview45", "s41_overview45", "overview45_C2"),
         ("play", "s41_play", "play_C1"), ("wall", "s25_wall", "wall_C2"), ("top", "s41_top", "top_C2")]
W, H, BAR = 960, 540, 44


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
    if len(argv) < 2:
        print(__doc__)
        return 2
    out, targets = argv[0], argv[1]
    columns = [tuple(a.split("=", 1)) for a in argv[2:] if "=" in a] + [("THIS", out)]
    fnt = font(26)
    missing, sheets = [], []
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
        sheet = Image.new("RGB", (W * len(tiles), H + BAR), (20, 20, 20))
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * W, 0))
        sheet.save(os.path.join(out, "sheet_%s.jpg" % cam), quality=90)
        sheets.append(sheet)
    if missing:
        print("MISSING: " + "; ".join(missing), file=sys.stderr)
        return 1
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
