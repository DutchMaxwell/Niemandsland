"""Build provenance and CLI compatibility gates; no private corpus required."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import nml_core
import pytest

ROOT = Path(__file__).resolve().parents[4]
TOOLS = ROOT / "core/nml-core-py/tools"
sys.path.insert(0, str(TOOLS))
import gen0_replay_one as gr
import selfplay as sp


@pytest.fixture
def tiny_record(tmp_path):
    army = tmp_path / "test_100.json"
    army.write_text(json.dumps({"gameSystem": "gf", "units": [{
        "id": "unit", "selectionId": "unit", "name": "Test unit",
        "quality": 4, "defense": 4, "size": 1, "rules": [],
        "weapons": [{"name": "Rifle", "range": 24, "attacks": 1, "count": 1}],
        "selectedUpgrades": [],
    }]}))
    terrain = {"cells": [], "sandbox": [], "walls": [], "cell_params": {
        "table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0,
        "grid_size_inches": 6.0, "inches_to_meters": sp.IN2M,
    }}
    (tmp_path / "board_17.json").write_text(json.dumps({"terrain": terrain, "pieces": []}))
    return tmp_path, army


def play(tiny_record, record_cands):
    bank, army = tiny_record
    gr.G["dice"] = 23
    with gr.armed(sp._pick_for):
        return sp.play_game(17, army, army, ROOT, bank, top_k=1, horizon=1,
                            dice_seed=23, record_cands=record_cands,
                            movement="rigid", **gr.KNOBS)


def test_module_exports_build_identity():
    assert re.fullmatch(r"[0-9a-fA-F]{40}|unknown", nml_core.BUILD_COMMIT)
    assert isinstance(nml_core.BUILD_DIRTY, bool)
    info = nml_core.BUILD_INFO
    assert info["commit"] == nml_core.BUILD_COMMIT
    assert info["dirty"] == nml_core.BUILD_DIRTY
    assert info["rules_epoch"] == nml_core.CURRENT_RULES_EPOCH
    assert info["crate_version"] == "0.1.0"
    assert datetime.fromisoformat(info["build_time_utc"].replace("Z", "+00:00")).utcoffset().total_seconds() == 0


@pytest.mark.parametrize("record_cands", [False, True])
def test_every_fresh_record_stamps_the_build(tiny_record, record_cands):
    rec = play(tiny_record, record_cands)
    assert rec["prescreen"]["core_commit"] == nml_core.BUILD_COMMIT
    assert rec["prescreen"]["core_build"] == nml_core.BUILD_INFO
    assert rec["prescreen"]["core_build"]["rules_epoch"] == nml_core.CURRENT_RULES_EPOCH
    if record_cands:
        assert rec["core_commit"] == rec["prescreen"]["core_commit"]


def run_tool(tool, bank, *args, strict_env=False):
    # Keep the real CLI and real core; only point the terrain bank at the tiny fixture.
    module = "gen0_replay_one" if tool == "one" else "gen0_replay_shards"
    code = ("import sys; sys.path.insert(0, %r); import gen0_replay_one as gr; "
            "gr.BANK = %r; import %s as tool; sys.exit(tool.main())"
            % (str(TOOLS), str(bank), module))
    env = dict(os.environ)
    env.pop("NML_REQUIRE_SAME_CORE", None)
    if strict_env:
        env["NML_REQUIRE_SAME_CORE"] = "1"
    return subprocess.run([sys.executable, "-c", code, *map(str, args)],
                          text=True, capture_output=True, env=env, timeout=60)


@pytest.mark.parametrize("stamp", ["different", "matching", "missing"])
@pytest.mark.parametrize("strict", ["off", "flag", "env"])
@pytest.mark.parametrize("tool", ["one", "shards"])
def test_replay_cli_core_gate(tiny_record, stamp, strict, tool):
    bank, _ = tiny_record
    rec = play(tiny_record, True)
    rec.setdefault("prescreen", {})["knobs"] = dict(gr.KNOBS, movement="rigid", record_cands=True)
    running = getattr(nml_core, "BUILD_COMMIT", "a" * 40)
    recorded = ("b" if running != "b" * 40 else "c") * 40
    if stamp != "missing":
        rec["prescreen"]["core_commit"] = running if stamp == "matching" else recorded
    else:
        rec["prescreen"].pop("core_commit", None)
    path = bank / "gen0_s17_d23.json"
    path.write_text(json.dumps(rec))
    args = [path, path] if tool == "one" else [bank, "--out", bank / "shards", "--workers", "1"]
    args += ["--lists", bank]
    if strict == "flag":
        args += ["--require-same-core"]
    result = run_tool(tool, bank, *args, strict_env=strict == "env")
    output = result.stdout + result.stderr
    refused = strict != "off" and stamp != "matching"
    assert result.returncode == (3 if refused else 0), output
    if stamp != "matching":
        assert str(path) in output
        assert running in output
        assert (recorded if stamp == "different" else "unknown") in output
        assert ("REFUSED" if refused else "WARN") in output
        if not refused:
            assert output.count("WARN") == 1
    if not refused:
        assert "core_commit=" + running in output


def test_build_identity_precedes_runtime_git(monkeypatch):
    monkeypatch.setattr(nml_core, "BUILD_COMMIT", "a" * 40, raising=False)
    def must_not_run():
        pytest.fail("runtime git was consulted despite a build identity")
    monkeypatch.setattr(sp, "_git_full_sha", must_not_run, raising=False)
    assert sp._record_core_commit() == "a" * 40


def test_unknown_build_falls_back_without_blocking(monkeypatch):
    monkeypatch.setattr(nml_core, "BUILD_COMMIT", "unknown", raising=False)
    monkeypatch.setattr(sp, "_git_full_sha", lambda: "c" * 40, raising=False)
    assert sp._record_core_commit() == "c" * 40
    monkeypatch.setattr(sp, "_git_full_sha", lambda: "unknown")
    assert sp._record_core_commit() == "unknown"


def test_build_metadata_does_not_change_gameplay_digest():
    original = {"winner": "draw", "planner_positions": []}
    stamped = dict(original, prescreen={"core_commit": "a" * 40, "core_build": {"dirty": False}})
    assert sp.result_digest(stamped) == sp.result_digest(original)
    # Other prescreen fields still contribute; do not exclude the whole object.
    stamped["prescreen"]["rules_epoch"] = 5
    assert sp.result_digest(stamped) != sp.result_digest(original)
    held = dict(original, prescreen={"rules_epoch": 5})
    assert sp.result_digest(stamped) == sp.result_digest(held)
    assert "core_build" in stamped["prescreen"], "digest must not mutate the record"


def test_build_metadata_does_not_mask_or_break_sidecar_comparison():
    import sidecar_gate
    original = {"winner": "draw", "planner_positions": []}
    stamped = dict(original, prescreen={"core_commit": "a" * 40, "core_build": {"dirty": False}})
    assert sidecar_gate.compare(original, stamped, 0.0001) == []
    stamped["winner"] = "p1"
    assert sidecar_gate.compare(original, stamped, 0.0001)
    stamped["winner"] = "draw"
    stamped["prescreen"]["rules_epoch"] = 5
    assert sidecar_gate.compare(original, stamped, 0.0001)


def test_narrator_accepts_a_metadata_only_prescreen(tiny_record):
    import game_narrator
    bank, _ = tiny_record
    record = play(tiny_record, False)
    path = bank / "game.json"
    path.write_text(json.dumps(record))
    replayed, acts = game_narrator.replay(str(path), str(bank), str(ROOT), str(bank))
    assert len(acts) == len(record["planner_positions"]) > 0
    assert replayed["prescreen"] == record["prescreen"]


@pytest.mark.parametrize("module,seat_flag", [("search_ab_one", "--deep-player"), ("eval_ab_one", "--cand-player")])
def test_ab_writers_preserve_build_metadata(tmp_path, monkeypatch, module, seat_flag):
    import importlib
    tool = importlib.import_module(module)
    stamp = {"core_commit": nml_core.BUILD_COMMIT, "core_build": dict(nml_core.BUILD_INFO)}
    monkeypatch.setattr(sp, "play_game", lambda *a, **kw: {"winner": "draw", "prescreen": dict(stamp)})
    monkeypatch.setattr(sys, "argv", [module, str(tmp_path), "--seed", "17", "--dice-seed", "23",
                                      "--army1", "a.json", "--army2", "b.json", seat_flag, "1"])
    assert tool.main() == 0
    record = json.loads(next(tmp_path.glob("*.json")).read_text())
    for key, value in stamp.items():
        assert record["prescreen"][key] == value
