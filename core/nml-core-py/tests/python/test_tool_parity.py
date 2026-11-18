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
  * the knob set the driver plays at agrees with `selfplay.TRAINER_KNOBS`.
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
    for seed in SEEDS:
        ref = _ref(seed)
        (tmp_path / ("core_s%d.json" % seed)).write_text(json.dumps(ref))
        (tmp_path / ("acts_%d" % seed)).mkdir()
        (tmp_path / ("acts_%d" % seed) / "acts.jsonl").write_text(_acts(ref))
    return tmp_path


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
    assert code == 2 and "1 of 2 requested seeds have no reference" in summary["refused"]
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


def test_the_cli_refuses_an_empty_directory_before_loading_the_core_and_writes_the_summary(tmp_path, monkeypatch):
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


def test_the_knob_set_the_driver_plays_at_agrees_with_the_trainer_knobs():
    """The plan says "at TRAINER_KNOBS"; the driver splats LEGACY_FIDELITY_KNOBS (the play_game
    kwargs both older gates use). Every knob the two share must say the same thing."""
    as_trainer = {"charge_gate": False}                        # the play_game string "off" is the trainer's False
    shared = set(sp.LEGACY_FIDELITY_KNOBS) & set(sp.TRAINER_KNOBS)
    assert {"hero_last", "cast_fold", "cond_ap_dice", "versatile_reach", "rules_epoch", "melee_reach",
            "charge_gate"} <= shared
    for key in shared:
        want = as_trainer.get(key, sp.LEGACY_FIDELITY_KNOBS[key])
        assert sp.TRAINER_KNOBS[key] == want, key
