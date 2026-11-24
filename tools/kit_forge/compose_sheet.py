# compose_sheet.py <rows dir> <out.jpg>: stacks the Blender row renders (rows.json) into one labelled review sheet.
import json, os, sys
from PIL import Image, ImageDraw, ImageFont
R, O = sys.argv[1], sys.argv[2]
meta = json.load(open(os.path.join(R, "rows.json")))
try:
    FB = ImageFont.truetype("/usr/share/fonts/google-noto/NotoSans-Bold.ttf", 30)
    FS = ImageFont.truetype("/usr/share/fonts/google-noto/NotoSans-Regular.ttf", 21)
except OSError:
    FB = FS = ImageFont.load_default()
ims = [Image.open(m["png"]).convert("RGB") for m in meta]
W = max(i.width for i in ims)
H = sum(i.height + 50 for i in ims) + 70
sheet = Image.new("RGB", (W, H), (18, 18, 20))
d = ImageDraw.Draw(sheet)
d.text((20, 15), (sys.argv[3] if len(sys.argv) > 3 else "ruintown dressing kit") + " - preview shading (not the game shader), 25 mm base disc beside every module", font=FB, fill=(235, 235, 235))
y = 70
for m, im in zip(meta, ims):
    d.text((20, y + 8), m["title"], font=FB, fill=(220, 200, 150))
    y += 50
    sheet.paste(im, (0, y))
    for t, x, ly in m["labels"]:
        for k, line in enumerate(t.split("\n")):
            w = d.textlength(line, font=FS)
            d.text((x - w / 2, y + ly + k * 24), line, font=FS, fill=(255, 255, 255) if k == 0 else (190, 190, 190),
                   stroke_width=2, stroke_fill=(0, 0, 0))
    y += im.height
sheet.save(O, quality=88)
print("SHEET", O, sheet.size)
