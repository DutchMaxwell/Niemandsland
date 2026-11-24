"""Smoke tests for the ruin-town kit forge: the pure-Python paths work without Blender."""
import json
import subprocess
import sys
from pathlib import Path

FORGE = Path(__file__).resolve().parent


def test_manifest_only_needs_no_blender(tmp_path):
    subprocess.run([sys.executable, str(FORGE / "dress_kit.py"), "--manifest-only", str(tmp_path)],
                   check=True, capture_output=True)
    m = json.loads((tmp_path / "ruintown_dress.json").read_text())
    assert m["version"] == 1
    assert len(m["modules"]) > 100
    assert m["sets"]["cobbles"]["licence"] == "CC0-1.0"
    assert all(e["stub"] for e in m["modules"].values())


def test_check_kit_imports_without_blender():
    sys.path.insert(0, str(FORGE))
    try:
        import check_kit
    finally:
        sys.path.pop(0)
    assert callable(check_kit.check_piece)
    assert callable(check_kit.openings)
