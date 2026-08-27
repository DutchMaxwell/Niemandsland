"""GATE M3-5 (NML-1073) — the Godot-free self-play harness.

Two layers, the same split `test_list_to_profile.py` uses:

  * unit tests over in-repo data only — the act fixtures the Rust gates already
    ship, plus `rng_range_godot.json`, the `randf_range` stream dumped from a
    live 4.6 engine by `tools/rng_range_fixture.gd`. These always run.

  * the CORPUS gate — whole games against `tools/core_selfplay.gd`'s own
    results, seed for seed. That corpus is Godot output living outside the repo
    (`~/selfplay_out/m3_ref_v2`, written by the recording command in
    `tools/selfplay_gate.py`'s docstring) and the AI lists come from the private
    mission tracker, so this half SKIPS wholesale when either is absent rather
    than failing a machine that never recorded it.

Three of the unit tests are RED-GREEN pairs, because each pins a change M3-5
made to the Rust core and a green assertion alone would not say the change is
load-bearing:

  * the charge-gate knob — the trainer never wires `state["charge_illegal"]`,
    so its menu carries charges the arena's gate refuses;
  * the sight refresh inside `resolve` — `BattleSim._los_clear` re-probes with
    the CURRENT centres, so a unit that just moved is seen from where it now is;
  * `randf_range` in single precision — the f64 form misses by an ULP, which is
    enough to move a deployed model into the next terrain cell.
"""

from __future__ import annotations

import json
import os
import struct
import sys
from collections import Counter
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import hero_attach_gate as hag  # noqa: E402
import selfplay as sp  # noqa: E402
from list_to_profile import (  # noqa: E402
    profiles_from_army_forge_json,
    selections_from_army_forge_json,
)

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"

#: The out-of-repo halves of the corpus gate.
REF_DIR = Path(os.path.expanduser("~/selfplay_out/m3_ref_v2"))
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
GATE_SEEDS = range(27, 47)


def read_acts(name: str):
    lines = [json.loads(l) for l in open(FIXTURES / name, encoding="utf-8")]
    return lines[0], lines[1:]


# ------------------------------------------------------------------- dice ---


def test_the_rng_reproduces_godots_randf_range_stream():
    """`nml_core.Rng` is the generator the harness holds across a whole game;
    `randf_range` is the draw `_deploy_zone` makes twice per unit. Same fixture
    the Rust GATE R2 reads, asked through the seam this time."""
    raw = json.loads((FIXTURES / "rng_range_godot.json").read_text())
    checked = 0
    for seed_s, block in raw.items():
        rng = nml_core.Rng(int(seed_s))
        for name, lo, hi in (("randf_range_m3_3", -3.0, 3.0), ("randf_range_1_9", 1.0, 9.0)):
            for i, want in enumerate(block[name]):
                got = rng.randf_range(lo, hi)
                assert got == want, "%s %s[%d]: %r != %r" % (seed_s, name, i, got, want)
                checked += 1
        assert rng.state == block["state"], "seed %s: post-draw state" % seed_s
    assert checked == 3000
    print("randf_range: %d/%d draws exact across %d seeds" % (checked, checked, len(raw)))


def test_red_the_double_precision_randf_range_misses_the_stream():
    """RED half: the same draw with the multiply-add in f64 — one rounding
    instead of two. It agrees for a while and then does not, which is why the
    gate above compares exactly instead of within a tolerance."""
    raw = json.loads((FIXTURES / "rng_range_godot.json").read_text())
    wrong = 0
    for seed_s, block in raw.items():
        rng = nml_core.Rng(int(seed_s))
        for name, lo, hi in (("randf_range_m3_3", -3.0, 3.0), ("randf_range_1_9", 1.0, 9.0)):
            for want in block[name]:
                if rng.randf() * (hi - lo) + lo != want:
                    wrong += 1
    assert wrong > 0, "the f64 form must miss recorded draws, or the gate proves nothing"
    print("RED (randf_range in f64): %d/3000 draws wrong" % wrong)


def test_the_live_generator_is_the_one_the_caller_keeps():
    """`resolve_stochastic_rng` advances the CALLER's generator, which is what
    lets one dice stream run across a whole game (`tools/core_selfplay.gd`
    passes the game `rng` to every played resolve). Its first call must agree
    with the per-call-seed form, and the generator must have moved."""
    header, acts = read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    act = acts[0]
    state = core.state_of(act["state"])
    action = act["pick"]["action"]

    rng = nml_core.Rng(4242)
    live = core.resolve_stochastic_rng(state, action, rng)
    seeded = core.resolve_stochastic(state, action, 4242)
    assert live.plain() == seeded.plain()

    # And it must ADVANCE: the same generator handed two activations in a row
    # must give the second one different dice from a freshly seeded one. Not
    # every activation rolls (a resolve only flips a coin for a fractional
    # wound remainder), so this walks the corpus until one does.
    advanced = False
    for a in acts:
        st = core.state_of(a["state"])
        r = nml_core.Rng(4242)
        before = r.state
        core.resolve_stochastic_rng(st, a["pick"]["action"], r)
        if r.state != before:
            advanced = True
            break
    assert advanced, "no recorded activation drew a die — the seam is untested"


# -------------------------------------------------------------- deployment ---


def test_deploy_zone_draws_two_values_per_unit_and_lays_models_five_wide():
    """`_deploy_zone` core_selfplay.gd:593-606 — x jitter then z spot, per unit,
    in list order; models 5 to a row at 1" spacing."""
    units = [{"model_count": 7}, {"model_count": 1}]
    rng = nml_core.Rng(27)
    want = [rng.randf_range(-3.0, 3.0), rng.randf_range(1.0, 9.0),
            rng.randf_range(-3.0, 3.0), rng.randf_range(1.0, 9.0)]

    rng = nml_core.Rng(27)
    pos = sp.deploy_zone(units, -24.0, 12.0, rng)
    assert [len(p) for p in pos] == [7, 1]
    # x0 = (-36 + 8) + 56 * (i + 0.5) / n: -14.0 for unit 0 of two, 14.0 for unit 1
    for u, (x0, jitter, spot) in enumerate(((-14.0, want[0], want[1]), (14.0, want[2], want[3]))):
        bx, bz = x0 + jitter, -24.0 + spot
        for m in range(len(pos[u])):
            assert pos[u][m][0] == sp.f32((bx + float(m % 5)) * sp.IN2M)
            assert pos[u][m][1] == 0.0
            assert pos[u][m][2] == sp.f32((bz + float(m // 5)) * sp.IN2M)
    # the sixth model starts the second row, one inch back and back at x offset 0
    assert pos[0][5][0] == pos[0][0][0]
    assert pos[0][5][2] == sp.f32((-24.0 + want[1] + 1.0) * sp.IN2M)


def test_the_deployment_stream_is_the_games_own():
    """Deployment draws BEFORE the opener roll-off, from the same generator —
    so a harness that seeded a private one for deployment would hand the roll-off
    different dice. Pinned as the draw COUNT: 2 per unit, both sides, then two
    `randi_range(1, 6)`."""
    rng = nml_core.Rng(27)
    sp.deploy_zone([{"model_count": 1}] * 3, -24.0, 12.0, rng)
    sp.deploy_zone([{"model_count": 1}] * 2, 12.0, 12.0, rng)
    after_deploy = rng.state
    rng.randi_range(1, 6)
    rng.randi_range(1, 6)
    assert rng.state != after_deploy

    fresh = nml_core.Rng(27)
    for _ in range(5):
        fresh.randf_range(-3.0, 3.0)
        fresh.randf_range(1.0, 9.0)
    assert fresh.state == after_deploy, "deployment must consume exactly 2 draws per unit"


# ----------------------------------------------------------------- capture ---


TINY_LIST = {
    "gameSystem": "gf",
    "units": [
        {
            "id": "a",
            "selectionId": "sa",
            "name": "Scout",
            "quality": 4,
            "defense": 4,
            "size": 2,
            "rules": [{"label": "Tough(3)", "name": "Tough", "rating": 3}],
            "weapons": [{"name": "Rifle", "range": 24, "attacks": 1, "count": 1}],
        }
    ],
}


def test_capture_produces_a_state_the_core_reads_back_unchanged():
    """`_capture` writes exactly the plain dict `Core.state_of` consumes — and
    `plain()` hands it back with the same numbers. A field this port forgot
    would show up as a missing key on the way out."""
    profiles = profiles_from_army_forge_json(TINY_LIST, "robot_legions", 1)
    units = list(profiles.values())
    core = nml_core.load(str(REPO))
    header, _ = read_acts("acts_25.jsonl")
    core.set_header({"profiles": profiles, "terrain": header["terrain"], "knobs": sp.TRAINER_KNOBS})
    board = nml_core.board(header["terrain"])
    rng = nml_core.Rng(1)
    pos = sp.deploy_zone(units, -24.0, 12.0, rng)
    plain = sp.capture(units, pos, core.capture_reads(), board, [[0.0, 0.0, 0.0]])

    state = core.state_of(plain)
    back = state.plain()
    for key, want in plain["units"].items():
        got = back["units"][key]
        for field, value in want.items():
            assert got[field] == value, "%s.%s: %r != %r" % (key, field, got[field], value)
    assert back["los_pairs"] == plain["los_pairs"]
    assert back["round"] == 1 and back["rounds_total"] == sp.ROUNDS
    assert back["scoring"] == "end"


#: D4: a host, the HERO that joins it (`joinToUnit` with `combined` false —
#: a combined partner would be folded INTO the host instead) and a lone unit.
JOIN_LIST = {
    "gameSystem": "gf",
    "units": [
        {
            "id": "h", "selectionId": "sh", "joinToUnit": "sa", "name": "Lord",
            "quality": 3, "defense": 4, "size": 1,
            "rules": [{"label": "Hero", "name": "Hero"}],
            "weapons": [{"name": "Blade", "range": 0, "attacks": 3, "count": 1}],
        },
        TINY_LIST["units"][0],
        {
            "id": "b", "selectionId": "sb", "name": "Lone", "quality": 4,
            "defense": 4, "size": 1, "rules": [],
            "weapons": [{"name": "Rifle", "range": 24, "attacks": 1, "count": 1}],
        },
    ],
}


def test_the_hero_attach_knob_joins_the_list_the_way_the_table_does():
    """`BattleSim.capture` battle_sim.gd:1352-1369: the hero whose
    `join_to_unit` names the host's `selection_id` becomes that host's attached
    hero, and the host's PROFILE gains the hero's rules as
    `attached_hero_rules`. RED half: at the default the same list joins nobody,
    so every `attached` is empty and no profile field moves."""
    profiles = profiles_from_army_forge_json(JOIN_LIST, "robot_legions", 1)
    units = list(profiles.values())
    selections = selections_from_army_forge_json(JOIN_LIST, 1)
    # loader order is ROSTER order: the joining hero is listed first here.
    hero, host, lone = (u["unit_id"] for u in units)
    assert selections[hero] == ("sh", "sa") and selections[host] == ("sa", "")

    attached, attached_to = sp.derive_attachment(units, selections)
    assert attached == {host: [hero], hero: [], lone: []}
    assert attached_to == {host: "", hero: host, lone: ""}

    core = nml_core.load(str(REPO))
    header, _ = read_acts("acts_25.jsonl")
    board = nml_core.board(header["terrain"])
    profiles[host]["attached_hero_rules"] = [profiles[hero]["special_rules"]]
    core.set_header({"profiles": profiles, "terrain": header["terrain"],
                     "knobs": sp.TRAINER_KNOBS})
    rng = nml_core.Rng(1)
    pos = sp.deploy_zone(units, -24.0, 12.0, rng)
    plain = sp.capture(units, pos, core.capture_reads(), board, [[0.0, 0.0, 0.0]],
                       attached, attached_to)
    assert plain["units"][host]["attached"] == [hero]
    assert plain["units"][hero]["attached_to"] == host
    assert core.state_of(plain).plain()["units"][hero]["attached_to"] == host
    assert profiles[host]["attached_hero_rules"] == [["Hero"]]

    red = sp.capture(units, pos, core.capture_reads(), board, [[0.0, 0.0, 0.0]])
    assert all(u["attached"] == [] and u["attached_to"] == "" for u in red["units"].values())


def test_hero_attach_refuses_a_mode_it_does_not_have():
    """A silently ignored mode would write a corpus whose header claims a rule
    it did not play."""
    assert sp.resolve_hero_attach("table") is True
    assert sp.resolve_hero_attach("off") is False
    with pytest.raises(ValueError):
        sp.resolve_hero_attach("Table")


def test_the_arena_fixture_carries_four_joined_heroes():
    """The gate's arena reader over an in-repo recording: `acts_25.jsonl` is a
    real arena game and its first act joins four heroes. RED half: the same
    comparison against a roster with the attachment stripped must NOT agree —
    that is exactly what `hero_attach="off"` produces."""
    header, acts = read_acts("acts_25.jsonl")
    arena = hag.arena_graph(header["profiles"], acts[0]["state"]["units"])
    joined = [g for side in arena.values() for g in side if g[2] is not None]
    assert len(joined) == 4, [g[0][0] for g in joined]
    assert all(g[3] == 1 for side in arena.values() for g in side if g[1])

    stripped = {s: [(g[0], (), None, 0) for g in arena[s]] for s in (1, 2)}
    assert any(Counter(arena[s]) != Counter(stripped[s]) for s in (1, 2))


@pytest.mark.skipif(not ARMY1.exists() or not ARMY2.exists(),
                    reason="the AI lists live in the private mission tracker")
def test_the_trainer_derives_the_arena_fixtures_attachment_graph():
    """GATE D4 in miniature: `acts_25.jsonl` was recorded from ARMY1 vs ARMY2,
    so the same two lists through the trainer's loader must produce the arena's
    attachment graph, unit for unit. RED half: at `hero_attach="off"` they
    must not."""
    header, acts = read_acts("acts_25.jsonl")
    arena = hag.arena_graph(header["profiles"], acts[0]["state"]["units"])
    units1, units2 = sp.load_army(ARMY1, 1), sp.load_army(ARMY2, 2)
    selections = dict(sp.load_selections(ARMY1, 1))
    selections.update(sp.load_selections(ARMY2, 2))
    attached, attached_to = sp.derive_attachment(units1 + units2, selections)
    by_id = {u["unit_id"]: u for u in units1 + units2}
    for u in units1 + units2:
        u["attached_hero_rules"] = [by_id[h]["special_rules"] for h in attached[u["unit_id"]]]

    got = hag.trainer_graph(units1, units2, attached, attached_to)
    for side in (1, 2):
        assert Counter(arena[side]) == Counter(got[side]), side

    red = hag.trainer_graph(units1, units2, {}, {})
    assert any(Counter(arena[s]) != Counter(red[s]) for s in (1, 2))


def test_the_round_refill_follows_the_caster_rule():
    """`_refill_round_caster_points` core_selfplay.gd:120-135 over
    `GameUnit.add_round_caster_points`: Caster(X) ACCUMULATES to a cap of 6, a
    Caster Group RESETS to its bearer count (and the trainer's bearers never
    die, so that is the full model count)."""
    caster = {"caster_value": 2, "model_count": 5, "special_rules": ["Caster(2)"]}
    unit = {"casts": 1}
    assert sp._refill_round_caster_points(unit, caster) == 2
    assert unit["casts"] == 3
    unit["casts"] = 5
    assert sp._refill_round_caster_points(unit, caster) == 1  # capped at 6
    assert unit["casts"] == sp.CASTER_POINTS_CAP

    group = {"caster_value": 5, "model_count": 5, "special_rules": ["Caster Group"]}
    unit = {"casts": 0}
    assert sp._refill_round_caster_points(unit, group) == 5
    assert unit["casts"] == 5

    plain = {"caster_value": 0, "model_count": 3, "special_rules": []}
    unit = {"casts": 0}
    assert sp._refill_round_caster_points(unit, plain) == 0


# --------------------------------------------------- the two Rust seam knobs ---


def test_the_charge_gate_knob_is_load_bearing():
    """`tools/core_selfplay.gd` never stamps `state["charge_illegal"]`, and both
    menu sites read it as `illegal_cb.is_valid() and illegal_cb.call(...)`
    (ai_planner.gd:1024/1308) — so a gateless caller is offered charges the
    arena's gate refuses. RED-GREEN: the two knob settings must not agree on
    every unit of every act, or the knob is decoration."""
    header, acts = read_acts("acts_25.jsonl")
    gated = nml_core.load(str(REPO))
    gated.set_header(header)  # no `charge_gate` key -> the default, true
    assert gated.knobs()["charge_gate"] is True

    open_header = dict(header)
    open_header["knobs"] = dict(header.get("knobs", {}))
    open_header["knobs"]["charge_gate"] = False
    ungated = nml_core.load(str(REPO))
    ungated.set_header(open_header)
    assert ungated.knobs()["charge_gate"] is False

    extra = 0
    for act in acts:
        a_state = gated.state_of(act["state"])
        b_state = ungated.state_of(act["state"])
        for key in act["pool"]:
            a = gated.candidates(a_state, key)
            b = ungated.candidates(b_state, key)
            assert len(b) >= len(a), "dropping the gate can only ADD charges"
            extra += len(b) - len(a)
    assert extra > 0, "the gate refuses no charge in this corpus — the knob proves nothing"
    print("charge gate: %d extra charge candidates once the gate is off" % extra)


def test_the_charge_gate_mode_stamps_what_the_table_stamped():
    """GATE D2 (NML-1073) in miniature, on the in-repo arena recording.

    `charge_gate="table"` has to stamp what `SoloController` stamped: for every
    act of `acts_25.jsonl` the trainer's `charge_illegal` matrix must equal the
    one the recorder read off the LIVE Callable, pair for pair. RED-GREEN: with
    the mode "off" the trainer stamps `{}`, which is what the recorder writes
    for a caller whose Callable is invalid — so the same comparison must go red
    on every recorded pair."""
    assert sp.resolve_charge_gate("table") is True
    assert sp.resolve_charge_gate("off") is False
    with pytest.raises(ValueError):
        sp.resolve_charge_gate("on")

    header, acts = read_acts("acts_25.jsonl")
    cores = {}
    for mode in sp.CHARGE_GATE_MODES:
        h = dict(header)
        h["knobs"] = dict(header.get("knobs", {}), charge_gate=sp.resolve_charge_gate(mode))
        cores[mode] = nml_core.load(str(REPO))
        cores[mode].set_header(h)

    pairs = red = 0
    for act in acts:
        want = act["charge_illegal"]
        assert want, "the recording carries no stamp — it cannot gate anything"
        assert sp.charge_illegal_stamp(cores["table"], cores["table"].state_of(act["state"])) == want
        assert sp.charge_illegal_stamp(cores["off"], cores["off"].state_of(act["state"])) == {}
        pairs += len(want)
        red += len(want)
    assert pairs > 0
    print("charge gate stamp: %d/%d pairs equal, %d red with the gate off" % (pairs, pairs, red))


# ------------------------------------------------------- D1-B3: the tray ----


def test_the_dice_mode_is_validated():
    """`resolve_dice` takes the two modes and RAISES on anything else — a run
    that meant to record table dice and silently recorded expected values is
    the one failure this knob exists to make impossible."""
    assert sp.resolve_dice("expected") == "expected"
    assert sp.resolve_dice("table") == "table"
    for bad in ("real", "on", "", "Table"):
        with pytest.raises(ValueError):
            sp.resolve_dice(bad)


def test_the_tray_is_the_engines_randi_range_and_burns_the_zero_die_roll():
    """`nml_core.Tray` from Python, against the two things `dice.rs` pins:
    a face is one `randi_range(1, 6)` on the seeded twin (main.gd:7152-7159),
    and `maxi(1, count)` makes a ZERO-die roll cost one draw all the same."""
    tray = nml_core.Tray(27)
    twin = nml_core.Rng(27)
    assert tray.roll(5) == [twin.randi_range(1, 6) for _ in range(5)]
    assert tray.state == twin.state

    burned, straight = nml_core.Tray(27), nml_core.Tray(27)
    assert len(burned.roll(0)) == 1, "a zero-die roll still rolls one"
    assert burned.roll(3) == straight.roll(4)[1:], "and it burns exactly one draw"


def _digest_without_the_dice_mode(res: dict) -> str:
    """The game, with the ONE field B3 is allowed to change removed."""
    body = dict(res)
    body["knobs"] = {k: v for k, v in res["knobs"].items() if k != "dice"}
    return sp.result_digest(body)


@pytest.mark.skipif(
    not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()),
    reason="no terrain bank / AI lists on this machine",
)
def test_b3_the_dice_knob_is_stamped_and_does_not_move_the_game_yet():
    """THE B3 INVARIANT, and it is meant to be broken later.

    B3 ships the tray and the stream split but no consumer, so `dice="table"`
    must still play the expected-value game: same seed, same everything except
    the one string `knobs["dice"]`, which is removed before the digest is
    taken. B4 (shooting on the tray) and B5 (melee/morale) will make this fail
    on purpose — when they do, this test is inverted, not deleted.

    RED PROOF, because a green digest comparison on its own proves nothing
    here: burn ONE draw out of the GAME generator per round and the digest must
    move. MEASURED while writing this test — seed 27 alone would NOT have
    moved (its played activations spend the mean-preserving remainder flip in
    one round of four, and that flip lands the same side either way), which is
    exactly why the invariant runs on seed 28 as well and the red proof runs on
    the seed that is stream-sensitive."""
    core = nml_core.load(str(REPO))
    for seed in (27, 28):
        out = {}
        for mode in sp.DICE_MODES:
            res = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, dice=mode)
            assert res["knobs"]["dice"] == mode, "the corpus file must document its rung"
            assert res["dice_seed"] == res["seed"], "arena_match.gd:984-985 — dice_seed IS the seed"
            out[mode] = _digest_without_the_dice_mode(res)
        assert out["expected"] == out["table"], (
            "B3 has no tray consumer — seed %d must play the identical game: %s" % (seed, out)
        )

    base = _digest_without_the_dice_mode(sp.play_game(28, ARMY1, ARMY2, REPO, BANK_DIR, core))
    played = sp._play_round

    def burn_one(core_, state, opener, rng, log, round_no, **kw):
        rng.randf()  # a consumer drawing from the WRONG generator
        return played(core_, state, opener, rng, log, round_no, **kw)

    sp._play_round = burn_one
    try:
        shifted = _digest_without_the_dice_mode(
            sp.play_game(28, ARMY1, ARMY2, REPO, BANK_DIR, core)
        )
    finally:
        sp._play_round = played
    assert shifted != base, "seed 28 is stream-blind — the invariant above measures nothing"
    print("B3 invariant: seeds 27+28 identical in both modes; a stream shift reddens seed 28")


def test_the_top_k_horizon_env_knobs_mirror_ai_planner(monkeypatch):
    """`NML_TOP_K` / `NML_HORIZON` (ai_planner.gd:49-56, 290-297) reach the fast
    trainer the same way: unset is the trainer's own default, set is
    `int(env)` clamped to the SAME bounds — `0` clamps UP rather than asking
    for the default — and an explicit argument outranks the env. The resolved
    pair also has to land in `Core.knobs()`, which is what the search actually
    runs on (`plan_with_rollout`'s `Rollout::new(policy, self.knobs)`)."""
    monkeypatch.delenv("NML_TOP_K", raising=False)
    monkeypatch.delenv("NML_HORIZON", raising=False)
    assert sp.resolve_top_k(None) == sp.ROLLOUT_TOP_K == 6
    assert sp.resolve_horizon(None) == sp.ROLLOUT_HORIZON_ROUNDS == 2

    monkeypatch.setenv("NML_TOP_K", "2")
    monkeypatch.setenv("NML_HORIZON", "1")
    assert sp.resolve_top_k(None) == 2
    assert sp.resolve_horizon(None) == 1
    assert sp.resolve_top_k(5) == 5  # an explicit argument outranks the env

    # ai_planner.gd's `clampi(int(e), 1, 32)` / `clampi(int(e), 1, 3)`: `0` is
    # NOT a second way to ask for the default, it clamps UP to the floor.
    monkeypatch.setenv("NML_TOP_K", "0")
    monkeypatch.setenv("NML_HORIZON", "0")
    assert sp.resolve_top_k(None) == 1
    assert sp.resolve_horizon(None) == 1
    monkeypatch.setenv("NML_TOP_K", "999")
    assert sp.resolve_top_k(None) == 32  # clamped, ai_planner.gd:54

    header, _ = read_acts("acts_25.jsonl")
    monkeypatch.setenv("NML_TOP_K", "2")
    monkeypatch.setenv("NML_HORIZON", "1")
    stamped = dict(header)
    stamped["knobs"] = dict(
        header.get("knobs", {}), top_k=sp.resolve_top_k(None), horizon=sp.resolve_horizon(None)
    )
    core = nml_core.load(str(REPO))
    core.set_header(stamped)
    assert core.knobs()["top_k"] == 2
    assert core.knobs()["horizon"] == 1


def _fresh_los(board, plain):
    return board.los_pairs(plain["units"])


def test_resolve_refreshes_the_sight_matrix_from_the_board():
    """`BattleSim._los_clear` (battle_sim.gd:792-796) calls the state's
    `los_blocked` with the CURRENT centres, so a unit that just moved is probed
    from where it now stands. RED-GREEN: after a move the state's matrix must be
    the one the board gives for the NEW positions, and it must differ from the
    parent's — otherwise the refresh is untested."""
    header, acts = read_acts("acts_25.jsonl")
    board = nml_core.board(header["terrain"])
    core = nml_core.load(str(REPO))
    core.set_header(header)

    moved = 0
    for act in acts:
        plain = json.loads(json.dumps(act["state"]))
        plain["los_pairs"] = _fresh_los(board, plain)
        state = core.state_of(plain)
        for key in act["pool"]:
            for cand in core.candidates(state, key):
                if cand.get("dest") is None:
                    continue
                after = core.resolve(state, cand).plain()
                assert after["los_pairs"] == _fresh_los(board, after), (
                    "resolve must leave the matrix the board gives for the new positions"
                )
                if after["los_pairs"] != plain["los_pairs"]:
                    moved += 1
    assert moved > 0, "no move changed a sight line — the refresh is not being exercised"
    print("sight refresh: %d moves rewrote at least one row" % moved)


def test_red_a_state_without_the_seam_keeps_its_answers():
    """The other half: a state with no `los_pairs` had no `los_blocked` seam in
    the game either (the arena never stamps one), so `resolve` must not invent
    one. Absent stays absent."""
    header, acts = read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    act = acts[0]
    assert "los_pairs" not in act["state"]
    state = core.state_of(act["state"])
    after = core.resolve(state, act["pick"]["action"]).plain()
    assert "los_pairs" not in after


def test_capture_reads_answer_for_every_unit_of_the_header():
    """The four capture-time registry reads, one row per profile."""
    header, _ = read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    reads = core.capture_reads()
    assert set(reads) == set(header["profiles"])
    for key, r in reads.items():
        assert set(r) == {"morale_bonus", "aircraft", "charge_no_difficult", "shroud"}
        assert isinstance(r["morale_bonus"], int) and r["morale_bonus"] >= 0
        assert isinstance(r["aircraft"], bool)
        rules = header["profiles"][key]["special_rules"]
        want = any(str(x).startswith("Strider") or str(x).startswith("Flying") for x in rules)
        assert r["charge_no_difficult"] is want


# --------------------------------------------------------------- the gate ----


def _gate_seeds():
    if not (REF_DIR.is_dir() and BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()):
        return []
    return [s for s in GATE_SEEDS if (REF_DIR / ("core_s%d.json" % s)).exists()]


@pytest.mark.skipif(not _gate_seeds(), reason="no recorded core_selfplay reference on this machine")
def test_the_python_harness_plays_the_same_game_seed_for_seed():
    """THE GATE. Whole games against `tools/core_selfplay.gd`'s own results:
    winner, objectives, VP, rounds played, and the SEQUENCE of picks."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
    import selfplay_gate as gate  # noqa: E402

    core = nml_core.load(str(REPO))
    seeds = _gate_seeds()
    bad = []
    for seed in seeds:
        with open(REF_DIR / ("core_s%d.json" % seed), encoding="utf-8") as f:
            ref = json.load(f)
        got = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core)
        diff = gate.compare(ref, got, gate.ref_picks(REF_DIR, seed))
        if diff:
            bad.append((seed, diff))
    assert not bad, "seeds that diverged: %s" % bad[:3]
    print("GATE M3-5: %d/%d seeds seed-for-seed equal" % (len(seeds), len(seeds)))


@pytest.mark.skipif(not _gate_seeds(), reason="no recorded core_selfplay reference on this machine")
def test_red_a_different_deployment_is_a_different_game():
    """RED PROOF for the gate: deploy from a generator seeded `seed + 1` while
    the game's own generator is advanced past the same draws and discards them —
    same opener, same dice, different starting positions. Every seed must
    diverge, or the gate is not measuring the deployment."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
    import selfplay_gate as gate  # noqa: E402

    core = nml_core.load(str(REPO))
    seeds = _gate_seeds()
    same = []
    for seed in seeds:
        with open(REF_DIR / ("core_s%d.json" % seed), encoding="utf-8") as f:
            ref = json.load(f)
        got = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, deploy_rng_seed=seed + 1)
        if not gate.compare(ref, got, gate.ref_picks(REF_DIR, seed)):
            same.append(seed)
    assert not same, "seeds that survived a swapped deployment: %s" % same
    print("RED PROOF: %d/%d seeds diverge on a swapped deployment stream" % (len(seeds), len(seeds)))


def test_f32_is_the_engines_real_t():
    """Sanity on the one arithmetic helper this module owns."""
    assert sp.f32(0.1) == struct.unpack("f", struct.pack("f", 0.1))[0]
    assert sp.f32(0.1) != 0.1
    assert sp._centre_f32([]) == [0.0, 0.0, 0.0]
    assert sp._centre_f32([[1.0, 0.0, 3.0], [3.0, 0.0, 1.0]]) == [2.0, 0.0, 2.0]
