"""`teacher_record --cand-knobs / --cand-preset` (freeze2 SPEC_cand_knobs.md, 07.10.2026): "Erlkoenig + one knob bundle vs Erlkoenig",
mirrored. The knobs ride `play_game(knob_override_player=<the row's seat>, knob_overrides=<bundle>)` on the candidate seat only; the
incumbent seat keeps the frozen `--knobs` grade; both seats keep the net. Proofs:

  * the plumbing: a cand bundle reaches the game call for the ROW'S seat only (seat 1 and seat 2 rows = the mirror), and without
    the flag the game call carries exactly the old keys (nothing new);
  * `--cand-preset NAME` resolves `selfplay.KNOB_PRESETS` (`afpoints_p1`), `--cand-knobs` takes an inline object or a file, the
    preset is overridden key by key, an unknown preset and a non-`I` arm are refused (a tree arm's deep core would be replaced);
  * a grade knob (`top_k`) in the bundle reaches the seat core (the search pool of T1);
  * with the private fixtures: the rows say which seat had what (`cand_seat`, `cand_knobs_sha256`; the per-seat header shas differ);
    without the flag the row's teacher block keeps its old keys.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

pytest.importorskip("onnxruntime")
import nml_core  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(REPO / "tools"))
import lab2_tree_probe as lab  # noqa: E402
import selfplay as sp  # noqa: E402
import teacher_record as tr  # noqa: E402

BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1, ARMY2 = LISTS / "robot_legions_1000.json", LISTS / "blessed_sisters_1000.json"
needs_lists = pytest.mark.skipif(not (BANK.is_dir() and ARMY1.exists() and ARMY2.exists()),
                                 reason="private fixtures (terrain bank + lists) not on this box")
CAND = {"menu_all_targets": 3, "menu_advance_obj_shoot": True}


def i_rows():
    block = {"block": "B", "cell": "c1", "mission": "duel", "army1": str(ARMY1), "army2": str(ARMY2),
             "seeds": {"terrain": "27", "layout": "91002", "deploy": "91003", "play_general": ["91004", "91005"],
                       "tray": ["91006", "91007"], "search": {}}}
    return lab.game_rows([block], ("I",))


def cfg(out, **over):
    c = {"repo": str(REPO), "bank": str(BANK), "out": str(out), "knobs": {"top_k": 2, "horizon": 1}, "budget": 0, "pair": (2, 1),
         "allowance": 0, "prereg": "test", "net_cand": "", "net_inc": ""}
    c.update(over)
    return c


def captured_play(monkeypatch, w, row):
    seen = {}

    def fake(nm, spm, r, repo, bank, knobs, net, allowance, ctx):
        seen.update(knobs)
        return {"valid": False, "reason": "probe", "winner": None}

    monkeypatch.setattr(lab, "play_row", fake)
    tr.play(w, row, record=False)
    return seen


@pytest.mark.parametrize("seat", [1, 2])
def test_a_cand_bundle_reaches_the_game_call_for_the_rows_seat_only(monkeypatch, seat):
    w = {"nm": nml_core, "knobs": {"top_k": 10}, "repo": "r", "bank": "b", "allowance": 0, "ctx": {}, "nets": {1: object()},
         "cand_knobs": CAND}
    row = {"seat": seat, "arm": "I", "row_id": "x"}
    seen = captured_play(monkeypatch, w, row)
    assert seen["knob_override_player"] == seat and seen["knob_overrides"] == CAND
    assert seen["top_k"] == 10, "the incumbent grade stays in the shared knobs"


def test_without_the_flag_the_game_call_carries_the_old_keys_only(monkeypatch):
    w = {"nm": nml_core, "knobs": {"top_k": 10}, "repo": "r", "bank": "b", "allowance": 0, "ctx": {}, "nets": {1: object()}}
    seen = captured_play(monkeypatch, w, {"seat": 1, "arm": "I", "row_id": "x"})
    assert seen == {"top_k": 10, "record_cands": False, "sidecars": False}  # sidecars off = the recorder default


def test_mirrored_rows_play_the_same_board_with_the_cand_on_each_seat():
    rows = [r for r in i_rows() if r["d"] == 0]
    assert sorted(r["seat"] for r in rows) == [1, 2]
    assert len({(r["block"], r["seeds"]["terrain"]) for r in rows}) == 1


def test_resolve_cand_preset_inline_file_and_precedence(tmp_path):
    assert sp.KNOB_PRESETS["afpoints_p1"] == {"strength_by_points": True}
    assert tr.resolve_cand("", "afpoints_p1", "I") == {"strength_by_points": True}
    assert tr.resolve_cand('{"top_k": 40}', "", "I") == {"top_k": 40}
    f = tmp_path / "c.json"
    f.write_text(json.dumps({"menu_all_targets": 2}))
    assert tr.resolve_cand(str(f), "", "I") == {"menu_all_targets": 2}
    merged = tr.resolve_cand('{"menu_all_targets": 5}', "menu_open", "I")
    assert merged["menu_all_targets"] == 5 and merged["menu_advance_obj_shoot"] is True
    assert tr.resolve_cand("", "", "L") == {}
    with pytest.raises(SystemExit):
        tr.resolve_cand("", "no_such_preset", "I")
    with pytest.raises(SystemExit):
        tr.resolve_cand('{"top_k": 40}', "", "L")


def test_a_grade_knob_in_the_bundle_reaches_the_seat_core_not_the_base():
    header = {"profiles": {}}
    base = nml_core.load(str(REPO))
    base.set_header({**header, "knobs": {"top_k": 10, "horizon": 3}})
    seat = sp.core_with_knob_overrides(REPO, header, {"top_k": 10, "horizon": 3}, {"top_k": 40})
    assert seat.knobs()["top_k"] == 40 and base.knobs()["top_k"] == 10 and seat.knobs()["horizon"] == 3
    sbp = sp.core_with_knob_overrides(REPO, header, {}, sp.KNOB_PRESETS["afpoints_p1"])
    assert sbp.knobs()["strength_by_points"] is True


@needs_lists
@pytest.mark.parametrize("seat", [1, 2])
def test_rows_record_which_seat_had_which_knobs(tmp_path, seat):
    (tmp_path / "out").mkdir()
    w = tr._init(cfg(tmp_path / "out", cand_knobs=CAND))
    row = [r for r in i_rows() if r["seat"] == seat and r["d"] == 0][0]
    out = tr._work(w, "c", [row])
    assert out[0]["valid"]
    meta = json.load(open(tmp_path / "out" / (row["row_id"] + ".json")))
    t = meta["teacher"]
    assert t["cand_seat"] == seat and t["cand_knobs"] == CAND
    assert t["cand_knobs_sha256"] == tr.lab2_rows.sha_of(CAND)
    # the game's own per-seat stamp: the bundle on the cand seat, nothing extra on the other
    assert t["knobs_by_seat"]["p%d" % seat] == CAND and t["knobs_by_seat"]["p%d" % (3 - seat)] == {}


@needs_lists
def test_without_the_flag_the_teacher_block_keeps_its_old_keys(tmp_path):
    (tmp_path / "out").mkdir()
    w = tr._init(cfg(tmp_path / "out"))
    row = [r for r in i_rows() if r["seat"] == 1 and r["d"] == 1][0]
    tr._work(w, "c", [row])
    t = json.load(open(tmp_path / "out" / (row["row_id"] + ".json")))["teacher"]
    assert set(t) == {"schema", "rows", "tree_rows", "y_cand", "budget", "pair", "nets"}
