"""R9a fog of war on the Rust self-play path (plan G step 11).

Both seats play on ONE state. In a Smash & Grab game (secret markers: one relic, one trap, the rest
empty) the ATTACKER must not know which marker is which until it turns one up, so every state a seat
plans on must be ITS view of the board: the attacker's view of an unrevealed secret marker carries no
`secret` / `carry` / `carried_by` and says `secret_hidden` instead.

`tools/core_selfplay.gd` did this in `_seat_view` (test/core_selfplay_fog_test.gd, 3 tests). The Python
harness did NOT: `_pick_for` handed the shared state straight to `plan_with_rollout`, so the attacker's
planner read the relic (found 18.11.: the attacker's value moved from 0.267 to 0.183 when the relic and
the trap swapped places). `selfplay._seat_view` is the fix.

Named twins of the GD suite:
  test_the_attacker_seat_cannot_read_a_hidden_marker   <- test_the_attacker_seat_cannot_read_a_hidden_marker
  test_the_defender_seat_keeps_its_secrets             <- test_the_defender_seat_keeps_its_secrets
  test_a_game_without_secret_markers_gets_the_same_object
                                                       <- test_a_game_without_secret_markers_gets_the_same_dict

RED (manual, how each group was seen failing; see the PR): `_seat_view` returning `state` untouched fails
the view tests and the value/pick tests; removing the `_seat_view` call from `_pick_for` fails only the
planner-boundary tests; removing it from `_fork_run_activations` fails only the fork test; emptying
`FOG_SCORINGS` fails the catalog pin.
"""

from __future__ import annotations

import copy
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
LISTS = Path(os.path.expanduser(os.environ.get("NML_AI_LISTS_DIR", "")))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
needs_lists = pytest.mark.skipif(
    not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()), reason="needs the terrain bank + 1000pt lists"
)
KINDS = ["relic", "trap", ""]
SWAPPED = ["trap", "relic", ""]  # the same three spots, the relic and the trap exchanged


@pytest.fixture(scope="module")
def world():
    """A core on acts_25's header plus its first recorded board, made a Smash & Grab game: slot 1
    attacks, three markers sit on the centre line (the objectives the fixture already carries)."""
    lines = (FIXTURES / "acts_25.jsonl").read_text().splitlines()
    header = json.loads(lines[0])
    plain = json.loads(lines[1])["state"]
    core = nml_core.load(str(REPO))
    core.set_header(header)
    plain.update(round=1, rounds_total=4, attacker=1, scoring="extract")
    return core, plain


def _state(world, kinds, *, revealed=()):
    """The shared state with `kinds` assigned to the three markers; `revealed` indexes turned-up ones."""
    core, base = world
    plain = copy.deepcopy(base)
    plain["markers_meta"] = []
    for i, kind in enumerate(kinds):
        marker = {"secret": kind, "revealed": i in revealed}
        if kind == "relic":
            marker.update(carry=True, carried_by=-1)
        plain["markers_meta"].append(marker)
    return core.state_of(plain)


def _markers(state):
    return state.plain()["markers_meta"]


# ---------------------------------------------------------------- the view ----


def test_the_attacker_seat_cannot_read_a_hidden_marker(world):
    core, _ = world
    shared = _state(world, KINDS)
    view = sp._seat_view(core, shared, 1)
    for marker in _markers(view):
        for key in ("secret", "carry", "carried_by"):
            assert key not in marker
        assert marker["secret_hidden"] is True
    assert [m["secret"] for m in _markers(shared)] == KINDS  # the shared state is untouched


def test_the_defender_seat_keeps_its_secrets(world):
    core, _ = world
    shared = _state(world, KINDS)
    view = sp._seat_view(core, shared, 2)
    assert view is shared
    assert [m["secret"] for m in _markers(view)] == KINDS
    assert _markers(view)[0]["carry"] is True


def test_a_game_without_secret_markers_gets_the_same_object(world):
    core, base = world
    plain = copy.deepcopy(base)
    plain["markers_meta"] = [{"carry": True, "carried_by": -1}]
    carry_only = core.state_of(plain)
    assert sp._seat_view(core, carry_only, 1) is carry_only
    plain.pop("markers_meta")
    bare = core.state_of(plain)
    assert sp._seat_view(core, bare, 1) is bare
    plain.update(scoring="end", markers_meta=[{"secret": "relic", "revealed": False}])
    other_scoring = core.state_of(plain)  # a scoring that never carries secret markers is not even read
    assert sp._seat_view(core, other_scoring, 1) is other_scoring


def test_a_marker_the_attacker_turned_up_keeps_its_kind(world):
    core, _ = world
    shared = _state(world, KINDS, revealed=(0,))  # the relic is up, the other two are not
    marks = _markers(sp._seat_view(core, shared, 1))
    assert marks[0]["secret"] == "relic" and marks[0]["carry"] is True and "secret_hidden" not in marks[0]
    assert "secret" not in marks[1] and "secret" not in marks[2]
    allup = _state(world, KINDS, revealed=(0, 1, 2))
    assert sp._seat_view(core, allup, 1) is allup  # nothing hidden left: the same object


def test_the_view_differs_from_the_state_in_the_markers_only(world):
    core, _ = world
    shared = _state(world, KINDS)
    shared = core.restamp_los(shared) if core.has_terrain() else shared  # the sight seams must survive too
    view = sp._seat_view(core, shared, 1)
    a, b = shared.plain(), view.plain()
    assert a.pop("markers_meta") != b.pop("markers_meta")
    assert a == b


def test_every_secret_mission_is_scored_by_a_fogged_scoring():
    catalog = json.loads((REPO / "assets" / "solo" / "missions.json").read_text())["missions"]
    secret = {k: v["scoring"] for k, v in catalog.items() if (v.get("markers") or {}).get("secret")}
    assert secret, "the catalog has no secret-marker mission any more: retire the gate"
    assert all(scoring in sp.FOG_SCORINGS for scoring in secret.values()), secret


# --------------------------------------------------- what the planner reads ----


def test_the_attackers_value_cannot_tell_the_relic_from_the_trap(world):
    core, _ = world
    a, b = _state(world, KINDS), _state(world, SWAPPED)
    inc = [0.0] * a.units
    # the leak is a real signal: on the shared state the attacker's value moves with the kinds ...
    assert core.score_hand_incoming(a, 1, inc) != core.score_hand_incoming(b, 1, inc)
    # ... and through its own view it does not
    va, vb = sp._seat_view(core, a, 1), sp._seat_view(core, b, 1)
    assert core.score_hand_incoming(va, 1, inc) == core.score_hand_incoming(vb, 1, inc)
    assert core.score(va, 1) == core.score(vb, 1)


class _Spy:
    """The real core with the planner entries recorded: which seat asked, and the markers it was handed."""

    def __init__(self, core):
        self._core, self.plans, self.steps = core, [], []

    def __getattr__(self, name):
        return getattr(self._core, name)

    def plan_with_rollout(self, state, player, *args, **kwargs):
        self.plans.append((player, _markers(state)))
        return self._core.plan_with_rollout(state, player, *args, **kwargs)

    def policy_step(self, state, player, *args, **kwargs):
        self.steps.append((player, _markers(state)))
        return self._core.policy_step(state, player, *args, **kwargs)


def test_pick_for_hands_each_seat_its_own_view(world):
    core, _ = world
    spy = _Spy(core)
    shared = _state(world, KINDS)
    assert sp._pick_for(spy, shared, 1) and sp._pick_for(spy, shared, 2)
    (seat_a, seen_a), (seat_d, seen_d) = spy.plans
    assert (seat_a, seat_d) == (1, 2)
    assert all("secret" not in m and "carry" not in m for m in seen_a), seen_a  # the attacker: fogged
    assert [m["secret"] for m in seen_d] == KINDS  # the defender: the truth


def test_the_attackers_pick_does_not_depend_on_the_hidden_kinds(world):
    core, _ = world
    a, b = _state(world, KINDS), _state(world, SWAPPED)
    pa, pb = sp._pick_for(core, a, 1), sp._pick_for(core, b, 1)
    assert pa["action"] == pb["action"] and pa["expectation"] == pb["expectation"]


def test_the_fork_continuation_steps_each_seat_on_its_view_too(world):
    core, _ = world
    spy = _Spy(core)
    sp._fork_run_activations(spy, _state(world, KINDS), 1, nml_core.Rng(7))
    seen = {seat: marks for seat, marks in spy.steps}
    assert set(seen) == {1, 2}, "the fork must step both seats"
    for seat, marks in spy.steps:
        if seat == 1:
            assert all("secret" not in m for m in marks), marks
        else:
            assert [m["secret"] for m in marks] == KINDS


@needs_lists
def test_a_played_smash_and_grab_game_never_shows_the_attacker_a_hidden_kind():
    """The whole path, not the helpers: every planner call of a real game, from the seat that asked."""
    spy = _Spy(nml_core.load(str(REPO)))
    res = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, spy, mission="smash_and_grab", top_k=2, horizon=1)
    attacker = 1 if res["mission"]["role_p1"] == "attacker" else 2

    def unrevealed_kinds(marks):
        return [m for m in marks if "secret" in m and not m.get("revealed")]

    by_seat = {seat: [unrevealed_kinds(marks) for s, marks in spy.plans if s == seat] for seat in (1, 2)}
    assert any(spy_marks for spy_marks in by_seat[3 - attacker]), "the defender never saw a kind: the spy is blind"
    assert not any(by_seat[attacker]), "the attacker's planner read a hidden marker kind"
