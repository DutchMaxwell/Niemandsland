#!/usr/bin/env python3
"""Tests for tools/check_release_zip.py (layouts as in the v0.3.15.0-alpha zips).

Run:  python3 -m pytest -q tools/check_release_zip_test.py
"""

import os
import subprocess
import sys
import zipfile

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_release_zip.py")
APP = "Niemandsland.app/Contents/"
GOOD = [("linux", ["Niemandsland.x86_64", "libnml_core_godot.so"]),
        ("linux", ["a/b/libnml_core_godot.so"]),
        ("windows", ["Niemandsland.exe", "nml_core_godot.dll"]),
        ("macos", [APP + "MacOS/Niemandsland", APP + "Frameworks/libnml_core_godot.dylib"])]
BAD = [("linux", ["Niemandsland.x86_64", "Niemandsland.pck"]),
       ("linux", ["xlibnml_core_godot.so"]),
       ("windows", ["Niemandsland.exe", "Niemandsland.pck"]),
       ("macos", [APP + "MacOS/Niemandsland"]),
       ("macos", [APP + "MacOS/libnml_core_godot.dylib"])]  # present, but not in Frameworks


def run(tmp_path, names, platform):
    path = tmp_path / "t.zip"
    if names is None:
        path.write_text("not a zip")
    else:
        with zipfile.ZipFile(path, "w") as z:
            for n in names:
                z.writestr(n, "x")
    return subprocess.run([sys.executable, SCRIPT, str(path), platform],
                          capture_output=True, text=True)


@pytest.mark.parametrize("platform,names", GOOD)
def test_a_zip_with_the_core_passes(tmp_path, platform, names):
    r = run(tmp_path, names, platform)
    assert r.returncode == 0 and r.stdout.startswith("OK"), r


@pytest.mark.parametrize("platform,names", BAD)
def test_a_zip_without_the_core_fails_with_a_message(tmp_path, platform, names):
    r = run(tmp_path, names, platform)
    assert r.returncode == 1 and "FAIL" in r.stderr and "nml_core_godot" in r.stderr, r


@pytest.mark.parametrize("platform,names,msg", [
    ("windows", GOOD[0][1], "FAIL"),  # a linux zip checked as windows
    ("beos", GOOD[0][1], "usage"), ("linux", None, "cannot read")])
def test_wrong_platform_or_input_fails(tmp_path, platform, names, msg):
    r = run(tmp_path, names, platform)
    assert r.returncode == 1 and msg in r.stderr, r
