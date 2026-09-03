"""The SEARCH A/B seam — per-seat search depth on the fast core's selfplay
path (`deep_player` / `deep_top_k` / `deep_horizon` on `play_game`).

One seat of a paired game must be able to search DEEPER than the other
(600 paired games answering "does more search make the AI stronger?"). The
implementation hands the deep seat's activations a SECOND core built off the
same header payload with the deep pair in place of the base pair. Three
proofs, the knob-wiring pattern (`test_explore_knob.py`,
`test_deployment_knob.py`):

  * `deep_player=0` (the default, and passing it explicitly) plays the
    BYTE-IDENTICAL game the pre-knob code played — vintage-pinned raw digest,
    stamp set included (no stamp exists on this path);
  * a deep game whose deep pair EQUALS the resolved base pair digests
    byte-identically to that pin — the proof the second core really sees the
    same header (same profiles, terrain and every other knob);
  * `deep_player=2` with a deeper pair plays a DIFFERENT game (compared
    without the stamps, so stamps alone cannot pass) and stamps both seats'
    resolved depths as `knobs_by_seat` (the NML-1147a pattern: the stamp
    rides only a game whose deep pair parted from the base pair).
"""

from __future__ import annotations

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

#: the explore-knob test's fixture game: seed 27, FAST knobs, fresh core.
SEED = 27
FAST = {"top_k": 2, "horizon": 1}
#: raw `sp.result_digest` at HEAD 08e80b90 (deep_player absent), taken by
#: `.forge/digest_probe.py` BEFORE the seam landed — the pre-change game.
#: Re-pinned after PR #600 (`dangerous_end_morale`, default True) landed and
#: moved this seed's game under `LEGACY_FIDELITY_KNOBS` too — these tests are
#: about deep_player/menu_los/menu_wide, not that knob, so the pin just
#: follows today's other defaults rather than pinning a growing list of
#: unrelated ones.
SEED_27_FAST_DIGEST = "86249fc93149f8d49e74f19fbef634e985f3224710aba39d4248f535f8c94504"


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _digest_without_stamps(result: dict) -> str:
    """`sp.result_digest` with both stamp fields stripped (`knobs` grows with
    mode metadata, `knobs_by_seat` rides only a parted deep pair) — so a
    comparison cannot pass on stamps alone."""
    return sp.result_digest(
        {k: v for k, v in result.items() if k not in ("knobs", "knobs_by_seat")}
    )


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_default_is_byte_identical():
    """`deep_player=0` — passed and defaulted — must leave the pre-knob game
    untouched: same seed, RAW result digest equal to the vintage pin."""
    # W5a: pinned to the legacy fidelity knobs — this test is about
    # deep_player, not the shipped-defaults flip, so it keeps the ORIGINAL
    # vintage pin instead of moving it for an unrelated reason.
    core = nml_core.load(str(REPO))
    base = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    explicit = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                            deep_player=0, **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(base) == SEED_27_FAST_DIGEST
    assert sp.result_digest(explicit) == SEED_27_FAST_DIGEST


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_equal_knobs_digest_byte_identical():
    """A deep game whose deep pair EQUALS the base pair must digest exactly
    what the pre-change code digested: the second core is built and planned
    on, so the pin can only hold if that core really sees the same header."""
    # W5a: pinned to the legacy fidelity knobs — see test_deep_default_is_
    # byte_identical above.
    core = nml_core.load(str(REPO))
    r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                     deep_player=1, deep_top_k=2, deep_horizon=1,
                     **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(r) == SEED_27_FAST_DIGEST
    assert "knobs_by_seat" not in r  # the stamp rides only a parted pair


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_player_stamps_knobs_by_seat():
    """MUTATION GUARD: `deep_player=2` with a deeper pair must play a
    DIFFERENT game than the base (stamps stripped) and stamp both seats'
    resolved depths — p1 the base pair, p2 the deep pair."""
    core = nml_core.load(str(REPO))
    base = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    deep = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        deep_player=2, deep_top_k=4, deep_horizon=2, **FAST)
    assert _digest_without_stamps(base) != _digest_without_stamps(deep)
    assert deep["knobs_by_seat"] == {
        "p1": {"top_k": 2, "horizon": 1},
        "p2": {"top_k": 4, "horizon": 2},
    }
    assert "knobs_by_seat" not in base


# ------------------------------- NML-1161b: the PER-SEAT menu knob ---
# `deep_menu_los` is the first knob of this seam that is not a search depth.
# It works because `Tuning` is derived per CORE (`plan::tuning_of` off the
# header) and `_play_round` plans the acting seat on ITS core while both seats
# still RESOLVE on the base one — so the two seats part in the MENU and in
# nothing else, which is what a strength A/B needs.

ACTS = REPO / "core" / "nml-core" / "tests" / "fixtures" / "acts_25.jsonl"


def _fixture_header_and_act() -> tuple[dict, dict]:
    """The recorded oracle's header line and its first act line."""
    import json

    with open(ACTS, encoding="utf-8") as f:
        header = json.loads(f.readline())
        act = json.loads(f.readline())
    return header, act


def _core_with_menu_los(header: dict, on: bool):
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": header["profiles"], "terrain": header["terrain"],
                     "knobs": dict(header["knobs"], menu_los=on)})
    return core


def test_two_cores_give_two_menus_on_one_state():
    """RED for the per-seat seam: ONE state, TWO cores that differ only in
    `menu_los`, and the menus must part. The state gets a `los_pairs` matrix
    that blocks every ordered pair — an arena recording carries none, which is
    exactly why the recorded corpus cannot show this and self-play can (it
    stamps that matrix at `tools/core_selfplay.gd:675`).

    Without the per-seat wiring both cores read the same `Tuning` and this
    returns two identical menus."""
    header, act = _fixture_header_and_act()
    plain = act["state"]
    n = len(plain["units"])
    plain["los_pairs"] = ["0" * n] * n
    open_core = _core_with_menu_los(header, False)
    gated_core = _core_with_menu_los(header, True)
    st_open, st_gated = open_core.state_of(plain), gated_core.state_of(plain)
    parted = 0
    shots_open = shots_gated = 0
    for key in act["pool"]:
        a = open_core.candidates(st_open, key)
        b = gated_core.candidates(st_gated, key)
        shots_open += sum(1 for c in a if c.get("shoot"))
        shots_gated += sum(1 for c in b if c.get("shoot"))
        parted += a != b
    print("NML-1161b two cores, one state: %d of %d menus part; shoot candidates "
          "%d open vs %d gated" % (parted, len(act["pool"]), shots_open, shots_gated))
    assert shots_open > 0, "the fixture has to offer shots for this to say anything"
    assert shots_gated == 0, "a fully blocked matrix must leave the gated seat no target"
    assert parted > 0, "the two seats got the same menu — the per-seat wiring is cut"


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_menu_los_default_is_byte_identical():
    """`deep_menu_los=None` (every caller written before this) leaves the deep
    core on the base value: the equal-pair pin still holds, stamp included."""
    # W5a: pinned to the legacy fidelity knobs — see test_deep_default_is_
    # byte_identical above.
    core = nml_core.load(str(REPO))
    r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                     deep_player=1, deep_top_k=2, deep_horizon=1,
                     **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(r) == SEED_27_FAST_DIGEST
    assert "knobs_by_seat" not in r


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_menu_los_parts_the_two_seats_on_the_trainers_own_sight():
    """MUTATION GUARD: equal search pairs, `los="unit"` (the sight self-play
    has always had — an empty `los` row and a centre-to-centre `los_pairs`),
    the DEEP seat on the LOS-aware menu and the BASE seat on the old one. The
    game must part, and both seats' resolved `menu_los` must be stamped."""
    # W5a: every OTHER knob pinned to legacy (`LEGACY_FIDELITY_KNOBS` already
    # carries `los="unit"`/`menu_los="planner"`) — the split's p2 stays
    # "planner" (asserted below), whichever way play_game()'s own defaults
    # move next.
    core = nml_core.load(str(REPO))
    both = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        deep_player=1, deep_top_k=2, deep_horizon=1,
                        dice="table", **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    split = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                         deep_player=1, deep_top_k=2, deep_horizon=1,
                         dice="table", deep_menu_los="resolve",
                         **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert _digest_without_stamps(both) != _digest_without_stamps(split)
    assert split["knobs_by_seat"] == {
        "p1": {"top_k": 2, "horizon": 1, "menu_los": "resolve"},
        "p2": {"top_k": 2, "horizon": 1, "menu_los": "planner"},
    }
    assert "knobs_by_seat" not in both


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_the_per_seat_menu_knob_is_a_no_op_under_los_model():
    """AND THE LIMIT, measured rather than argued: under `los="model"` (#589)
    the per-unit `los` row and `los_pairs` are the SAME per-model matrix, so
    `sees` already answers what `_los_clear` answers and the menu gate adds
    nothing. The two seats then play a BYTE-IDENTICAL game however they are
    split — which is why a `menu_los` strength A/B has to run at `los="unit"`,
    and why on a `los="model"` corpus this rung is a redundancy lock rather
    than a strength lever."""
    core = nml_core.load(str(REPO))
    both = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        deep_player=1, deep_top_k=2, deep_horizon=1,
                        dice="table", los="model", **FAST)
    split = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                         deep_player=1, deep_top_k=2, deep_horizon=1,
                         dice="table", los="model", deep_menu_los="resolve", **FAST)
    assert _digest_without_stamps(both) == _digest_without_stamps(split)


# W1 — `deep_menu_wide` is the first per-seat knob with a RESOLVE half, and that
# is a trap the `menu_los` seam does not have: `_play_round` plans the acting
# seat on ITS core but RESOLVES every activation on the BASE one. A deep seat
# playing the wide menu therefore hands its ADVANCE+shoot to a core that would
# decline it (`Unsupported::MovedShootLos`) and the whole game dies mid-round —
# which is exactly how the first A/B run failed. The permission is
# `Knobs::moved_shoot`, granted to BOTH cores as soon as EITHER seat may offer
# a moving shot; without it this test raises instead of asserting.


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_menu_wide_plays_and_parts_the_two_seats():
    """A per-seat wide-menu game must PLAY — the BASE core has to resolve the
    DEEP seat's moving shot — and both seats' resolved `menu_wide` is stamped."""
    # W5a: every OTHER knob pinned to legacy (`LEGACY_FIDELITY_KNOBS` already
    # carries `los="unit"`/`menu_wide="off"`) — the split's p2 stays "off"
    # (asserted below), whichever way play_game()'s own defaults move next.
    core = nml_core.load(str(REPO))
    both = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        deep_player=1, deep_top_k=2, deep_horizon=1,
                        dice="table", **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    split = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                         deep_player=1, deep_top_k=2, deep_horizon=1,
                         dice="table", deep_menu_wide="table",
                         **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert _digest_without_stamps(both) != _digest_without_stamps(split)
    assert split["knobs_by_seat"] == {
        "p1": {"top_k": 2, "horizon": 1, "menu_wide": "table"},
        "p2": {"top_k": 2, "horizon": 1, "menu_wide": "off"},
    }
    assert "knobs_by_seat" not in both


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_menu_wide_default_is_byte_identical():
    """`deep_menu_wide=None` (every caller written before this) leaves both
    seats on the base value, so the game is the one it always was — the
    permission bit alone must move nothing."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                     deep_player=1, deep_top_k=2, deep_horizon=1,
                     dice="table", los="unit", **FAST)
    b = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                     deep_player=1, deep_top_k=2, deep_horizon=1,
                     dice="table", los="unit", deep_menu_wide=None, **FAST)
    assert _digest_without_stamps(a) == _digest_without_stamps(b)
