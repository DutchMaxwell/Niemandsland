"""PLAN G step 2 — the parity driver's own instrument check (`tools/tool_parity.py`).

No Godot and no game: a SYNTHETIC oracle directory (`core_s<seed>.json` + `acts_<seed>/acts.jsonl`,
the shape `tools/core_selfplay.gd` writes) and an injected `play(seed)` that answers with the harness's
own result shape. What is pinned:

  * the identical pair is GREEN (exit 0, every seed and row counted) — otherwise every red below is noise;
  * ONE changed int is RED (exit 1) and is named with seed, gate, path, ref and got;
  * a change only one gate reads shows up under THAT gate (a board cell: sidecar; the pick: selfplay);
  * an empty directory, a seed without its acts corpus and a half-recorded range are REFUSED (exit 2),
    never skipped and never green, and no game is played for them;
  * the CLI refuses an empty directory (exit 2) before it loads the core, and still writes the summary;
  * the knob set the driver plays at (`LEGACY_FIDELITY_KNOBS`, epoch 0 pre-fidelity) agrees with the old tool's
    header (`selfplay.TRAINER_KNOBS`) on the shared keys.

Step 3 (`--accept`, `--plant`), through `main` with the game and the core stubbed:

  * a difference an accept entry names (same gate, `path_regex` FULL match) is `accepted` and the run is green;
    one it does not name is unexplained and red; an entry that matched nothing is `stale accept` and red;
  * `--plant` corrupts a COPY of the first seed (never the oracle), the planted run must turn red through BOTH gates,
    and an instrument that cannot see it exits 3 ("blind"); a refused run plants nothing.

Step 2b (core identity guard and summary provenance):

  * a dirty `nml_core` (`BUILD_DIRTY=True`) or commit mismatch (`BUILD_COMMIT != HEAD`) is refused with exit 2
    before loading the core or playing; `--allow-core-mismatch` overrides it, records the override in the summary,
    and prints it on the `PARITY:` line;
  * the summary carries `config`, `rules_epoch` (0 for the legacy config), and `knobs_played`.
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import selfplay as sp  # noqa: E402
import tool_parity as tp  # noqa: E402

SEEDS = [1, 2]


def _ref(seed: int) -> dict:
    """What the Godot tool writes: no `rounds_played`, no per-row `unit`/`kind`/`action`."""
    rows = [
        {"round": r, "side": s, "board": [[1, 0.5, 0.25, 3, 4, 5, 6, 7, 8, 9, 4, 4, 1.5, 2.5]],
         "ids": [7, 8], "features": [0.1, 0.2], "value": 0.5, "intent": "hold"}
        for r, s in ((1, 1), (1, 2), (2, 1))
    ]
    return {"tool": "core_selfplay", "seed": seed, "winner": 1,
            "objectives": {"p1": 1, "p2": 0, "neutral": 0}, "vp": {"p1": 5, "p2": 3},
            "planner_positions": rows}


def _acts(ref: dict) -> str:
    lines = [{"kind": "header", "knobs": {}}]
    lines += [{"kind": "act", "round": r["round"], "player": r["side"],
               "pick": {"unit_key": "u%d" % r["side"], "action": {"kind": "move"}}}
              for r in ref["planner_positions"]]
    return "".join(json.dumps(ln) + "\n" for ln in lines)


def _got(ref: dict) -> dict:
    """The Python harness's result for the same game: the ref plus its own extras."""
    got = copy.deepcopy(ref)
    got["tool"] = "core_selfplay_py"
    got["rounds_played"] = len({r["round"] for r in ref["planner_positions"]})
    for r in got["planner_positions"]:
        r.update(unit="u%d" % r["side"], kind="move", action={"kind": "move"})
    return got


@pytest.fixture
def oracle(tmp_path):
    root = tmp_path / "oracle"
    for seed in SEEDS:
        ref = _ref(seed)
        (root / ("acts_%d" % seed)).mkdir(parents=True)
        (root / ("core_s%d.json" % seed)).write_text(json.dumps(ref))
        (root / ("acts_%d" % seed) / "acts.jsonl").write_text(_acts(ref))
    return root


def _play_equal(seed: int) -> dict:
    return _got(_ref(seed))


def _judge(oracle, play=_play_equal, seeds=SEEDS):
    played: list[int] = []

    def make_play():
        return lambda seed: (played.append(seed), play(seed))[1]

    summary = tp.run_parity(oracle, seeds, make_play, log=lambda *_: None)
    return tp.exit_code(summary), summary, played


def test_the_identical_pair_is_green_and_every_seed_and_row_is_counted(oracle):
    code, summary, played = _judge(oracle)
    assert code == 0
    assert (summary["seeds_requested"], summary["seeds_compared"], summary["rows_compared"]) == (2, 2, 6)
    assert summary["diffs"] == [] and summary["missing"] == [] and summary["refused"] is None
    assert played == SEEDS


def test_one_changed_int_is_red_and_named(oracle):
    def play(seed):
        got = _got(_ref(seed))
        if seed == 2:
            got["vp"]["p1"] += 1
        return got

    code, summary, _ = _judge(oracle, play)
    assert code == 1
    assert summary["seeds_compared"] == 2
    hit = [d for d in summary["diffs"] if d["seed"] == 2 and d["gate"] == "selfplay"]
    assert hit == [{"seed": 2, "gate": "selfplay", "path": "vp", "ref": {"p1": 5, "p2": 3}, "got": {"p1": 6, "p2": 3}}]
    assert all(d["seed"] == 2 for d in summary["diffs"])      # seed 1 stays clean


def test_a_board_cell_is_a_sidecar_difference_only_and_a_pick_a_selfplay_one_only(oracle):
    def board(seed):
        got = _got(_ref(seed))
        got["planner_positions"][1]["board"][0][3] += 1
        return got

    _, summary, _ = _judge(oracle, board, seeds=[1])
    assert [(d["gate"], d["path"], d["ref"], d["got"]) for d in summary["diffs"]] == [("sidecar", "row[1].board[0][3]", 3, 4)]

    def pick(seed):
        got = _got(_ref(seed))
        got["planner_positions"][0]["unit"] = "u9"
        return got

    _, summary, _ = _judge(oracle, pick, seeds=[1])
    assert [(d["gate"], d["path"]) for d in summary["diffs"]] == [("selfplay", "pick#0")]


def test_an_empty_directory_is_refused_with_exit_2_and_plays_nothing(tmp_path):
    code, summary, played = _judge(tmp_path)
    assert code == 2 and summary["refused"] == "compared 0 seeds"
    assert summary["seeds_compared"] == 0 and played == []
    assert summary["missing"] == SEEDS


def test_an_empty_seed_list_compares_nothing_and_is_refused(oracle):
    code, summary, played = _judge(oracle, seeds=[])
    assert code == 2 and summary["refused"] == "compared 0 seeds" and played == []


def test_a_seed_without_its_acts_corpus_is_refused_not_skipped(oracle):
    (oracle / "acts_2" / "acts.jsonl").unlink()
    code, summary, played = _judge(oracle)
    assert code == 2 and "seeds [2] have no reference" in summary["refused"]
    assert summary["missing"] == [2]
    assert played == []                                        # the comparison is invalid; no game is wasted on it


def test_a_half_recorded_range_is_refused_and_a_core_file_without_rows_counts_as_missing(oracle):
    code, summary, _ = _judge(oracle, seeds=[1, 2, 3])
    assert code == 2 and summary["missing"] == [3]
    (oracle / "core_s1.json").write_text(json.dumps({"winner": 1}))
    code, summary, _ = _judge(oracle, seeds=[1])
    assert code == 2 and summary["missing"] == [1] and summary["refused"] == "compared 0 seeds"
    (oracle / "core_s1.json").write_text("{not json")
    assert _judge(oracle, seeds=[1])[1]["missing"] == [1]


def _match_core(monkeypatch, sha: str = "deadbeef") -> str:
    monkeypatch.setattr(tp, "_repo_head", lambda *_: sha)
    monkeypatch.setattr(tp.nml_core, "BUILD_COMMIT", sha)
    monkeypatch.setattr(tp.nml_core, "BUILD_DIRTY", False)
    return sha


def test_the_cli_refuses_an_empty_directory_before_loading_the_core_and_writes_the_summary(tmp_path, monkeypatch):
    _match_core(monkeypatch)
    monkeypatch.setattr(tp.nml_core, "load", lambda *_: pytest.fail("a refused run must not load the core"))
    out = tmp_path / "parity_summary.json"
    empty = tmp_path / "empty"
    empty.mkdir()
    code = tp.main(["--ref", str(empty), "--bank", str(tmp_path), "--army1", "a", "--army2", "b",
                    "--seeds", "27-29", "--repo", str(tmp_path), "--out", str(out)])
    assert code == 2
    summary = json.loads(out.read_text())
    assert summary["refused"] == "compared 0 seeds" and summary["seeds_compared"] == 0
    assert summary["missing"] == [27, 28, 29] and summary["core_commit"] == tp.nml_core.BUILD_COMMIT


def test_the_knob_set_the_driver_plays_at_agrees_with_the_old_tools_header_on_the_shared_keys():
    """`LEGACY_FIDELITY_KNOBS` is epoch 0, pre-fidelity (the old tool's game, not the trainer's).
    Every knob it shares with `TRAINER_KNOBS` (the old tool's header defaults) must say the same thing."""
    as_trainer = {"charge_gate": False}                        # the play_game string "off" is the old tool's False
    shared = set(sp.LEGACY_FIDELITY_KNOBS) & set(sp.TRAINER_KNOBS)
    assert {"hero_last", "cast_fold", "cond_ap_dice", "versatile_reach", "rules_epoch", "melee_reach",
            "charge_gate"} <= shared
    for key in shared:
        want = as_trainer.get(key, sp.LEGACY_FIDELITY_KNOBS[key])
        assert sp.TRAINER_KNOBS[key] == want, key


@pytest.fixture
def cli(monkeypatch, oracle, tmp_path):
    """`main` end to end without a game: the core load and `play_game` are stubbed, the planted copy goes to tmp."""
    _match_core(monkeypatch)
    monkeypatch.setattr(tp.nml_core, "load", lambda *_: object())
    monkeypatch.setattr(tp.list_to_profile, "LEGACY_CORE_SELFPLAY", False)
    monkeypatch.setattr(tp, "PLANT_DIR", tmp_path / "plant")
    holder = {"play": _play_equal}
    monkeypatch.setattr(tp.sp, "play_game", lambda seed, *a, **k: holder["play"](seed))

    def run(*extra, play=_play_equal, ref=oracle):
        holder["play"] = play
        out = tmp_path / "summary.json"
        code = tp.main(["--ref", str(ref), "--bank", "b", "--army1", "a", "--army2", "b", "--seeds", "1-2",
                        "--repo", str(tmp_path), "--out", str(out), *extra])
        return code, json.loads(out.read_text())

    return run


def _vp_off_by_one(seed):
    got = _got(_ref(seed))
    got["vp"]["p1"] += 1          # the selfplay gate calls this `vp`, the sidecar gate `vp.p1`
    return got


def _accept_file(tmp_path, *entries):
    (tmp_path / "accept.json").write_text(json.dumps([
        {"gate": g, "path_regex": rx, "reason": "test", "epoch": 71, "pr": 0} for g, rx in entries]))
    return str(tmp_path / "accept.json")


def test_a_difference_an_accept_entry_names_is_accepted_and_the_run_is_green(cli, tmp_path):
    accept = _accept_file(tmp_path, ("selfplay", "vp"), ("sidecar", r"vp\.p1"))
    code, summary = cli("--accept", accept, play=_vp_off_by_one)
    assert code == 0 and len(summary["diffs"]) == 4 and all(d["accepted"] for d in summary["diffs"])
    assert summary["stale_accepts"] == []


def test_a_difference_no_entry_names_is_unexplained_and_red(cli, tmp_path, capsys):
    code, summary = cli("--accept", _accept_file(tmp_path, ("selfplay", "vp")), play=_vp_off_by_one)
    assert code == 1 and [d["gate"] for d in summary["diffs"] if not d["accepted"]] == ["sidecar", "sidecar"]
    assert "4 differences (2 unexplained)" in capsys.readouterr().out
    # the gate must match and the path must match IN FULL: neither a prefix nor the other gate's name counts
    code, summary = cli("--accept", _accept_file(tmp_path, ("sidecar", "vp"), ("selfplay", "v")), play=_vp_off_by_one)
    assert code == 1 and not any(d["accepted"] for d in summary["diffs"])


def test_a_stale_accept_entry_fails_an_otherwise_equal_run(cli, tmp_path, capsys):
    code, summary = cli("--accept", _accept_file(tmp_path, ("selfplay", "vp")))
    assert code == 1 and summary["diffs"] == [] and [e["path_regex"] for e in summary["stale_accepts"]] == ["vp"]
    assert "stale accept" in capsys.readouterr().out
    assert cli()[0] == 0                                         # without the allowance the same run is green


def test_the_plant_corrupts_a_copy_and_the_planted_run_is_red_through_both_gates(oracle, tmp_path):
    before = {str(p): p.read_bytes() for p in oracle.rglob("*") if p.is_file()}
    dest = tp.plant(oracle, 1, tmp_path / "plant")
    assert {str(p): p.read_bytes() for p in oracle.rglob("*") if p.is_file()} == before     # the oracle is untouched
    ref, planted = _ref(1), json.loads((dest / "core_s1.json").read_text())
    assert planted["planner_positions"][0]["board"][0][3] == ref["planner_positions"][0]["board"][0][3] + 1
    assert planted["planner_positions"][1:] == ref["planner_positions"][1:]
    orig, swapped = _acts(ref).splitlines(), (dest / "acts_1" / "acts.jsonl").read_text().splitlines()
    assert swapped[1:3] == [orig[2], orig[1]] and swapped[0] == orig[0] and swapped[3:] == orig[3:]
    summary = tp.run_parity(dest, [1], lambda: _play_equal, log=lambda *_: None)
    assert tp.exit_code(summary) == 1 and {d["gate"] for d in summary["diffs"]} == {"selfplay", "sidecar"}


def test_plant_on_an_equal_pair_reports_the_planted_run_red_and_the_run_stays_green(cli, capsys):
    code, summary = cli("--plant")
    assert code == 0 and summary["plant_exit"] == 1 and summary["diffs"] == []
    assert "red, as it must be" in capsys.readouterr().out


def test_an_instrument_blind_to_the_plant_exits_3(cli, monkeypatch, capsys):
    monkeypatch.setattr(tp, "compare_seed", lambda *_: [])       # a gate that sees nothing
    code, summary = cli("--plant")
    assert code == 3 and summary["plant_exit"] == 0
    assert "instrument blind" in capsys.readouterr().out
    assert cli()[0] == 0                                          # blind AND green: only --plant tells them apart


def test_a_refused_run_plants_nothing(cli, tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    code, summary = cli("--plant", ref=empty)
    assert code == 2 and "plant_exit" not in summary and not (tmp_path / "plant").exists()


def test_a_dirty_core_is_refused_with_exit_2_before_loading_or_playing(cli, monkeypatch, capsys):
    monkeypatch.setattr(tp.nml_core, "BUILD_DIRTY", True)
    monkeypatch.setattr(tp.nml_core, "load", lambda *_: pytest.fail("a refused run must not load the core"))
    code, summary = cli(play=lambda *_: pytest.fail("a refused run must not play"))
    assert code == 2 and summary["seeds_compared"] == 0
    assert summary["core_dirty"] is True and summary["allow_core_mismatch"] is False
    assert "core mismatch" in summary["refused"] and "BUILD_DIRTY" in summary["refused"]
    assert "REFUSED: core mismatch" in capsys.readouterr().out


def test_a_commit_mismatch_is_refused_with_exit_2_before_loading_or_playing(cli, monkeypatch, capsys):
    monkeypatch.setattr(tp.nml_core, "BUILD_COMMIT", "00000000")
    monkeypatch.setattr(tp.nml_core, "load", lambda *_: pytest.fail("a refused run must not load the core"))
    code, summary = cli(play=lambda *_: pytest.fail("a refused run must not play"))
    assert code == 2 and summary["seeds_compared"] == 0
    assert summary["core_commit"] == "00000000" and summary["sha"] == "deadbeef"
    assert summary["allow_core_mismatch"] is False
    assert "core mismatch" in summary["refused"] and "00000000" in summary["refused"]
    assert "REFUSED: core mismatch" in capsys.readouterr().out


def test_allow_core_mismatch_overrides_refusal_and_records_it(cli, monkeypatch, capsys):
    monkeypatch.setattr(tp.nml_core, "BUILD_DIRTY", True)
    monkeypatch.setattr(tp.nml_core, "BUILD_COMMIT", "00000000")
    code, summary = cli("--allow-core-mismatch")
    assert code == 0 and summary["refused"] is None and summary["seeds_compared"] == 2
    assert summary["allow_core_mismatch"] is True and summary["core_dirty"] is True
    assert summary["core_commit"] == "00000000" and summary["sha"] == "deadbeef"
    out = capsys.readouterr().out
    assert "PARITY:" in out and "--allow-core-mismatch" in out


def test_summary_carries_config_rules_epoch_0_and_knobs_played_for_the_legacy_config(cli):
    code, summary = cli()
    assert code == 0
    assert summary["config"] == "legacy" and summary["rules_epoch"] == 0
    assert summary["knobs_played"]["rules_epoch"] == 0
    assert sp.LEGACY_FIDELITY_KNOBS.items() <= summary["knobs_played"].items()
    assert summary["allow_core_mismatch"] is False
