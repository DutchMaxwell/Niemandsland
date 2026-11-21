#!/usr/bin/env python3
"""luma_rows.py UNGRADED_DIR GRADED_DIR: the mean luma (0-255, whole 1600 x 900 frame, PIL 'L') of the overview45 and play stills of two default town captures
(`godot -s tools/boardgen/bg_capture_town.gd -- OUT seeds=7,41,25 only=overview,play`, a real display): one without the ruin town's grade (main before it) and one with it.
Prints the "ungraded" / "graded" parts of tools/boardgen/town_grade_luma.json, which the gdUnit pin in test/boardgen_mood_test.gd reads. Needs Pillow."""
import glob
import json
import os
import sys

from PIL import Image, ImageStat


def luma(directory):
    out = {}
    for path in sorted(glob.glob(os.path.join(directory, "s*_*.jpg"))):
        name = os.path.basename(path)[:-4]
        if name.endswith(("overview45", "play")):
            out[name] = round(ImageStat.Stat(Image.open(path).convert("L")).mean[0], 1)
    return out


print(json.dumps({"ungraded": luma(sys.argv[1]), "graded": luma(sys.argv[2])}, indent=1))
