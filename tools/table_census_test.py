"""Contract checks for tools/table_census.py on a three-function fixture (built at test time)."""
import json
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).with_name("table_census.py")
PROD = """class_name Fixture
extends RefCounted

func old_a(x: int) -> int:
	return x + 1
# a comment that mentions old_a(1) is not a caller

func old_b() -> void:
	old_a(2)   # a trailing comment with old_b() is not a caller

func door() -> void:
	old_a(3)
	_label(self, "old_b")   # a quoted label is not a call
"""
TEST = "func t():\n\tFixture.old_a(4)\n\tFixture.old_b()\n\tFixture.call(\"old_a\", 5)\n"
MANIFEST = {"groups": {"grp": ["scripts/a.gd:old_a", "scripts/a.gd:old_b"], "whole": ["scripts/a.gd"]},
            "allowed_callers": {"scripts/a.gd:old_a": ["scripts/a.gd:door", "@grp"],
                                "scripts/a.gd:old_b": []}}


def repo(tmp_path):
    for rel, text in (("scripts/a.gd", PROD), ("tools/t.gd", "func g():\n\tpass\n"), ("test/x_test.gd", TEST)):
        (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / rel).write_text(text)
    (tmp_path / "tools/table_census.json").write_text(json.dumps(MANIFEST))
    (tmp_path / "test/one_core").mkdir()
    return tmp_path


def run(root, *args):
    return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), *args],
                          capture_output=True, text=True, check=False)


def committed(root):
    assert run(root, "--write").returncode == 0
    return root / "test/one_core/table_census.txt"


def test_report_counts_lines_and_callers_and_ignores_comments_and_labels(tmp_path):
    root = repo(tmp_path)
    out = run(root).stdout.splitlines()
    assert "grp scripts/a.gd:old_a 4 2 2" in out        # 4 lines to the next decl; prod: old_b + door; test: a call + call("old_a")
    assert "grp scripts/a.gd:old_b 3 0 1" in out        # the comment mention and the quoted label do not count
    assert "whole scripts/a.gd 13 0 1" in out           # whole file: its lines; the test file names the class
    assert out[-1] == "TABLE LINES LEFT: 20"


def test_check_is_green_on_the_committed_state(tmp_path):
    root = repo(tmp_path)
    committed(root)
    assert run(root, "--check").returncode == 0


def test_check_is_red_on_a_stale_counter(tmp_path):
    root = repo(tmp_path)
    txt = committed(root)
    txt.write_text(txt.read_text().replace("old_b 3 0 1", "old_b 3 0 2"))
    res = run(root, "--check")
    assert res.returncode == 1 and "counter is stale" in res.stdout
    assert run(root, "--write").returncode == 0 and run(root, "--check").returncode == 0


def test_check_is_red_on_a_new_prod_caller_and_green_once_listed(tmp_path):
    root = repo(tmp_path)
    with (root / "scripts/a.gd").open("a") as f:
        f.write("\nfunc sneaky() -> void:\n\told_b()\n")
    committed(root)                                      # counter current: only the caller arm can fire
    res = run(root, "--check")
    assert res.returncode == 1 and "new caller of scripts/a.gd:old_b: scripts/a.gd:sneaky" in res.stdout
    listed = {**MANIFEST, "allowed_callers": {**MANIFEST["allowed_callers"], "scripts/a.gd:old_b": ["scripts/a.gd:sneaky"]}}
    (root / "tools/table_census.json").write_text(json.dumps(listed))
    assert run(root, "--check").returncode == 0


def test_a_listed_caller_that_is_gone_is_not_red(tmp_path):
    root = repo(tmp_path)
    committed(root)
    prod = (root / "scripts/a.gd").read_text().replace("\told_a(3)\n", "\tpass\n")
    (root / "scripts/a.gd").write_text(prod)
    committed(root)
    assert run(root, "--check").returncode == 0


def test_a_manifest_entry_without_its_function_is_an_error(tmp_path):
    root = repo(tmp_path)
    (root / "tools/table_census.json").write_text(json.dumps({"groups": {"grp": ["scripts/a.gd:gone"]}}))
    res = run(root)
    assert res.returncode != 0 and "scripts/a.gd:gone not found" in res.stderr
