"""Expert-iteration step 1 — `trace.cands`, the candidate CONTENT behind an opt-in.

`plan_with_rollout`'s trace always carried the RANK (`trace.scored`: idx, unit,
kind, score) but never the candidate itself — a net could know "a charge was
scored 3rd" yet never "toward WHICH target". Step 1 adds the binding kwarg
`cands` (keyword, default False): when true, `trace.cands` holds one entry per
built candidate, in BUILD index order, each the same `cand_plain` shape
`pick.action` uses. The join rule is `trace.scored[i].idx` ->
`trace.cands[trace.scored[i].idx]` — `scored` rows carry their build-order
`idx` (`prefilter` writes `idx == position`), and `cands` sits exactly on that
index. `selfplay.play_game(..., record_cands=True)` threads the flag through
`_pick_for` and stamps `row["cands"] = {"list": ..., "best": ...}` onto the
planner row, `best` being the argmax's build index
(`trace.scored[trace.best_idx].idx` — at eps=0 the played candidate).

Four proofs:

  * OFF, at the binding: no `trace.cands` key on any act of the in-repo
    corpus `acts_25.jsonl` (the test_parity.py replay convention);
  * ON, at the binding: for every used act, `len(cands) == len(scored)`,
    `scored[i].kind`/`.unit` equal `cands[scored[i].idx]`'s, and
    `pick.action == cands[scored[best_idx].idx]` — the played candidate IS
    the trace's content;
  * OFF, through selfplay: the seed-27 fast game's `result_digest` is pinned
    at the PRE-CHANGE head b532e975 (the test_search_depth.py pattern — any
    default-path change moves it), and no planner row carries the key;
  * ON, through selfplay: every row joins the same way, and stripping the
    new key restores the OFF rows byte for byte — the game itself did not
    move.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
#: the fast trainer's own knobs (`test_explore_knob.py`'s arms) — the only
#: game the pin and the ON arm run, so the corpus stays comparable.
FAST = {"top_k": 2, "horizon": 1}

#: raw `sp.result_digest` of the seed-27 fast game at the PRE-CHANGE head
#: b532e975, built and run through the private-module recipe (maturin build
#: --release into .forge/site). The OFF arm's red-green anchor.
#: Re-pinned after PR #600 (`dangerous_end_morale`, default True) landed and
#: moved this seed's game under `LEGACY_FIDELITY_KNOBS` too — this test is
#: about record_cands, not that knob, so the pin just follows today's other
#: defaults rather than pinning a growing list of unrelated ones.
SEED_27_FAST_DIGEST = "86249fc93149f8d49e74f19fbef634e985f3224710aba39d4248f535f8c94504"


def _read_acts(name: str):
    lines = [json.loads(l) for l in open(FIXTURES / name, encoding="utf-8")]
    return lines[0], lines[1:]


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _join_errors(tr: dict) -> list[str]:
    """The join contract in one walk: `cands` one-per-built in build order,
    every `scored` row's `idx` landing on its own content."""
    bad = []
    scored, cands = tr["scored"], tr["cands"]
    if len(cands) != len(scored):
        bad.append("len(cands) %d != len(scored) %d" % (len(cands), len(scored)))
    for row in scored:
        c = cands[row["idx"]]
        if c["kind"] != row["kind"] or c["unit"] != row["unit"]:
            bad.append("scored[%d].idx: kind %s/unit %s vs row kind %s/unit %s"
                       % (row["idx"], c["kind"], c["unit"], row["kind"], row["unit"]))
    return bad


def test_binding_off_writes_no_cands_key():
    """The default call must write the trace it always wrote — `cands` absent,
    not present-and-empty, so a field-by-field gate sees the same object."""
    header, acts = _read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    used = 0
    for act in acts:
        rec = act["trace"].get("arbitration")
        sig = rec["sig"] if rec else None
        got = core.plan_with_rollout(
            core.state_of(act["state"]), act["player"], act["statics"], sig
        )
        if got["used"]:
            used += 1
            assert "cands" not in got["trace"]
    assert used > 0, "the corpus declined everywhere — the gate proves nothing"


def test_binding_on_joins_scored_to_cands():
    """The opt-in: every built candidate's content, joined by `scored[i].idx`,
    and the played action identical to the argmax's own entry."""
    header, acts = _read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    checked = 0
    for act in acts:
        rec = act["trace"].get("arbitration")
        sig = rec["sig"] if rec else None
        got = core.plan_with_rollout(
            core.state_of(act["state"]), act["player"], act["statics"], sig, cands=True
        )
        if not got["used"]:
            continue
        checked += 1
        tr = got["trace"]
        bad = _join_errors(tr)
        assert not bad, "act seq %d: %s" % (act.get("seq", "?"), "; ".join(bad))
        assert got["action"] == tr["cands"][tr["scored"][tr["best_idx"]]["idx"]], (
            "act seq %s: the played action is not the argmax's cands entry"
            % act.get("seq", "?")
        )
    assert checked > 0, "the corpus declined everywhere — the gate proves nothing"


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_selfplay_off_rows_are_untouched():
    """Default `play_game` plays the pinned pre-change game and stamps no
    `cands` key on any planner row — the byte-identity arm."""
    # W5a: pinned to the legacy fidelity knobs — this test is about
    # record_cands, not the shipped-defaults flip, so it keeps the ORIGINAL
    # vintage pin instead of moving it for an unrelated reason.
    core = nml_core.load(str(REPO))
    res = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core,
                       **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(res) == SEED_27_FAST_DIGEST
    assert all("cands" not in row for row in res["planner_positions"])


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_selfplay_on_records_the_menu_and_moves_nothing():
    """`record_cands=True` puts the menu + the argmax's build index on every
    row — `action == list[best]` per row — and changes NOTHING else: stripping
    the key restores the OFF game's rows byte for byte."""
    core = nml_core.load(str(REPO))
    off = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    on = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, record_cands=True, **FAST)
    rows = on["planner_positions"]
    assert len(rows) == len(off["planner_positions"]) > 0
    assert all("cands" in row for row in rows)
    stripped = [{k: v for k, v in row.items() if k != "cands"} for row in rows]
    assert stripped == off["planner_positions"], "record_cands moved the game"
    for row in rows:
        cands = row["cands"]
        assert len(cands["list"]) > 0
        assert row["action"] == cands["list"][cands["best"]], (
            "row seq %d: the recorded action is not the entry `best` points at" % row["seq"]
        )
