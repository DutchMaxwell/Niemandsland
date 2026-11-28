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



def test_a_look_markdown_file_lends_no_name_but_a_look_script_still_does(tmp_path):
    assert _tree(tmp_path, tools__boardgen__README_DOT_md="see BoardgenKit\n", scripts__other_DOT_gd="# README\nvar readme := 1\nvar README := 2\n") == []
    assert _tree(tmp_path, tools__boardgen__README_DOT_md="x\n", scripts__other_DOT_gd="var k := BoardgenKit.new()\n")

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


def test_look_list_never_claims_a_file_the_core_reads():
    from ci_path_classes import in_class
    for path in ["assets/model_manifest.json", "assets/ruins_manifest.json", "assets/solo/x.json", "tools/a.py",
                 "core/x.rs", "data/x.json", "test/fixtures/x.json", "scripts/main.gd", "project.godot"]:
        assert not in_class(path, "look"), f"{path} must never be in tools/ci_look_paths.txt"


def _mp_ignored_globs():
    import re
    wf = open(os.path.join(ROOT, ".github", "workflows", "mp-two-instance.yml"), encoding="utf-8").read()
    items = []
    for line in wf.split("paths-ignore:\n", 1)[1].splitlines():
        m = re.match(r"\s*-\s*'([^']+)'\s*$", line)
        if not m:
            break
        items.append(m.group(1))
    return items


def test_mp_workflow_ignores_exactly_docs_and_the_look_class():
    from ci_path_classes import CLASSES
    assert _mp_ignored_globs() == ["docs/**"] + CLASSES["look"]["globs"], \
        "mp-two-instance.yml paths-ignore must equal docs/** + tools/ci_look_paths.txt: add the same glob to both in one PR"


def test_mp_run_is_skipped_only_when_every_changed_file_is_docs_or_look():
    import re
    # GitHub path filters: ** crosses '/', * does not. A PR skips the workflow only if EVERY changed file matches.
    rx = [re.compile(re.escape(g).replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + r"\Z") for g in _mp_ignored_globs()]
    skipped = lambda files: all(any(r.match(f) for r in rx) for f in files)  # noqa: E731
    look = ["scripts/boardgen_kit.gd", "shaders/tiefwerk_relief.gdshaderinc", "assets/ruintown_manifest.json",
            "test/tiefwerk_library_test.gd", "tools/boardgen/capture.py", "docs/a/b.md"]
    assert skipped(look) and is_only(look, "look")  # LOOK + docs only: no MP run
    for files in (look + ["scripts/network_manager.gd"], ["core/nml-core/src/lib.rs"], ["scripts/main.gd"], ["project.godot"],
                  look + ["tools/ci_look_paths.txt"], ["tools/boardgen/sub/x.py"]):
        assert not skipped(files), f"MP must run for {files}"  # the last one: the filter is stricter than the classifier, never looser
        assert not (skipped(files) and not is_only(files, "look"))


def test_the_kit_wait_door_is_main_gd_only(tmp_path):
    """GEN-13 (lead 28.11.): the setup's board card reaches BoardgenKit.wait_state through ONE door in main.gd; the same
    call from a setup or menu file (plant) still fails."""
    door = "\treturn BoardgenKit.wait_state(holder, kit_theme)\n"
    assert _tree(tmp_path, scripts__main_DOT_gd=BASE["scripts/main.gd"] + door) == []
    assert _tree(tmp_path, scripts__setup_layout_step_DOT_gd=door)
    assert _tree(tmp_path, scripts__main_DOT_gd=BASE["scripts/main.gd"] + "\tvar k := BoardgenKit.new(theme)\n")
