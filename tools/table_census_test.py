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
    txt.write_text(txt.read_text().replace("old_b 3 0", "old_b 3 1"))   # a prod-caller count
    res = run(root, "--check")
    assert res.returncode == 1 and "counter is stale" in res.stdout
    assert run(root, "--write").returncode == 0 and run(root, "--check").returncode == 0


def test_the_committed_report_has_no_test_caller_column(tmp_path):
    root = repo(tmp_path)
    txt = committed(root).read_text().splitlines()
    assert "grp scripts/a.gd:old_a 4 2" in txt             # lines and prod callers only
    assert "grp TOTAL 7 2" in txt
    assert "whole scripts/a.gd 13 0" in txt
    assert all(len(ln.split()) == 4 for ln in txt if ln.split()[0] in ("grp", "whole"))
    assert "old_a 4 2 2" not in "\n".join(txt)             # the test caller count is not committed
    assert "grp scripts/a.gd:old_a 4 2 2" in run(root).stdout   # the printed report still shows it


def test_a_moved_test_caller_count_is_reported_but_not_red(tmp_path):
    root = repo(tmp_path)
    txt = committed(root)
    before = txt.read_text()
    with (root / "test/x_test.gd").open("a") as f:
        f.write("\tFixture.old_b()\n")                     # one more test caller: never committed, never red
    assert run(root, "--check").returncode == 0
    assert txt.read_text() == before                       # the committed text does not move
    assert "old_b 3 0 2" in run(root).stdout               # the printed report shows the new test count
    txt.write_text(before.replace("old_b 3 0", "old_b 4 0"))   # the same edit on the LINES column is red
    assert run(root, "--check").returncode == 1


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


def test_runtime_census_appends_the_share_and_the_top_reasons(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    census.write_text(json.dumps({"ai_volleys": 40, "legacy": {"ai_volley": {
        "_all": 30, "split": 12, "weapon_rule:Blast": 9, "unit_rule:Tough": 3, "no_handle": 3}}}))
    out = run(root, "--runtime", str(census)).stdout.splitlines()
    assert out[-5:] == ["RUNTIME AI VOLLEYS ON TABLE: 75.0 %",
                        "   30.0 %      12  split",
                        "   22.5 %       9  weapon_rule:Blast",
                        "    7.5 %       3  no_handle",       # ties by name
                        "    7.5 %       3  unit_rule:Tough"]
    assert out[-6].startswith("TABLE LINES LEFT")           # appended to the printed report, not replacing it


def test_runtime_census_never_reaches_the_committed_report(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    census.write_text(json.dumps({"ai_volleys": 1, "legacy": {"ai_volley": {"_all": 1}}}))
    assert run(root, "--write", "--runtime", str(census)).returncode == 2
    assert run(root, "--check", "--runtime", str(census)).returncode == 2
    committed(root)
    assert "RUNTIME" not in (root / "test/one_core/table_census.txt").read_text()


def test_runtime_census_reports_what_one_group_alone_would_unlock(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    census.write_text(json.dumps({"ai_volleys": 40, "legacy": {"ai_volley": {"_all": 25}}, "legacy_sets": {"ai_volley": {
        "no_handle|weapon_rule:AP": 10,                                   # AP alone
        "no_handle|target_weapon_rule:AP|weapon_rule:AP": 6,              # shooter and target side of AP = still AP alone
        "no_handle|weapon_rule:AP|weapon_rule:Blast": 4,                  # needs two groups
        "no_handle|unit_rule:Tough": 3,
        "no_handle|split|weapon_rule:Blast": 2}}}))                       # the door fact `split` is a group of its own
    out = run(root, "--runtime", str(census)).stdout

    def block(title):   # the lines under `title` up to the next all-caps header
        lines = out.split(title + "\n")[1].splitlines()
        return lines[:next((i for i, ln in enumerate(lines) if ln[:1].isupper()), len(lines))]
    assert block("UNLOCKED IF THIS GROUP ALONE WERE ALLOWED:") == ["   40.0 %      16  AP", "    7.5 %       3  Tough"]
    assert block("VOLLEYS BY NUMBER OF GROUPS THEY NEED:") == ["   47.5 %      19  1 group(s)", "   15.0 %       6  2 group(s)"]
    assert block("MOST COMMON GROUPS ALLOWED FIRST (cumulative unlocked):") == [   # AP 20 volleys, Blast 6, Tough 3, split 2
        "   40.0 %      16  + AP (group 1)", "   50.0 %      20  + Blast (group 2)",
        "   57.5 %      23  + Tough (group 3)", "   62.5 %      25  + split (group 4)"]
    sets = block("TOP REASON SETS (no_handle left out):")
    assert sets[:3] == ["   25.0 %      10  weapon_rule:AP",
                        "   15.0 %       6  target_weapon_rule:AP + weapon_rule:AP",
                        "   10.0 %       4  weapon_rule:AP + weapon_rule:Blast"]
    assert len(sets) == 5


def test_runtime_census_says_so_when_no_volley_needs_a_single_group(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    census.write_text(json.dumps({"ai_volleys": 3, "legacy": {"ai_volley": {"_all": 3}},
                                  "legacy_sets": {"ai_volley": {"no_handle|weapon_rule:AP|weapon_rule:Blast": 3}}}))
    out = run(root, "--runtime", str(census)).stdout
    assert "UNLOCKED IF THIS GROUP ALONE WERE ALLOWED:\n  (none: no volley needs fewer than 2 groups)\n" in out


TAGGED = {**MANIFEST, "tag_vocabulary": "erlkoenig tree dead",
          "planner_tags": {"scripts/a.gd": {"erlkoenig": "old_a", "tree": "old_b door"}}}


def tagged(root, manifest=TAGGED):
    (root / "tools/table_census.json").write_text(json.dumps(manifest))
    return root


def test_planner_tags_print_functions_and_code_lines_per_tag_above_an_unchanged_counter(tmp_path):
    out = run(tagged(repo(tmp_path))).stdout.splitlines()
    # old_a: 4 lines to the next declaration, minus the blank and the column-0 comment before old_b = 2 code lines
    head = out[:out.index("TEST CALLERS BY TAG") - 1]   # the printed-only section comes last, after a blank line
    assert head[-4:] == ["planner_tag erlkoenig 1 2", "planner_tag tree 2 5", "planner_tag TOTAL 3 7", "TABLE LINES LEFT: 20"]


def test_check_is_red_on_an_untagged_planner_function_and_green_once_tagged(tmp_path):
    root = tagged(repo(tmp_path))
    committed(root)
    assert run(root, "--check").returncode == 0
    with (root / "scripts/a.gd").open("a") as f:
        f.write("\nfunc fresh() -> void:\n\tpass\n")
    res = run(root, "--check")
    assert res.returncode == 1 and "scripts/a.gd:fresh has no planner tag" in res.stdout
    assert run(root, "--write").returncode == 1          # the counter is never committed with an untagged function
    tagged(root, {**TAGGED, "planner_tags": {"scripts/a.gd": {"erlkoenig": "old_a fresh", "tree": "old_b door"}}})
    assert run(root, "--write").returncode == 0 and run(root, "--check").returncode == 0


def test_check_is_red_on_a_double_tag_and_on_an_unknown_tag(tmp_path):
    root = repo(tmp_path)
    twice = {**TAGGED, "planner_tags": {"scripts/a.gd": {"erlkoenig": "old_a door", "tree": "old_a old_b door"}}}
    res = run(tagged(root, twice), "--check")
    assert res.returncode == 1 and "scripts/a.gd:old_a carries two planner tags" in res.stdout
    typo = {**TAGGED, "planner_tags": {"scripts/a.gd": {"erlkonig": "old_a old_b door"}}}
    res = run(tagged(root, typo), "--check")
    assert res.returncode == 1 and "unknown planner tag 'erlkonig'" in res.stdout


def test_a_stale_tag_line_is_red_and_a_tagged_function_that_is_gone_is_an_error(tmp_path):
    root = tagged(repo(tmp_path))
    txt = committed(root)
    txt.write_text(txt.read_text().replace("planner_tag tree 2 5", "planner_tag tree 2 4"))
    res = run(root, "--check")
    assert res.returncode == 1 and "counter is stale" in res.stdout
    gone = {**TAGGED, "planner_tags": {"scripts/a.gd": {"tree": "old_a old_b door vanished"}}}
    res = run(tagged(root, gone))
    assert res.returncode != 0 and "scripts/a.gd:vanished not found" in res.stderr


def test_runtime_census_shadow_section_ranks_groups_and_names_deny_and_unexplained(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    eq = lambda *labels: {"equal": True, "first_diff": "", "labels": list(labels), "unported": []}
    ne = lambda diff, *labels: {"equal": False, "first_diff": diff, "labels": list(labels), "unported": []}
    census.write_text(json.dumps({"ai_volleys": 8, "legacy": {"ai_volley": {"_all": 8}}, "shadow": [
        eq("weapon_rule:AP"), eq("weapon_rule:AP"), eq("no_handle"),
        ne("rolls", "weapon_rule:AP", "target_rule:Regeneration"), ne("rolls", "target_rule:Regeneration"),
        ne("state", "unit_rule:Tough", "weapon_rule:AP"), eq("unit_rule:Tough"),
        {**ne("faces", "no_handle"), "unported": ["strafing"]}]}))
    out = run(root, "--runtime", str(census)).stdout.split("SHADOW:")[1].splitlines()
    assert out[0] == " 8 volleys replayed in the core, 4 equal (50.0 %)"
    assert out[1:5] == ["MISMATCHES BY FIRST DIFF:", "   25.0 %       2  rolls",
                        "   12.5 %       1  faces", "   12.5 %       1  state"]
    # Regeneration: 2 of 2 mismatch, the other 6 volleys 2 of 6 -> lift 3; AP 2 of 4 vs 2 of 4 -> 1; Tough 1 of 2 vs 3 of 6.
    assert out[6].split() == ["2", "2", "100.0", "%", "3.00", "Regeneration"]
    assert [ln.split()[-1] for ln in out[6:9]] == ["Regeneration", "AP", "Tough"]
    assert "DENY CANDIDATES (no volley with the group matches): Regeneration" in out
    assert out[-2:] == ["UNEXPLAINED (mismatching, no rule group): 1", "  faces  unported=strafing"]


def test_runtime_census_deny_mode_names_taken_equal_unequal_and_blockers(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    rec = lambda deny, equal=True, diff="": {"deny": deny, "equal": equal, "first_diff": diff, "labels": [],
                                             "shooter": "Hive Swarms", "targets": ["Assault Brothers", "Flamer Beast"],
                                             "unported": []}
    census.write_text(json.dumps({"ai_volleys": 3, "legacy": {"ai_volley": {"_all": 3}}, "shadow": [
        rec([]), rec([], equal=False, diff="rolls"), rec(["unit_rule:Sturdy"], equal=False, diff="state")]}))
    out = run(root, "--runtime", str(census)).stdout.split("DENY MODE")[1].splitlines()
    assert "taken 2 of 3" in out[0] and "equal 1" in out[0]
    assert out[1] == "  UNEQUAL Hive Swarms -> Assault Brothers, Flamer Beast: rolls"
    assert out[2] == "BLOCKERS (volleys, one per label):"
    assert out[3].split() == ["1", "Sturdy"]


def test_runtime_census_deny_mode_is_silent_without_deny_fields(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    census.write_text(json.dumps({"ai_volleys": 1, "legacy": {"ai_volley": {"_all": 1}},
                                  "shadow": [{"equal": True, "first_diff": "", "labels": [], "unported": []}]}))
    out = run(root, "--runtime", str(census)).stdout
    assert "DENY MODE" not in out
    assert out.rstrip().endswith("UNEXPLAINED (mismatching, no rule group): 0")


def test_runtime_census_without_shadow_records_prints_no_shadow_section(tmp_path):
    root = repo(tmp_path)
    census = tmp_path / "census.json"
    census.write_text(json.dumps({"ai_volleys": 1, "legacy": {"ai_volley": {"_all": 1}}}))
    assert "SHADOW" not in run(root, "--runtime", str(census)).stdout


def test_the_test_caller_section_is_printed_and_never_committed(tmp_path):
    root = tagged(repo(tmp_path))
    out = run(root).stdout.splitlines()
    assert out[-4:] == ["", "TEST CALLERS BY TAG", "test_callers erlkoenig 1 2", "test_callers tree 1 1"]
    txt = committed(root).read_text()              # old_a: name( plus call("old_a"); old_b: one call; door: none
    assert "TEST CALLERS BY TAG" not in txt and "test_callers" not in txt
    assert run(root, "--check").returncode == 0    # the section never moves the committed counter


GATE_PROD = """class_name Fixture
extends RefCounted

func old_a(x: int) -> int:
	return x + 1

func old_b() -> void:
	pass
"""
GATE_TEST = "func t():\n\tFixture.old_a(4)\n"
GATE = {**MANIFEST, "tag_vocabulary": "gd_search keep",
        "planner_tags": {"scripts/a.gd": {"gd_search": "old_a", "keep": "old_b"}}}


def gate_repo(root, test_text=GATE_TEST):
    for rel, text in (("scripts/a.gd", GATE_PROD), ("test/x_test.gd", test_text)):
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text)
    (root / "tools").mkdir(parents=True, exist_ok=True)
    (root / "tools/table_census.json").write_text(json.dumps(GATE))
    (root / "test/one_core").mkdir()
    return root


def test_gate_tag_is_red_on_one_test_caller(tmp_path):
    res = run(gate_repo(tmp_path), "--gate-tag", "gd_search")
    assert res.returncode == 1
    assert "test_callers gd_search 1 1" in res.stdout
    assert "::error::test caller of gd_search: scripts/a.gd:old_a" in res.stdout


def test_gate_tag_is_green_once_the_test_call_is_removed(tmp_path):
    root = gate_repo(tmp_path)
    (root / "test/x_test.gd").write_text("func t():\n\tpass\n")   # planted fault: the call is gone
    res = run(root, "--gate-tag", "gd_search")
    assert res.returncode == 0
    assert "test_callers gd_search 0 0" in res.stdout


def test_gate_tag_is_green_for_a_tag_no_test_calls(tmp_path):
    res = run(gate_repo(tmp_path), "--gate-tag", "keep")
    assert res.returncode == 0 and "test_callers keep 0 0" in res.stdout


def test_gate_tag_rejects_an_unknown_tag_and_never_writes(tmp_path):
    root = gate_repo(tmp_path)
    res = run(root, "--gate-tag", "nope")
    assert res.returncode == 2 and "unknown planner tag" in res.stderr
    assert run(root, "--write", "--gate-tag", "gd_search").returncode == 2
    assert not (root / "test/one_core/table_census.txt").exists()


QUAL = {**MANIFEST, "tag_vocabulary": "gd_search keep", "planner_tags": {
    "scripts/p.gd": {"gd_search": "shared_fn"}, "scripts/o.gd": {"keep": "shared_fn"}}}


def test_a_test_caller_counts_only_for_the_class_of_the_file(tmp_path):
    root = repo(tmp_path)
    (root / "scripts/p.gd").write_text("class_name Planner\nextends RefCounted\n\nfunc shared_fn() -> void:\n\tpass\n")
    (root / "scripts/o.gd").write_text("class_name Other\nextends RefCounted\n\nfunc shared_fn() -> void:\n\tpass\n")
    (root / "test/x_test.gd").write_text("func t():\n\tOther.shared_fn()\n")   # the same name, another class
    (root / "tools/table_census.json").write_text(json.dumps(QUAL))
    out = run(root).stdout
    assert "test_callers gd_search 0 0" in out and "test_callers keep 1 1" in out
    assert run(root, "--gate-tag", "gd_search").returncode == 0
