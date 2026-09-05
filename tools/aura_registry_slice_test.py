"""Contract checks for the deterministic, metadata-only aura generator."""
import json
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).with_name("aura_registry_slice.py")
BASES = ["Scout", "Ambush", "Rapid Rush", "Relentless", "Piercing Assault"]


def fixture_repo(tmp_path):
    folder = tmp_path / "assets/solo"
    folder.mkdir(parents=True)
    data = {"common": {name: {"primitive": name} for name in BASES},
            "factions": {"test": {name + " Aura": {"primitive": None, "rated": False,
                                                    "book_version": "3.5.3"} for name in BASES}}}
    data["factions"]["test"]["Piercing Shooter Aura"] = {"primitive": None}
    data["factions"]["legacy"] = {"Rapid Rush Aura": {
        "primitive": "Rapid Rush", "params": {"rush_mod": 6}}}
    for system in ("gf", "gff", "aof", "aofs", "aofr"):
        (folder / f"rules_mechanics_{system}.json").write_text(json.dumps(data))
    return tmp_path


def run(repo, *args):
    return subprocess.run([sys.executable, str(SCRIPT), "--repo", str(repo), *args],
                          capture_output=True, text=True, check=False)


def test_priority_is_metadata_only_and_idempotent(tmp_path):
    repo = fixture_repo(tmp_path)
    first = run(repo, "--priority", "--write")
    assert first.returncode == 0, first.stderr
    assert json.loads(first.stdout)["changed_entries"] == 25
    data = json.loads((repo / "assets/solo/rules_mechanics_gf.json").read_text())
    for name in BASES:
        assert data["factions"]["test"][name + " Aura"] == {
            "primitive": "Aura Channel", "params": {"grants": name},
            "rated": False, "book_version": "3.5.3"}
        assert data["common"][name] == {"primitive": name}
    assert data["factions"]["test"]["Piercing Shooter Aura"]["primitive"] is None
    assert data["factions"]["legacy"]["Rapid Rush Aura"] == {
        "primitive": "Rapid Rush", "params": {"rush_mod": 6}}
    assert run(repo, "--priority").returncode == 0
    data["common"]["New Unimplemented Rule"] = {"primitive": None}
    (repo / "assets/solo/rules_mechanics_gf.json").write_text(json.dumps(data))
    assert run(repo, "--audit", "--write").returncode == 2


def test_plans_are_stable_and_deferred_names_are_rejected(tmp_path):
    repo = fixture_repo(tmp_path)
    before = {path: path.read_bytes() for path in repo.rglob("*.json")}
    first = run(repo, "--plan", "--limit", "10")
    assert first.returncode == 0, first.stderr
    assert first.stdout == run(repo, "--plan", "--limit", "10").stdout
    batches = [row for line in first.stdout.splitlines() if "names" in (row := json.loads(line))]
    assert [row["entries"] for row in batches] == [10, 10, 5]
    assert [name for row in batches for name in row["names"]] == sorted(name + " Aura" for name in BASES)
    assert run(repo, "--names", "Piercing Shooter Aura", "--write").returncode == 2
    assert before == {path: path.read_bytes() for path in repo.rglob("*.json")}


def test_reserved_names_stay_open_and_out_of_plans(tmp_path):
    repo = fixture_repo(tmp_path)
    args = ("--plan", "--limit", "10", "--exclude-names", "Ambush Aura")
    first = run(repo, *args)
    assert first.returncode == 0, first.stderr
    assert first.stdout == run(repo, *args).stdout
    batches = [row for line in first.stdout.splitlines() if "names" in (row := json.loads(line))]
    assert [row["entries"] for row in batches] == [10, 10]
    assert "Ambush Aura" not in [name for row in batches for name in row["names"]]
    assert run(repo, "--names", "Ambush Aura", "--exclude-names", "Ambush Aura", "--write").returncode == 2
    assert run(repo, "--names", "Scout Aura", "--exclude-names", "Ambush Aura", "--write").returncode == 0
    debt = json.loads((repo / "test/fixtures/rules_registry_open.json").read_text())
    assert "Ambush Aura" in debt
    assert "Scout Aura" not in debt
