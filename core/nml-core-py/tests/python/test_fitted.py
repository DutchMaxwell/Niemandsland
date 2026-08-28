"""NML-1142 — the FITTED eval through the Python seam.

`core/nml-core/src/fitted.rs` carries its own arithmetic tests; these hold the
BINDING: that a net loads only through the GDScript's own selftest gate, that
arming one actually moves `Core.score` by the blend the table blends, that the
red-proof `scale` is load-bearing, and that `fit_mode` is decided per
ACTIVATION even though the net is per process.

The net here is small enough to predict by hand: one hidden unit that fires on
the canonical MINE flag and doubles, a head that passes the own-side pool
through. Every own living unit embeds to 2, so their MEAN is 2 whatever the
board looks like, the head reads exactly that, and the fitted half is
`sigmoid(2)` for any state with a living own unit. The blend is then arithmetic,
not a guess.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import pytest

import nml_core

REPO_ROOT = Path(__file__).resolve().parents[4]
ACTS = REPO_ROOT / "core" / "nml-core" / "tests" / "fixtures" / "acts_25.jsonl"

#: What the hand-built net answers for any state with at least one living own
#: unit: relu(relu(1 * 1) * 2) = 2 per own unit, mean 2, head weight 1.
FIT = 1.0 / (1.0 + math.exp(-2.0))
#: `AiMissionEval.FIT_BLEND_DEFAULT` ai_mission_eval.gd:330.
BLEND = 0.5
#: A rule name the committed vocabulary will never carry.
BOGUS = "Totally Not A Rule"


def tiny_net() -> dict:
    """An encoder net with `slots = {}`, so a canonical row is 22 columns wide
    and `unit_w1` is 22x1."""
    unit_w1 = [[0.0] for _ in range(22)]
    unit_w1[0][0] = 1.0
    head_w1 = [[0.0] for _ in range(3 + 3 + 1)]
    head_w1[0][0] = 1.0
    unit_row = [0.0] * 21
    unit_row[0] = 1.0  # a player-1 unit
    obj_row = [0.0] * 21
    obj_row[0] = 3.0  # an objective marker
    return {
        "keys": ["round_frac"],
        "mu": [0.0],
        "sd": [1.0],
        "slots": {},
        "unit_w1": unit_w1,
        "unit_b1": [0.0],
        "unit_w2": [[2.0]],
        "unit_b2": [0.0],
        "head_w1": head_w1,
        "head_b1": [0.0],
        "head_w2": [1.0],
        "head_b2": 0.0,
        "selftest": {
            "board": [unit_row, obj_row],
            "side": 1,
            "features": [0.0],
            "expected": FIT,
        },
    }


def write_net(tmp_path: Path, net: dict) -> str:
    p = tmp_path / "net.json"
    p.write_text(json.dumps(net), encoding="utf-8")
    return str(p)


@pytest.fixture
def act():
    """The header and the first activation of the in-repo act fixture."""
    lines = [json.loads(x) for x in ACTS.read_text().splitlines() if x.strip()]
    return lines[0], lines[1]


def cored(head) -> nml_core.Core:
    core = nml_core.load(str(REPO_ROOT))
    core.set_header(
        {"profiles": head["profiles"], "terrain": head.get("terrain"),
         "knobs": head.get("knobs", {})}
    )
    return core


def test_the_loader_gate_refuses_a_drifted_net(tmp_path, act):
    head, _ = act
    core = cored(head)
    shape = core.load_net(write_net(tmp_path, tiny_net()))
    assert shape == {"slots": 0, "keys": 1, "hidden": 1}
    assert core.has_net()

    # RED: the same net claiming a different answer must not load...
    bad = tiny_net()
    bad["selftest"]["expected"] = 0.5
    with pytest.raises(Exception, match="selftest"):
        cored(head).load_net(write_net(tmp_path, bad))
    # ...and neither may one that carries no selftest block at all.
    none = tiny_net()
    del none["selftest"]
    with pytest.raises(Exception, match="missing"):
        cored(head).load_net(write_net(tmp_path, none))
    # A net slotted against another rule vocabulary is refused on that alone.
    stale = tiny_net()
    stale["vocab_version"] = nml_core.RULE_VOCAB_VERSION + 1
    with pytest.raises(Exception, match="vocabulary"):
        cored(head).load_net(write_net(tmp_path, stale))


def test_the_net_moves_the_score_by_exactly_the_blend(tmp_path, act):
    head, a = act
    player = int(a["player"])
    hand_core = cored(head)
    hand = hand_core.score(hand_core.state_of(a["state"]), player)

    core = cored(head)
    core.load_net(write_net(tmp_path, tiny_net()))
    got = core.score(core.state_of(a["state"]), player)
    assert got == pytest.approx((1.0 - BLEND) * hand + BLEND * FIT, abs=1e-12)
    assert got != hand  # the net is doing something, not decorating

    # The cheap leaf takes the same blend — one core, one brain.
    cheap_hand = hand_core.score_cheap(hand_core.state_of(a["state"]), player)
    cheap = core.score_cheap(core.state_of(a["state"]), player)
    assert cheap == pytest.approx((1.0 - BLEND) * cheap_hand + BLEND * FIT, abs=1e-12)


def test_the_red_scale_is_load_bearing(tmp_path, act):
    """`--red-scale` in `tools/fitted_gate.py` — proof that the number the gate
    reads comes from the NET and not from the hand half beside it."""
    head, a = act
    player = int(a["player"])
    core = cored(head)
    core.load_net(write_net(tmp_path, tiny_net()), 1.5)
    got = core.score(core.state_of(a["state"]), player)
    plain = cored(head)
    plain.load_net(write_net(tmp_path, tiny_net()))
    assert got - plain.score(plain.state_of(a["state"]), player) == pytest.approx(
        BLEND * 0.5 * FIT, abs=1e-12
    )


def test_an_unslotted_rule_the_net_saw_is_still_reported(tmp_path, act):
    """`Core.unknown_rules` must merge BOTH encoders. The fitted eval carries its
    own `RowEncoder`, and a game played with a net may run only that one — the
    core's own fills from `board_rows`, which a game calls for its sidecars and
    nowhere else. Without the merge this reports an empty list for a roster that
    had an unslotted rule, which is the loud-failure contract inverted."""
    head, a = act
    state = json.loads(json.dumps(a["state"]))
    unit = state["units"][sorted(state["units"])[0]]
    assert isinstance(unit.get("prof"), dict), "the fixture act carries per-activation profiles"
    unit["prof"]["special_rules"] = list(unit["prof"].get("special_rules", [])) + [BOGUS]

    # RED half, in the same test: with no net nothing encodes anything, so the
    # collector is empty and could not have caught this on its own.
    bare = cored(head)
    bare.score(bare.state_of(state), int(a["player"]))
    assert bare.unknown_rules() == []

    core = cored(head)
    core.load_net(write_net(tmp_path, tiny_net()))
    core.score(core.state_of(state), int(a["player"]))
    assert BOGUS in core.unknown_rules()


def test_fit_mode_is_decided_per_activation_not_per_process(tmp_path, act):
    """The net is armed on the CORE; whether an activation takes it is that
    activation's own `AiMissionEval.fit_mode`, which the act corpus records."""
    head, a = act
    player = int(a["player"])
    statics = dict(a["statics"])
    hand_statics = dict(statics, fit_mode=False)
    fit_statics = dict(statics, fit_mode=True)

    # No net: a fitted activation is DECLINED, never answered by the hand eval.
    bare = cored(head)
    declined = bare.plan_with_rollout(bare.state_of(a["state"]), player, fit_statics)
    assert declined["used"] is False and declined["unsupported"] == "FittedEval"

    core = cored(head)
    core.load_net(write_net(tmp_path, tiny_net()))
    fitted = core.plan_with_rollout(core.state_of(a["state"]), player, fit_statics)
    assert fitted["used"] is True

    # With `fit_mode` off the armed net must not leak into the search: the
    # answer is the one a core with no net gives, root score included.
    off = core.plan_with_rollout(core.state_of(a["state"]), player, hand_statics)
    ref = bare.plan_with_rollout(bare.state_of(a["state"]), player, hand_statics)
    assert off["expectation"]["before"] == ref["expectation"]["before"]
    assert off["unit_key"] == ref["unit_key"]
    assert fitted["expectation"]["before"] != ref["expectation"]["before"]


class _StubCore:
    """The three things `_pick_for` asks a core, and a record of the statics it
    was handed. Playing a real game to observe this would cost ~70 s a call."""

    def __init__(self, has_net: bool):
        self._has_net = has_net
        self.seen: list[dict] = []

    def knobs(self):
        return {"hero_attach": True}

    def has_net(self):
        return self._has_net

    def plan_with_rollout(self, _state, _player, statics):
        self.seen.append(dict(statics))
        return {"used": True}


class _StubState:
    def pool(self, _player, _fold):
        return ["a_unit"]


def test_net_player_decides_which_seat_takes_the_fitted_leaf():
    """`_pick_for`'s seat gate — the research seam `play_game` and (since the
    #474 rebase) `play_from_state` both thread. Held here rather than over a
    played game, which costs ~70 s a call with a net armed."""
    import selfplay as sp

    state = _StubState()

    # No net: `fit_mode` stays off whatever seat is named — a core with no net
    # must never claim the fitted eval.
    bare = _StubCore(has_net=False)
    for seat in (0, 1, 2):
        sp._pick_for(bare, state, 1, seat)
    assert [s["fit_mode"] for s in bare.seen] == [False, False, False]
    assert bare.seen[0] == sp.TRAINER_STATICS  # the default, untouched

    # `0` is the table's reading: whichever eval is armed plays BOTH seats.
    both = _StubCore(has_net=True)
    sp._pick_for(both, state, 1, 0)
    sp._pick_for(both, state, 2, 0)
    assert [s["fit_mode"] for s in both.seen] == [True, True]

    # `1`/`2` give the net to that seat alone — the head-to-head A/B.
    one = _StubCore(has_net=True)
    sp._pick_for(one, state, 1, 1)
    sp._pick_for(one, state, 2, 1)
    assert [s["fit_mode"] for s in one.seen] == [True, False]
    two = _StubCore(has_net=True)
    sp._pick_for(two, state, 1, 2)
    sp._pick_for(two, state, 2, 2)
    assert [s["fit_mode"] for s in two.seen] == [False, True]


def test_play_from_state_can_be_handed_the_seat_seam():
    """NML-1142 after the #474 rebase: the NET itself reaches `play_from_state`
    by inheritance (it is armed on the caller's `Core`, which `_pick_for` reads),
    so there is deliberately no `net` parameter there — but `net_player` is a
    property of the MATCH, not of the core, and must be threadable."""
    import inspect

    import selfplay as sp

    sig = inspect.signature(sp.play_from_state)
    assert sig.parameters["net_player"].default == 0
    assert "net" not in sig.parameters, "the net is inherited from the core, not passed"
    # And it reaches the round loop it exists for.
    assert "net_player" in inspect.signature(sp._play_round).parameters
