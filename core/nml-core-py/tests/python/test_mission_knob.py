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


def test_smash_and_grab_catalog_entry_pins_rounds_roles_and_secret_markers():
    snap = sp.resolve_mission("smash_and_grab", REPO)
    assert snap["name"] == "Smash & Grab" and snap["scoring"] == "extract"
    assert snap["rounds"] == 6 and snap["roles"] is True and snap["attacker_points_factor"] == 1.25
    assert snap["markers"]["count"] == "d3+2" and snap["markers"]["secret"] is True
    assert "carry" not in snap["markers"]
    assert sp.mission_markers(snap["markers"], 4) == [{"secret": "", "revealed": False}] * 4


def test_last_stand_catalog_entry_pins_phases_recycling_and_the_central_marker():
    snap = sp.resolve_mission("last_stand", REPO)
    assert snap["name"] == "Last Stand" and snap["scoring"] == "end" and snap["rounds"] == 6 and snap["roles"] is True
    assert "attacker_points_factor" not in snap
    assert snap["markers"] == {"count": 1, "placement": "table_centre"}
    assert snap["reserves"] == {"who": "attacker", "recycle": True, "arrive_on": 6, "from_round": 2,
                                "zone": "edge_band_12", "gates": {}}
    ph = sp._phase_args(snap, 1, REPO)   # attacker = slot 1: the defender (side 1) goes first
    assert [(p["side"], p["share"]) for p in ph] == [(1, "all"), (0, "all")]
    assert sp._reserve_args(snap, 1)[0] == [True, False], "only the attacker recycles"


@needs_lists
def test_a_six_round_catalog_mission_plays_six_rounds_and_duel_stays_at_four():
    """NML-1010 D1: the match length is catalog data. No shipped mission is longer than 4,
    so a synthetic 6-round clone of duel is the fixture; duel itself must stay at 4."""
    core = nml_core.load(str(REPO))
    sp.resolve_mission("duel", REPO)
    catalog = sp._MISSION_CATALOG_CACHE[str(REPO)]
    catalog["six_round_fixture"] = dict(catalog["duel"], rounds=6)
    try:
        six = _play("six_round_fixture", core)
        duel = _play("duel", core)
    finally:
        del catalog["six_round_fixture"]
    assert six["rounds_played"] == 6 and six["mission"]["rounds"] == 6
    assert duel["rounds_played"] == 4 and duel["mission"]["rounds"] == 4


@needs_lists
def test_roles_mission_stamps_the_roll_off_winners_pick_and_duel_stays_roles_free():
    """NML-1010 D2b: R7a — the roll-off winner attacks when the mission grants the +25 % side,
    else defends. Same seed = same winner, so the two catalogs stamp opposite P1 roles."""
    core = nml_core.load(str(REPO))
    sp.resolve_mission("duel", REPO)
    catalog = sp._MISSION_CATALOG_CACHE[str(REPO)]
    base = dict(catalog["duel"], roles=True)
    catalog["roles_bonus"] = dict(base, attacker_points_factor=1.25)
    catalog["roles_even"] = dict(base, attacker_points_factor=1.0)
    try:
        bonus, even = _play("roles_bonus", core), _play("roles_even", core)
        duel = _play("duel", core)
    finally:
        del catalog["roles_bonus"], catalog["roles_even"]
    assert {bonus["mission"]["role_p1"], even["mission"]["role_p1"]} == {"attacker", "defender"}
    assert "role_p1" not in duel["mission"]


def test_style_zone_args_bound_a_disc_by_its_square_and_front_line_has_none():
    """NML-1010 D5: the pair the Rust spot search takes — the disc list plus its bounding rect."""
    assert sp.resolve_zone_style({"deployment": "front_line"}, REPO) is None
    style = sp.resolve_zone_style({"deployment": "centre_disc_12"}, REPO)
    rect, zl = sp._style_zone_args(style, "1")
    r = 12.0 * sp.IN2M
    assert rect == pytest.approx([-r, -r, 2 * r, 2 * r]) and zl == [{"disc": {"c": [0, 0], "r_in": 12}}]


@needs_lists
def test_an_arena_game_hands_the_missions_zone_to_the_deploy_pipeline(monkeypatch):
    """The disc mission's zone reaches `nml_core.deploy_side`; duel's (front_line) stays None."""
    core = nml_core.load(str(REPO))
    sp.resolve_mission("duel", REPO)
    catalog = sp._MISSION_CATALOG_CACHE[str(REPO)]
    catalog["disc_fixture"] = dict(catalog["duel"], deployment="centre_disc_12")
    seen: list = []
    real = nml_core.deploy_side

    def spy(*a, **kw):
        seen.append(kw.get("zones"))
        return real(*a, **kw)

    monkeypatch.setattr(nml_core, "deploy_side", spy)
    try:
        for m in ("disc_fixture", "duel"):
            sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission=m, deployment="arena", **FAST)
    finally:
        del catalog["disc_fixture"]
    disc = [{"disc": {"c": [0, 0], "r_in": 12}}]
    assert seen == [disc, disc, None, None]  # two deploy_side calls (one per slot) per game


def test_roles_decide_each_slots_gates_and_a_roles_less_mission_has_none():
    """NML-1010 D6b: R7a picks the attacker from the roll-off winner; the catalog gates follow the role."""
    ad = {"roles": True, "attacker_points_factor": 1.25,
          "deploy_gates": {"attacker": {"min_from_enemy_in": 12}, "defender": {"max_from_friend_in": 6}}}
    assert sp._ai_attacker(ad, 2) == 2 and sp._ai_attacker(dict(ad, attacker_points_factor=1.0), 2) == 1
    assert sp._ai_attacker({"scoring": "end"}, 2) == 0
    assert sp._role_gates(ad, 2) == {"1": {"max_from_friend_in": 6}, "2": {"min_from_enemy_in": 12}}
    assert sp._role_gates(ad, 0) == {} and sp._role_gates({"roles": True}, 1) == {}


@needs_lists
def test_an_interleaved_game_hands_each_side_its_role_gates_to_the_deploy_pipeline(monkeypatch):
    core = nml_core.load(str(REPO))
    sp.resolve_mission("duel", REPO)
    catalog = sp._MISSION_CATALOG_CACHE[str(REPO)]
    gates = {"attacker": {"min_from_enemy_in": 12}, "defender": {"max_from_friend_in": 6}}
    catalog["gates_fixture"] = dict(catalog["duel"], roles=True, attacker_points_factor=1.25, deploy_gates=gates)
    seen: list = []
    real = nml_core.deploy_interleaved

    def spy(*a, **kw):
        seen.append((kw.get("gates1"), kw.get("gates2")))
        return real(*a, **kw)

    monkeypatch.setattr(nml_core, "deploy_interleaved", spy)
    try:
        res = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission="gates_fixture",
                           deployment="interleaved", **FAST)
        sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission="duel", deployment="interleaved", **FAST)
    finally:
        del catalog["gates_fixture"]
    # the winner (opener) attacks under factor 1.25; P1's role is stamped in the result
    want = (gates["attacker"], gates["defender"]) if res["mission"]["role_p1"] == "attacker" else (gates["defender"], gates["attacker"])
    assert seen == [want, (None, None)]


def test_phase_args_map_roles_to_sides_and_styles_to_zones():
    """NML-1010 D7b: attacker slot 1 -> side 0, the defender -> side 1; a style gives rect + shape."""
    md = {"roles": True, "deploy_phases": [["defender", "half", "centre_disc_12"], ["attacker", "all", "edge_band_12"]]}
    ph = sp._phase_args(md, 1, REPO)
    assert [(p["side"], p["share"]) for p in ph] == [(1, "half"), (0, "all")]
    assert ph[0]["zones"] == [{"disc": {"c": [0, 0], "r_in": 12}}] and len(ph[1]["zones"]) == 4
    assert [p["side"] for p in sp._phase_args(md, 2, REPO)] == [0, 1]
    assert sp._phase_args(md, 0, REPO) == [] and sp._phase_args({"roles": True}, 1, REPO) == []


@needs_lists
def test_an_arena_game_runs_the_missions_phases_through_deploy_phased(monkeypatch):
    core = nml_core.load(str(REPO))
    sp.resolve_mission("duel", REPO)
    catalog = sp._MISSION_CATALOG_CACHE[str(REPO)]
    catalog["phase_fixture"] = dict(catalog["duel"], roles=True, attacker_points_factor=1.25,
                                    deploy_phases=[["defender", "half", "centre_disc_12"], ["attacker", "all", "edge_band_12"],
                                                   ["defender", "rest", "anywhere"]])
    seen: list = []
    real = nml_core.deploy_phased

    def spy(*a, **kw):
        out = real(*a, **kw)
        seen.append([e[0] for e in out["sequence"]])
        return out

    monkeypatch.setattr(nml_core, "deploy_phased", spy)
    try:
        res = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission="phase_fixture", deployment="arena", **FAST)
        sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission="duel", deployment="arena", **FAST)
    finally:
        del catalog["phase_fixture"]
    assert len(seen) == 1, "duel has no phases"
    seq = seen[0]
    attacker = 1 if res["mission"]["role_p1"] == "attacker" else 2
    defender = 3 - attacker
    first_attack = seq.index(attacker)
    assert seq[:first_attack] and set(seq[:first_attack]) == {defender}, "the defender's half goes first"
    assert seq[-1] == defender or defender in seq[first_attack:], "the defender's rest follows the attacker"


class _Dice:
    """A scripted game-stream stand-in: `randi_range` answers the queued faces in order."""

    def __init__(self, faces):
        self.faces = list(faces)

    def randi_range(self, lo, hi):
        return self.faces.pop(0)


def _reserve_fixture():
    plain = {"units": {"m1": {"player": 1, "dormant": True, "dormant_models": 2, "dormant_wounds": [1, 1],
                              "earliest_arrival_round": 2, "positions": [], "radii": []}}}
    reads = {"m1": {"repel_m": 0.0, "beacon": False, "beacon_r_m": 0.0, "ring_m": 0.0, "radius": 0.04,
                    "footprint": [[0.0, 0.0]], "base_r": 0.016, "flying": False}}
    return plain, reads


def test_a_mission_reserve_arrives_only_on_the_winning_die_and_inside_its_zone():
    """NML-1010 D8b: one die per held unit per round from from_round; a 4+ lands it in the 12" frame."""
    cfg = {"from_round": 2, "arrive_on": 4, "zone": "edge_band_12",
           "gates": {"min_from_enemy_in": 12, "min_from_marker_in": 12}}
    zl = sp._style_zone_args(sp._style_by_id("edge_band_12", REPO), "1")[1]
    objs = [[0.0, 0.0, 0.0]]

    def run(round_no, faces):
        plain, reads = _reserve_fixture()
        dice = _Dice(faces)
        n = sp._arrive_reserves(plain, reads, None, objs, 1, round_no,
                                mission={"keys": {"m1"}, "cfg": cfg, "rng": dice, "zones": zl})
        return n, plain["units"]["m1"], dice.faces

    n, u, left = run(1, [6])
    assert n == 0 and u["dormant"] and left == [6], "before from_round: no die is even rolled"
    n, u, left = run(2, [3])
    assert n == 0 and u["dormant"] and left == [], "a 3 on a 4+ stays in reserve"
    n, u, _ = run(2, [4])
    assert n == 1 and not u["dormant"] and u["ambush_arrived_round"] == 2
    x, z = u["positions"][0][0], u["positions"][0][2]
    assert abs(x) >= 24 * sp.IN2M - 1e-6 or abs(z) >= 12 * sp.IN2M - 1e-6, "inside the 12\" frame, not the centre"
    assert (x * x + z * z) ** 0.5 > 12 * sp.IN2M + 0.016, "more than the marker gate from the marker"


def test_core_recycles_a_destroyed_unit_once_and_the_plain_hook_applies_the_last_stand_rules():
    """NML-1010 D11b: `recycle_destroyed` parks the covered side's dead (once); at a round start the
    plain hook makes the copy due from the mission's first reserve round and drops the reserves of a
    side with no unit left on the table."""
    lines = (FIXTURES / "acts_25.jsonl").read_text().splitlines()
    header, plain = json.loads(lines[0]), json.loads(lines[1])["state"]
    core = nml_core.load(str(REPO))
    core.set_header(header)
    p2 = [k for k, u in plain["units"].items() if u["player"] == 2]
    for k, u in plain["units"].items():
        u.update(alive=0 if k in p2 else 1, positions=[] if k in p2 else [[1.0, 0, 1.0]],
                 radii=[] if k in p2 else [0.02], wounds=[] if k in p2 else [1], shaken=False, aircraft=False)
    state = core.state_of(plain)
    state, keys = nml_core.recycle_destroyed(state, 2, 2)
    assert sorted(keys) == sorted(p2)
    back = state.plain()["units"]
    assert all(back[k].get("dormant") for k in keys)
    _, again = nml_core.recycle_destroyed(state, 2, 3)
    assert again == [], "parked units are skipped"
    cfg = {"from_round": 4, "arrive_on": 6, "recycle": True}
    units = state.plain()["units"]
    sp._last_stand_plain({"units": units}, 3, cfg, [False, True], set(keys))
    assert all(units[k]["earliest_arrival_round"] == 4 for k in keys), "due from the first reserve round"
    # round 4 and the covered side has nothing on the table: the reserves are lost
    sp._last_stand_plain({"units": units}, 4, cfg, [False, True], set(keys))
    assert all(not units[k]["dormant"] and units[k]["alive"] == 0 for k in keys)
