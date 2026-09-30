"""NML-1010 W2 (missions R1) — the `mission` knob on `play_game`.

`mission="duel"` (the default) must reproduce today's game byte-for-byte:
`assets/solo/missions.json` is loaded but every optional state key it could
add (`vp`/`vp_flavour`/`vp_memo`/`markers_meta`/`destroy_seq`) stays absent,
so `result_digest` does not move and no `mission` key rides `knobs`. A
`round_vp` mission (`domination`, majority booked EVERY round) must NOT: its
round-1 `vp` line differs from duel's, and the id is stamped in both
`result["mission"]["name"]` and `result["knobs"]["mission"]`.

RED (manual, not a standing test): comment out the `if eff_scoring ==
"round_vp":` branch in `selfplay.py`'s round loop (falling through to the
`elif eff_scoring == "end":` arm, i.e. today's unconditional `vp_round_add`)
— `test_domination_differs_from_duel_at_round_one` fails, because
`mission="domination"` would then book VP exactly like duel.
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
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
#: the fast trainer's own knobs (`mass_fast.FIDELITY_DEFAULTS`), so the only
#: free variable across every call below is `mission`.
FAST = {"top_k": 2, "horizon": 1}
SEED = 27


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


needs_lists = pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")


def _play(mission: str, core) -> dict:
    return sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission=mission, **FAST)


@needs_lists
def test_duel_default_is_byte_identical_to_no_mission_kwarg():
    core = nml_core.load(str(REPO))
    base = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    explicit = _play("duel", core)
    assert sp.result_digest(base) == sp.result_digest(explicit)
    assert "mission" not in base["knobs"]
    assert base["scoring"] == "end"


@needs_lists
def test_domination_differs_from_duel_at_round_one_and_stamps_the_id():
    core = nml_core.load(str(REPO))
    duel = _play("duel", core)
    dom = _play("domination", core)
    assert dom["rounds_log"][0]["vp"] != duel["rounds_log"][0]["vp"]
    assert dom["mission"]["name"] == "domination"
    assert dom["knobs"]["mission"] == "domination"
    assert dom["scoring"] == "round_vp"


@needs_lists
def test_unknown_mission_id_raises():
    core = nml_core.load(str(REPO))
    with pytest.raises(ValueError):
        _play("not_a_mission", core)


def test_inline_carry_marker_spec_arms_unowned_relics_only_when_requested():
    assert sp.mission_markers({"carry": True}, 3) == [
        {"carry": True, "carried_by": -1} for _ in range(3)
    ]
    assert sp.mission_markers({}, 3) == []
    assert sp.mission_markers({"owned": True, "destructible": True}, 2) == [
        {"owned_by": 1, "destructible": True},
        {"owned_by": 2, "destructible": True},
    ]


# --- wave C gate C9.4: a replay inherits the recorded game's round-end referee ---

FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"


def _replay_held(monkeypatch, **mission):
    """`play_from_state` on acts_25's first recorded board with every activation stubbed
    out, so the board stands still and only the round-end referee moves the ledger. Every
    unit is parked apart; p1's first unit sits on the one marker, p2's first stands 0.3 m
    off (outside the 3" ring). `mission` = the keys a table capture writes."""
    lines = (FIXTURES / "acts_25.jsonl").read_text().splitlines()
    header, plain = json.loads(lines[0]), json.loads(lines[1])["state"]
    core = nml_core.load(str(REPO))
    core.set_header(header)
    first = {}
    for i, (key, unit) in enumerate(plain["units"].items()):
        first.setdefault(unit["player"], (i, key))
        unit.update(alive=1, positions=[[2.0 + i, 0, 2.0 + i]], radii=[0.02], wounds=[1],
                    shaken=False, aircraft=False, ambush_arrived_round=0)
    plain["units"][first[1][1]]["positions"] = [[0.04, 0, 0]]
    plain["units"][first[2][1]]["positions"] = [[0.3, 0, 0]]
    plain["objectives"] = [{"pos": [0, 0, 0], "owner": 0}]
    plain.update(mission)
    monkeypatch.setattr(sp, "_play_round", lambda core, state, opener, *a, **k: (state, opener))
    return sp.play_from_state(core, plain, header["profiles"], 1, nml_core.Rng(27)), first[1][0]


def test_play_from_state_scores_a_recorded_round_vp_mission_by_its_flavour(monkeypatch):
    """A Domination-style board (majority paid EVERY round): p1 holds the one marker all
    game, so each round pays 1 for the marker + 1 for the majority. The old replay loop
    booked the end-scored duel ledger instead ([1, 0] after round 1, [5, 0] at the end)."""
    res, _ = _replay_held(monkeypatch, scoring="round_vp", vp=[0, 0],
                          vp_flavour={"majority": "round"}, vp_memo={})
    assert [e["vp"] for e in res["rounds_log"]] == [[2, 0], [4, 0], [6, 0], [8, 0]]
    assert res["vp"] == {"p1": 8, "p2": 0}
    assert res["winner"] == "p1"


def test_play_from_state_carries_a_recorded_relic_in_the_tables_spelling(monkeypatch):
    """The table writes the carrier as its unit KEY, "" for none (C9.3 reads it). The
    replay's round-end referee picks the relic up onto p1's unit standing on it."""
    res, carrier = _replay_held(monkeypatch, markers_meta=[{"carry": True, "carried_by": ""}],
                                destroy_seq=[0])
    assert res["markers_meta"][0]["carried_by"] == carrier
    assert res["objectives"] == {"p1": 1, "p2": 0, "neutral": 0}


def test_carry_catalog_entries_pin_three_relics_and_scoring():
    relic = sp.resolve_mission("relic_hunt", REPO)
    hold = sp.resolve_mission("capture_and_hold", REPO)
    assert relic["name"] == "Relic Hunt" and relic["scoring"] == "end"
    assert hold["name"] == "Capture & Hold" and hold["scoring"] == "round_vp"
    assert hold["vp"]["majority"] == "end"
    for mission in (relic, hold):
        assert mission["markers"]["count"] == 3
        assert mission["markers"]["carry"] is True
        assert sp.mission_markers(mission["markers"], 3) == [
            {"carry": True, "carried_by": -1} for _ in range(3)
        ]
