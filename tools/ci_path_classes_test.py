"""tools/ci_path_classes.py: the LOOK class stays provably isolated (fixture trees + the real tree)."""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from ci_path_classes import check, is_only  # noqa: E402

BASE = {
    "scripts/boardgen_kit.gd": "class_name BoardgenKit\n",
    "scripts/boardgen_greybox.gd": "class_name BoardgenGreybox\n",
    "test/boardgen_kit_test.gd": "var k := BoardgenKit.new()\n",
    "scripts/main.gd": "\tBoardgenGreybox.attach_from_env(table)\n",
    "scripts/other.gd": "var x := 1\n",
}


def _tree(tmp_path, **extra):
    files = dict(BASE, **{k.replace("__", "/").replace("_DOT_", "."): v for k, v in extra.items()})
    for rel, text in files.items():
        (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / rel).write_text(text)
    return check(str(tmp_path), sorted(files), "look")


def test_fixture_with_only_the_door_passes(tmp_path):
    assert _tree(tmp_path) == []


def test_outside_script_naming_a_class_fails(tmp_path):
    assert _tree(tmp_path, scripts__other_DOT_gd="var k := BoardgenKit.new()\n")


def test_outside_script_loading_a_class_file_by_path_fails(tmp_path):
    assert _tree(tmp_path, scripts__other_DOT_gd='load("res://scripts/boardgen_kit.gd")\n')


def test_a_second_call_into_main_fails(tmp_path):
    assert _tree(tmp_path, scripts__main_DOT_gd="\tBoardgenGreybox.attach_from_env(t)\n\tBoardgenKit.build()\n")


def test_outside_test_setting_the_env_flag_fails(tmp_path):
    assert _tree(tmp_path, test__e2e__x_test_DOT_gd='OS.set_environment("NML_BOARDGEN_SEED", "7")\n')


def test_is_only():
    assert is_only(["scripts/boardgen_kit.gd", "docs/a.md", "test/tiefwerk_library_test.gd"], "look")
    assert not is_only(["scripts/boardgen_kit.gd", "scripts/main.gd"], "look")
    assert not is_only([], "look")


def test_real_tree_is_isolated():
    p = subprocess.run([sys.executable, "tools/ci_path_classes.py", "--check"], cwd=ROOT, capture_output=True, text=True)
    assert p.returncode == 0, p.stdout


def test_a_whole_line_comment_is_not_a_reference_but_a_shader_include_is(tmp_path):
    assert _tree(tmp_path, scripts__other_DOT_gd="## lit like BoardgenKit's board\n") == []
    assert _tree(tmp_path, shaders__x_DOT_gdshader='#include "res://shaders/boardgen_kit.gdshaderinc"\n')
