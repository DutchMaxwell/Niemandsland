"""GATE M3-9 (NML-1073) — the counterfactual SIDECARS of the Godot-free trainer.

M3-5 proved the Python harness plays the same GAME. This file holds it to the
same FILE: the v5 board rows, the roster indices, the eval feature vector and the
two counterfactual blocks the training pipeline actually consumes —
`planner_positions[].pair` (E0b: the chosen and the rejected candidate each
resolved on a clone) and `.fork` (E2-v2: one fork per round, both branches played
to game end, three playouts each).

Two layers, the same split `test_selfplay.py` uses: unit tests over the in-repo
act fixtures, which always run, and the CORPUS gate against
`tools/core_selfplay.gd`'s own `core_s<seed>.json`, which skips wholesale on a
machine that never recorded it.

Two RED-GREEN pairs pin the claims that a green assertion alone would not make:

  * the sidecars change no game — proved by playing every gate seed with and
    without them and comparing the pick sequences, with the RED half showing the
    sidecar generators do roll dice (so "unchanged" is not "nothing happened");
  * the board's quality/defense columns read `source_data`, not the live profile
    — the RED half turns the override off and watches the corpus diverge.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import list_to_profile  # noqa: E402
import selfplay as sp  # noqa: E402
import sidecar_gate as gate  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"

#: The recorded `core_selfplay` corpora this gate can hold the port to, NEWEST
#: FIRST with the encoder reading each one was written under. `m3_ref_v3` is the
#: FIXED recording — #392 fills `source_data`, so board columns 10/11 carry the
#: unit's own quality/defense, which is this module's default. `m3_ref_v2` is the
#: pre-#392 corpus and only compares under the legacy 4/4 reading; gating it
#: without that knob would be comparing two different encoders.
REF_CORPORA = (
    (Path(os.path.expanduser("~/selfplay_out/m3_ref_v3")), False),
    (Path(os.path.expanduser("~/selfplay_out/m3_ref_v2")), True),
)
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
GATE_SEEDS = range(27, 47)


@pytest.fixture(autouse=True)
def _legacy_core_selfplay_loader():
    """NML-1098: every corpus this module gates against was recorded by
    `tools/core_selfplay.gd`, whose loader reads rule names out of upgrade LABEL
    text and never sees a list's items, item grants or auras. The trainer now
    follows the TABLE, so a seed-for-seed replay of THOSE games must ask the
    loader for THAT reading; otherwise this gate would be measuring the loader
    fix instead of the search loop, and the fix has its own gate in
    `tools/loader_gate.py`."""
    before = list_to_profile.LEGACY_CORE_SELFPLAY
    list_to_profile.LEGACY_CORE_SELFPLAY = True
    yield
    list_to_profile.LEGACY_CORE_SELFPLAY = before


#: `board_rows` writes one row per living unit, then one per objective (type 3),
#: then the single game-state row (type 4) — battle_sim.gd:210-283.
OBJECTIVE_ROW = 3
GAME_STATE_ROW = 4


def read_acts(name: str):
    lines = [json.loads(l) for l in open(FIXTURES / name, encoding="utf-8")]
    return lines[0], lines[1:]


def loaded(name: str = "acts_25.jsonl"):
    header, acts = read_acts(name)
    core = nml_core.load(str(REPO))
    core.set_header(header)
    return core, acts


# ------------------------------------------------------------- the encoder ---


def test_board_rows_are_one_per_living_unit_then_the_markers_then_the_game():
    """The row LAYOUT of `BattleSim.board_rows` — the shape the v5 schema is,
    checked against the state it was built from rather than against itself."""
    core, acts = loaded()
    state = core.state_of(acts[0]["state"])
    plain = state.plain()
    alive = [k for k, u in plain["units"].items() if int(u["alive"]) > 0]
    rows = core.board_rows(state)
    markers = len(plain.get("objectives", []))
    assert len(rows) == len(alive) + markers + 1
    for row in rows[: len(alive)]:
        assert row[0] in (1, 2), "a unit row carries its player in column 0"
        assert len(row) == 21 + 2 * row[20], "column 20 counts the (slot, value) pairs"
    for row in rows[len(alive) : len(alive) + markers]:
        assert row[0] == OBJECTIVE_ROW and len(row) == 21
    assert rows[-1][0] == GAME_STATE_ROW
    assert rows[-1][1] == plain["round"] and rows[-1][2] == plain["rounds_total"]


def test_board_row_indices_name_the_rows_board_rows_wrote():
    """The judge-bench sidecar: the roster index of every row, same filter and
    same order — so tooling maps a row back to a roster name."""
    core, acts = loaded()
    for act in acts[:5]:
        state = core.state_of(act["state"])
        keys = state.keys()
        plain = state.plain()
        ids = core.board_row_indices(state)
        assert ids == [i for i, k in enumerate(keys) if int(plain["units"][k]["alive"]) > 0]
        rows = core.board_rows(state)
        for row, i in zip(rows, ids):
            assert row[0] == int(plain["units"][keys[i]]["player"])


def test_a_dead_unit_keeps_its_roster_slot_but_loses_its_row():
    """`board_row_indices` exists because the two lists are NOT the same length:
    a wiped-out unit keeps its slot in the roster and drops out of the rows."""
    core, acts = loaded()
    seen = False
    for act in acts:
        state = core.state_of(act["state"])
        ids = core.board_row_indices(state)
        if len(ids) < state.units:
            seen = True
            assert core.board_rows(state)[len(ids)][0] == OBJECTIVE_ROW
            assert ids != list(range(state.units))
            break
    if not seen:
        pytest.skip("no recorded activation in this fixture has a dead unit")


def test_an_unknown_rule_is_collected_loudly_and_never_given_a_slot():
    """Slot assignment only ever happens CENTRALLY, at collect time. A rule the
    committed vocabulary does not carry must therefore be reported, not numbered
    — and the arena fixture is the case that proves it: four of its rule names
    are outside the vocabulary ("built from ALL 43 CDN factions x sizes", which
    is not the same as every rule an item can grant).

    The trainer's own armies collect NOTHING; that half is held by the corpus
    gate, which compares the result's `unknown_rules` against the Godot file."""
    core, acts = loaded()
    rows = core.board_rows(core.state_of(acts[0]["state"]))
    vocab = json.loads((REPO / "data" / "encoder_rule_vocab_v1.json").read_text())
    assert len(vocab["unit"]) and len(vocab["weapon"]) and len(vocab["spell"])
    unknown = core.unknown_rules()
    assert unknown, "this fixture must exercise the collector, or it proves nothing"
    known = set(vocab["unit"]) | set(vocab["weapon"])
    for name in unknown:
        assert name not in known and not name.startswith("spell:") or name[6:] not in set(
            vocab["spell"]
        )
    # And nothing they could have been numbered as reached a row: every slot a
    # unit row carries is a slot the committed vocabulary defines.
    slots = set(range(len(vocab["unit"])))
    slots |= {200 + i for i in range(len(vocab["weapon"]))}
    slots |= {300 + i for i in range(len(vocab["spell"]))}
    for row in rows:
        if row[0] not in (1, 2):
            continue
        for i in range(row[20]):
            assert row[21 + 2 * i] in slots


def test_red_the_legacy_quality_column_is_a_different_corpus():
    """RED-GREEN. Board columns 10 and 11 come off the `GameUnit`'s
    `source_data` (battle_sim.gd:233-234). `tools/core_selfplay.gd` fills those
    stats since #392, so the DEFAULT here is the unit's own quality/defense; the
    blank `OPRApiClient.OPRUnit` 4/4 of every pre-#392 row is reachable only
    through the legacy override. This proves the two readings differ on this
    data — otherwise neither the default nor the override would be tested."""
    core, acts = loaded()
    state = core.state_of(acts[0]["state"])
    live = [(r[10], r[11]) for r in core.board_rows(state) if r[0] in (1, 2)]
    assert any(qd != (4, 4) for qd in live), "this data is all 4/4 — nothing to tell apart"
    core.set_encoder_source_qd(sp.SOURCE_DATA_QUALITY, sp.SOURCE_DATA_DEFENSE)
    stale = [(r[10], r[11]) for r in core.board_rows(state) if r[0] in (1, 2)]
    assert all(qd == (4, 4) for qd in stale)
    assert live != stale
    core.clear_encoder_source_qd()
    assert [(r[10], r[11]) for r in core.board_rows(state) if r[0] in (1, 2)] == live


def test_features_carry_the_whole_eval_vector_from_the_players_seat():
    """`AiMissionEval.features(state, player, reply_threat, true)` — the RICH
    vector, and it is a SEAT: the two sides' halves swap when the seat does."""
    core, acts = loaded()
    state = core.state_of(acts[0]["state"])
    f1 = core.features(state, 1)
    f2 = core.features(state, 2)
    assert f1["my_units"] == f2["their_units"] and f2["my_units"] == f1["their_units"]
    assert f1["my_wounds"] == f2["their_wounds"]
    assert 0.0 < f1["round_frac"] <= 1.0
    assert set(f1) == set(f2) and len(f1) == 30


# --------------------------------------------------------- the fork machine ---


def test_refresh_round_clears_the_two_flags_and_nothing_else():
    """The fork's per-round reset (core_selfplay.gd:382-386) — round number,
    `activated`, `fatigued`. Deliberately NOT the game's own round start: an
    imagined round inherits the last one's spell modifiers and its tokens."""
    core, acts = loaded()
    state = core.state_of(acts[-1]["state"])
    before = state.plain()
    after = state.refresh_round(before["round"] + 1).plain()
    assert after["round"] == before["round"] + 1
    for k, u in after["units"].items():
        assert u["activated"] is False and u["fatigued"] is False
        assert u["casts"] == before["units"][k]["casts"]
        assert u["mods"] == before["units"][k]["mods"]
        assert u["positions"] == before["units"][k]["positions"]


def test_policy_step_answers_for_a_live_side_and_declines_a_dry_one():
    """`AiPlanner._policy_step` through the seam — the cheap brain both fork
    branches continue with. A side with no living un-activated unit is `None`,
    which is what ends a fork round."""
    core, acts = loaded()
    state = core.state_of(acts[0]["state"])
    for player in (1, 2):
        if state.pool(player):
            action = core.policy_step(state, player, True)
            assert action is not None and action["unit"] in state.pool(player)
    plain = state.plain()
    for u in plain["units"].values():
        u["activated"] = True
    dry = core.state_of(plain)
    assert core.policy_step(dry, 1, True) is None
    assert core.policy_step(dry, 2, True) is None


def test_a_fork_playout_reports_the_markers_and_ends_the_game():
    """`_fork_playout` core_selfplay.gd:363-396 — one branch to GAME END, the
    answer being the final marker count per side. Three markers, so the two
    counts can never exceed them."""
    core, acts = loaded()
    state = core.state_of(acts[0]["state"])
    markers = len(state.plain().get("objectives", []))
    action = core.policy_step(state, 1, True)
    if action is None:
        pytest.skip("the fixture's first activation has no candidate for p1")
    out = sp._fork_playout(core, state, action, 1, state.round, [0] * markers, nml_core.Rng(7))
    assert set(out) == {"p1", "p2"}
    assert 0 <= out["p1"] + out["p2"] <= markers


def test_the_sidecar_generator_is_local_and_the_skip_shifts_it():
    """`_local_rng` — the red-proof knob. `skip` advances the stream and nothing
    else, so a shifted sidecar sees different dice from the same seed."""
    plain = nml_core.Rng(11)
    assert sp._local_rng(11, 0).state == plain.state
    plain.randf()
    assert sp._local_rng(11, 1).state == plain.state


# --------------------------------------------------------------- the gate ----


def _corpus():
    """The newest recorded corpus on this machine, and the encoder reading it was
    written under. `(None, False)` when there is none."""
    if BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists():
        for ref, legacy in REF_CORPORA:
            if ref.is_dir() and any(
                (ref / ("core_s%d.json" % s)).exists() for s in GATE_SEEDS
            ):
                return ref, legacy
    return None, False


REF_DIR, LEGACY_SOURCE_QD = _corpus()


def _gate_seeds():
    if REF_DIR is None:
        return []
    return [s for s in GATE_SEEDS if (REF_DIR / ("core_s%d.json" % s)).exists()]


def _play(core, seed: int, **kw):
    kw.setdefault("legacy_source_qd", LEGACY_SOURCE_QD)
    return sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, **kw)


@pytest.mark.skipif(not _gate_seeds(), reason="no recorded core_selfplay reference on this machine")
def test_the_python_result_file_equals_the_godot_one_field_by_field():
    """THE GATE. Every held field of `core_s<seed>.json` — see
    `tools/sidecar_gate.py` for the comparison rules and the excluded list."""
    core = nml_core.load(str(REPO))
    seeds = _gate_seeds()
    bad = []
    pairs = forks = 0
    for seed in seeds:
        with open(REF_DIR / ("core_s%d.json" % seed), encoding="utf-8") as f:
            ref = json.load(f)
        got = _play(core, seed)
        np, nf = gate.sidecar_shape(got)
        pairs += np
        forks += nf
        d = gate.compare(ref, got, 1e-9)
        if d:
            bad.append((seed, d[0]))
    assert not bad, "seeds that diverged: %s" % bad[:3]
    print(
        "GATE M3-9: %d/%d seeds field-for-field equal (%d pair, %d fork blocks)"
        % (len(seeds), len(seeds), pairs, forks)
    )


@pytest.mark.skipif(not _gate_seeds(), reason="no recorded core_selfplay reference on this machine")
def test_red_a_shifted_sidecar_dice_stream_moves_the_counterfactuals():
    """RED PROOF for the gate: every sidecar generator advanced by three draws
    before its clone is resolved — same seeds, same clone points, same played
    game, only the counterfactual dice moved. Every seed must diverge, or the
    gate is not reading the sidecars at all."""
    core = nml_core.load(str(REPO))
    seeds = _gate_seeds()
    same = []
    for seed in seeds:
        with open(REF_DIR / ("core_s%d.json" % seed), encoding="utf-8") as f:
            ref = json.load(f)
        if not gate.compare(ref, _play(core, seed, sidecar_skip=3), 1e-9):
            same.append(seed)
    assert not same, "seeds that survived a shifted sidecar stream: %s" % same
    print("RED PROOF: %d/%d seeds diverge on a shifted sidecar stream" % (len(seeds), len(seeds)))


@pytest.mark.skipif(not _gate_seeds(), reason="no recorded core_selfplay reference on this machine")
def test_the_sidecars_change_no_game():
    """The whole claim of the pair/fork design: they resolve on CLONES under
    generators of their own, so the PLAYED game is die-for-die the same with
    them on and off."""
    core = nml_core.load(str(REPO))
    for seed in _gate_seeds():
        on = _play(core, seed)
        off = _play(core, seed, sidecars=False)
        assert on["winner"] == off["winner"] and on["vp"] == off["vp"]
        assert on["objectives"] == off["objectives"]
        picks = lambda r: [(x["round"], x["side"], x["unit"], x["kind"]) for x in r["planner_positions"]]  # noqa: E731
        assert picks(on) == picks(off), "seed %d: the sidecars moved the game" % seed


@pytest.mark.skipif(not _gate_seeds(), reason="no recorded core_selfplay reference on this machine")
def test_red_the_sidecar_generators_do_roll_dice():
    """RED half of the test above: "unchanged" would be worthless if the
    sidecars never drew anything. Shifting their stream must move the blocks
    they wrote — on the very seeds the test above calls unchanged."""
    core = nml_core.load(str(REPO))
    moved = 0
    for seed in _gate_seeds():
        plain = _play(core, seed)
        shifted = _play(core, seed, sidecar_skip=3)
        for a, b in zip(plain["planner_positions"], shifted["planner_positions"]):
            if a.get("fork") != b.get("fork") or a.get("pair") != b.get("pair"):
                moved += 1
                break
    assert moved == len(_gate_seeds()), "only %d seeds drew a sidecar die" % moved
