"""Tests for tools/merge_ctex_manifest.py — a missing patch must fail the merge."""
import json
import os
import subprocess
import sys
import tempfile

SCRIPT = os.path.join(os.path.dirname(__file__), "merge_ctex_manifest.py")


def _run(manifest, patches, extra_args=()):
    tmp = tempfile.mkdtemp(prefix="ctex_merge_test_")
    patches_dir = os.path.join(tmp, "ctex_patches")
    os.mkdir(patches_dir)
    with open(os.path.join(tmp, "manifest.json"), "w") as f:
        json.dump({"models": manifest}, f)
    for name, data in patches.items():
        with open(os.path.join(patches_dir, name), "w") as f:
            json.dump(data, f)
    return subprocess.run(
        [sys.executable, os.path.abspath(SCRIPT),
         os.path.join(tmp, "manifest.json"), patches_dir, *extra_args],
        cwd=tmp, capture_output=True, text=True,
    )


CTEX = {"ctex": {"mesh": {"sha256": "ctexsha"}, "tex": {"sha256": "texsha"}}}


def test_missing_prefix_patch_fails_merge():
    rc = _run(
        {"alien_hives/hive lord": {"sha256": "legacy1"},
         "mummified_undead/tomb guard": {"sha256": "legacy2"}},
        {"alien_hives.json": {"alien_hives/hive lord": CTEX}},
    )
    assert rc.returncode != 0, "missing patch file must fail the merge, not exit 0"
    assert "mummified_undead" in rc.stdout + rc.stderr


def test_allow_missing_waives_named_prefixes():
    rc = _run(
        {"alien_hives/hive lord": {"sha256": "legacy1"},
         "mummified_undead/tomb guard": {"sha256": "legacy2"}},
        {"alien_hives.json": {"alien_hives/hive lord": CTEX}},
        extra_args=("--allow-missing",),
    )
    assert rc.returncode == 0
    assert "mummified_undead" in rc.stdout, "--allow-missing must name the waived prefixes"


def test_unsafe_still_fails():
    rc = _run(
        {"alien_hives/hive lord": {"sha256": "ctexsha"}},
        {"alien_hives.json": {"alien_hives/hive lord": CTEX}},
    )
    assert rc.returncode != 0
