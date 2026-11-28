"""The LOOK short run: which PRs get it, and what runs in it."""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from ci_path_classes import CANARY, lane, suites, walkers  # noqa: E402

TOOL = os.path.join(ROOT, "tools", "ci_path_classes.py")
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]


def _git(repo, *args):
    return subprocess.run([*GIT, *args], cwd=repo, check=True, capture_output=True, text=True).stdout


def _pr(tmp_path, base, change):
    """A repo whose HEAD is a merge commit of `change` (path -> text, None = delete, tuple = rename) onto `base`: GitHub's merge ref."""
    tmp_path.mkdir(parents=True, exist_ok=True)
    _git(tmp_path, "init", "-q", "-b", "main")
    for rel, text in base.items():
        (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / rel).write_text(text)
    _git(tmp_path, "add", "-A"), _git(tmp_path, "commit", "-qm", "base")
    _git(tmp_path, "checkout", "-qb", "pr")
    for rel, text in change.items():
        if isinstance(text, tuple):
            _git(tmp_path, "mv", rel, text[0])
        elif text is None:
            _git(tmp_path, "rm", "-q", rel)
        else:
            (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
            (tmp_path / rel).write_text(text)
    _git(tmp_path, "add", "-A"), _git(tmp_path, "commit", "-qm", "pr")
    _git(tmp_path, "checkout", "-q", "main")
    (tmp_path / "unrelated.txt").write_text("main moved\n")
    _git(tmp_path, "add", "-A"), _git(tmp_path, "commit", "-qm", "main moved")
    _git(tmp_path, "merge", "-q", "--no-ff", "-m", "merge ref", "pr")
    return subprocess.run([sys.executable, TOOL, "--pr-is-only", "look"], cwd=tmp_path, capture_output=True, text=True).returncode


BASE = {"scripts/boardgen_kit.gd": "var a := 1\n", "scripts/main.gd": "var m := 1\n", "docs/a.md": "x\n", "core/x.rs": "// 1\n"}


def test_look_and_docs_only_pr_gets_the_short_run(tmp_path):
    assert _pr(tmp_path, BASE, {"scripts/boardgen_kit.gd": "var a := 2\n", "docs/a.md": "y\n", "test/boardgen_new_test.gd": "x\n"}) == 0


def test_any_other_file_or_a_rename_out_of_the_game_gets_the_full_run(tmp_path):
    assert _pr(tmp_path / "a", BASE, {"scripts/boardgen_kit.gd": "var a := 2\n", "scripts/main.gd": "var m := 2\n"}) == 1
    assert _pr(tmp_path / "b", BASE, {"core/x.rs": "// 2\n"}) == 1
    assert _pr(tmp_path / "c", BASE, {"scripts/main.gd": ("scripts/boardgen_main.gd",)}) == 1  # main.gd leaves: the OLD path counts
    assert _pr(tmp_path / "d", BASE, {"scripts/boardgen_kit.gd": None, "tools/ci_look_paths.txt": "x\n"}) == 1  # widening the class is no LOOK change


def test_a_merge_ref_that_cannot_be_diffed_is_not_look_only(tmp_path):
    _git(tmp_path, "init", "-q", "-b", "main")
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts/boardgen_kit.gd").write_text("x\n")
    _git(tmp_path, "add", "-A"), _git(tmp_path, "commit", "-qm", "only")  # no HEAD^1
    assert subprocess.run([sys.executable, TOOL, "--pr-is-only", "look"], cwd=tmp_path, capture_output=True, text=True).returncode == 1


def test_lane_is_class_suites_walkers_and_the_canary(tmp_path):
    files = {"scripts/boardgen_kit.gd": "class_name BoardgenKit\n", "test/boardgen_kit_test.gd": "BoardgenKit.new()\n",
             "test/walk_test.gd": 'for p in _files("res://scripts"):\n', "test/shader_walk_test.gd": "walk('res://shaders/')\n",
             "test/other_test.gd": 'load("res://scripts/x.gd")\n', "test/ai_test.gd": "x\n"}
    for rel, text in files.items():
        (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / rel).write_text(text)
    got = lane(str(tmp_path), sorted(files), "look")
    assert got == sorted(["test/boardgen_kit_test.gd", "test/walk_test.gd", "test/shader_walk_test.gd", CANARY])
    assert "test/other_test.gd" not in got and walkers(str(tmp_path), sorted(files)) == ["test/shader_walk_test.gd", "test/walk_test.gd"]


def test_the_canary_really_boots_the_game_and_is_not_a_class_suite():
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")[:-1]
    text = open(os.path.join(ROOT, CANARY), encoding="utf-8").read()
    assert "scene_runner(E2EBoot.MAIN_SCENE)" in text, "the canary must boot scenes/main.tscn"
    assert 'MAIN_SCENE := "res://scenes/main.tscn"' in open(os.path.join(ROOT, "test/e2e/e2e_boot.gd"), encoding="utf-8").read()
    assert CANARY not in suites(ROOT, files, "look") and CANARY in lane(ROOT, files, "look")
    # and it asserts what no class suite can: no board-look node, no collider in table_overlay, the ground is the bare table
    for needle in ('find_children("Boardgen*"', '"table_overlay"', "CollisionObject3D", "_surface_y_under"):
        assert needle in text, f"the canary lost its check: {needle}"


def test_build_yml_wires_the_short_run_and_adds_no_skip():
    import re
    wf = open(os.path.join(ROOT, ".github", "workflows", "build.yml"), encoding="utf-8").read()
    for needle in ("fetch-depth: 2", '[ "$BASE_REF" = "main" ]', "--pr-is-only look", "&& '[0]' ||", "--lane look > look_suites.txt", "--suite-file look_suites.txt",
                   "tools/ci_look_lane_test.py"):
        assert needle in wf, f"build.yml lost the LOOK short run wiring: {needle}"
    m = re.search(r"^  test:\n(?:    .*\n)*?    if: (.*)$", wf, re.M)
    assert m and "look_only" not in m.group(1), "the test job must RUN for a LOOK-only PR (a skip would need a path reason in all_required.py)"


def test_the_short_run_is_for_a_pr_against_main_only(tmp_path):
    """A stacked child is diffed against its parent branch: LOOK-only there says nothing about the parent's own files."""
    import re
    import textwrap
    wf = open(os.path.join(ROOT, ".github", "workflows", "build.yml"), encoding="utf-8").read()
    m = re.search(r"      - name: LOOK-only PR\?\n(?:        .*\n)*?        run: \|\n((?:          .*\n)+)", wf)
    assert m, "the LOOK-only step moved: update this test"
    script = textwrap.dedent(m.group(1))
    (tmp_path / "tools").mkdir()
    (tmp_path / "tools" / "ci_path_classes.py").write_text("import sys\nsys.exit(0)\n")  # the diff says: LOOK-only

    def look_only(event, base):
        out = tmp_path / "out"
        out.write_text("")
        env = dict(os.environ, EVENT=event, BASE_REF=base, GITHUB_OUTPUT=str(out))
        subprocess.run(["bash", "-c", script], cwd=tmp_path, env=env, check=True, capture_output=True)
        return out.read_text().strip()

    assert look_only("pull_request", "main") == "look_only=true"
    assert look_only("pull_request", "roofsf/f1") == "look_only=false"  # stacked child of a parent that may change core/
    assert look_only("pull_request", "") == "look_only=false"
    assert look_only("push", "main") == "look_only=false"
