"""Contract checks for tools/table_census_soak.sh: the dry run and the merge (no Godot is started)."""
import json
import os
from pathlib import Path
import subprocess

SCRIPT = Path(__file__).with_name("table_census_soak.sh")


def run(*args, **env):
    return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, check=False,
                          env={**os.environ, **env})


def test_dry_run_prints_the_commands_and_plays_nothing(tmp_path):
    res = run("3", DRY_RUN="1", OUT=str(tmp_path / "o"), SIZES="1000 2000")
    games = [ln for ln in res.stdout.splitlines() if ln.startswith("[soak] game")]
    assert res.returncode == 0 and len(games) == 3
    assert "(gf 1000 pts)" in games[0] and "(aof 1000 pts)" in games[1] and "(gf 2000 pts)" in games[2]
    for i, line in enumerate(games):
        assert f"NML_TABLE_CENSUS={tmp_path}/o/game_{i}.json" in line and "res://tools/arena_match.gd" in line
        assert "MemoryMax=12G" in line and "--headless" in line
    assert sorted(p.name for p in (tmp_path / "o").iterdir()) == []   # no game log, no census.json


def test_real_run_without_lists_is_refused(tmp_path):
    res = run("1", OUT=str(tmp_path / "o"), LISTS_GF="", LISTS_AOF="")
    assert res.returncode == 2 and "need >= 2 lists" in res.stderr


def test_merge_equals_the_hand_sum(tmp_path):
    games = [{"core_ai_runs": 3, "legacy": {"ai_volley": {"_all": 5, "split": 2, "weapon_rule:Blast": 3},
                                            "ai_strafe": {"_all": 1, "no_core": 1}},
              "legacy_sets": {"ai_volley": {"split": 2, "weapon_rule:Blast": 3}}},
             {"core_ai_runs": 9, "legacy": {"ai_volley": {"_all": 7, "split": 1, "unit_rule:Tough": 6}},
              "legacy_sets": {"ai_volley": {"split": 1, "split|unit_rule:Tough": 6}}}]
    for i, g in enumerate(games):
        (tmp_path / f"game_{i}.json").write_text(json.dumps(g))
    res = run("merge", str(tmp_path))
    out = json.loads((tmp_path / "census.json").read_text())
    assert res.returncode == 0 and out["games"] == 2 and out["core_ai_runs"] == 12
    assert out["legacy"]["ai_volley"] == {"_all": 12, "split": 3, "weapon_rule:Blast": 3, "unit_rule:Tough": 6}
    assert out["legacy"]["ai_strafe"] == {"_all": 1, "no_core": 1}
    assert out["legacy_sets"] == {"ai_volley": {"split": 3, "weapon_rule:Blast": 3, "split|unit_rule:Tough": 6}}
    assert out["ai_volleys"] == 24                       # 12 on the table + 12 through the core
    assert out["ai_volley_share_pct"]["unit_rule:Tough"] == 25.0 and out["ai_volley_share_pct"]["_all"] == 50.0
    assert "games 2  ai_volleys 24  on the table 12" in res.stdout
    top = [ln.split()[-1] for ln in res.stdout.splitlines()[1:]]
    assert top == ["unit_rule:Tough", "split", "weapon_rule:Blast"]   # by count, `_all` left out
