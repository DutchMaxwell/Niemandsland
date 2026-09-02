"""NML-1164 (DESIGN_policy_player_2026-09-02.md §6 R4) — the `cand_logits`
seam at the PYTHON boundary.

R4 is what lets the token policy steer the search without being ported: the
`policy_net/1` loader (`lib.rs:1352`) holds a flat MLP and an attention model
cannot become one, so ORDER mode gets the NUMBERS instead of the net — one
logit per built candidate, in the menu's own order, plus the knob that arms
them. Three claims, each provable to fail:

  * `cand_logits=None` — every call written before this seam — answers with
    the pick the search has always answered with. The bar is the RECORDED
    pick of `acts_25.jsonl`, written by the shipped GDScript long before any
    of this existed, on 20 replayed positions;
  * armed, `policy_mode="order"` visits the menu in DESCENDING logit order:
    the crafted head is the head of `trace.scored`. The same vector with the
    knob off (and with the knob absent) must not move a single row — the KNOB
    decides, not the vector's presence;
  * a vector that does not line up with the built menu, and an unknown mode,
    DECLINE — `Unsupported`, never a partial re-rank.

The exhaustive proof of the ordering itself is in Rust
(`core/nml-core/tests/plan.rs`, `cand_logits_name_the_pool_and_the_pick_at_
top_k_one`), where a one-unit state makes the pool a single row.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"
#: the design's own bar — "equals the old call on 20 replayed positions".
POSITIONS = 20


#: `acts_25.jsonl` was cut before `AiEv.stamp_conditional_ap` reached the sim
#: path, so its recorded search priced Shatter/Tear/... at their printed AP —
#: the same pin `tests/common/mod.rs` sets for the Rust G4 gate and
#: `test_parity.py` for its own replays. Reset after, the flag is
#: process-global.
@pytest.fixture(autouse=True)
def legacy_no_cond_ap():
    nml_core.set_legacy_no_cond_ap(True)
    yield
    nml_core.set_legacy_no_cond_ap(False)


def _acts():
    lines = [json.loads(l) for l in open(FIXTURES / "acts_25.jsonl", encoding="utf-8")]
    core = nml_core.load(str(REPO))
    core.set_header(lines[0])
    return core, lines[1:]


def _sig(act):
    rec = act["trace"].get("arbitration")
    return rec["sig"] if rec else None


def test_cand_logits_none_is_the_old_call_on_20_positions():
    """The default path, twice over: passing nothing and passing `None`/"off"
    explicitly must answer identically, and both must answer with the pick the
    GDScript RECORDED for that position."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        state = core.state_of(act["state"])
        old = core.plan_with_rollout(state, act["player"], act["statics"], _sig(act), cands=True)
        if not old["used"]:
            continue
        new = core.plan_with_rollout(
            state, act["player"], act["statics"], _sig(act), cands=True,
            cand_logits=None, policy_mode="off",
        )
        assert new == old, "an explicit `None` is not the default call"
        assert old["unit_key"] == act["pick"]["unit_key"], "the pick left the recorded unit"
        assert old["action"]["kind"] == act["pick"]["action"]["kind"]
        checked += 1
        if checked == POSITIONS:
            break
    assert checked == POSITIONS, "only %d positions answered" % checked


def _crafted(core, act):
    """The default pick, plus a logit vector that names its LAST-ranked row."""
    state = core.state_of(act["state"])
    got = core.plan_with_rollout(state, act["player"], act["statics"], _sig(act), cands=True)
    if not got["used"]:
        return None
    scored = got["trace"]["scored"]
    if len(scored) < 2:
        return None
    target = scored[-1]["idx"]
    lg = [0.0] * len(got["trace"]["cands"])
    lg[target] = 1.0
    return state, got, target, lg


def test_order_mode_visits_the_menu_in_logit_order_and_off_does_not():
    """The knob decides, not the vector's presence."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        made = _crafted(core, act)
        if made is None:
            continue
        state, base, target, lg = made
        on = core.plan_with_rollout(
            state, act["player"], act["statics"], _sig(act), cands=True,
            cand_logits=lg, policy_mode="order",
        )
        assert on["used"], "order mode declined with a vector wired"
        assert on["trace"]["scored"][0]["idx"] == target, "the crafted head is not the order head"
        off = core.plan_with_rollout(
            state, act["player"], act["statics"], _sig(act), cands=True,
            cand_logits=lg, policy_mode="off",
        )
        assert off == base, "an off-mode vector moved the search"
        bare = core.plan_with_rollout(
            state, act["player"], act["statics"], _sig(act), cands=True, cand_logits=lg,
        )
        assert bare == base, "a vector with no mode named moved the search"
        checked += 1
        if checked == 5:
            break
    assert checked == 5, "only %d positions answered" % checked


def test_a_wrong_length_vector_declines():
    """A vector that does not line up with the built menu names the WRONG
    candidates — the binding's own decline dictionary, never a partial
    re-rank and never a silent truncation."""
    core, acts = _acts()
    act = acts[0]
    state = core.state_of(act["state"])
    got = core.plan_with_rollout(
        state, act["player"], act["statics"], _sig(act),
        cand_logits=[0.0, 1.0, 2.0], policy_mode="order",
    )
    assert got["used"] is False
    assert got["unsupported"].startswith("CandLogits("), got["unsupported"]


def test_an_unknown_policy_mode_declines():
    core, acts = _acts()
    act = acts[0]
    state = core.state_of(act["state"])
    with pytest.raises(nml_core.Unsupported):
        core.plan_with_rollout(
            state, act["player"], act["statics"], _sig(act), policy_mode="pick",
        )


def test_cand_logits_fn_hook_makes_the_deep_seat_play_its_choice():
    """`selfplay._pick_for`'s R4 seam at the HARNESS boundary: a hook that
    names a candidate the hand order does NOT pick makes the deep seat play
    it anyway. Every OTHER of the player's own live units is patched to
    `activated` first — the same isolation `plan.rs`'s
    `cand_logits_name_the_pool_and_the_pick_at_top_k_one` uses — because the
    search's coverage guarantee rolls at least one candidate per live unit
    REGARDLESS of `top_k`, so a multi-unit menu can let a competing unit's
    candidate win the rollout even with the crafted head visited first."""
    lines = [json.loads(l) for l in open(FIXTURES / "acts_25.jsonl", encoding="utf-8")]
    core = nml_core.load(str(REPO))
    core.set_header(dict(lines[0], knobs=dict(lines[0]["knobs"], top_k=1, horizon=1)))
    checked = 0
    for act in lines[1:]:
        raw, player = act["state"], act["player"]
        live = core.state_of(raw).pool(player, bool(core.knobs().get("hero_attach", True)))
        for keep in live:
            units = {
                k: (dict(u, activated=True) if k in live and k != keep else u)
                for k, u in raw["units"].items()
            }
            state = core.state_of(dict(raw, units=units))
            base = core.plan_with_rollout(state, player, sp.TRAINER_STATICS, cands=True)
            if not base["used"] or len(base["trace"]["cands"]) < 2:
                continue
            target = base["trace"]["scored"][-1]["idx"]
            if base["trace"]["scored"][0]["idx"] == target:
                continue  # the hand order already agrees -- no contrast
            lg = [0.0] * len(base["trace"]["cands"])
            lg[target] = 1.0
            calls = []

            def hook(st, menu, side, lg=lg, calls=calls):
                calls.append(side)
                assert len(menu) == len(lg)
                return lg

            pick = sp._pick_for(core, state, player, cand_logits_fn={player: hook}, policy_mode="order")
            if not pick or pick["action"] != base["trace"]["cands"][target]:
                continue
            assert calls == [player], "the hook must fire exactly once, for the acting side"
            checked += 1
            break
        if checked == 3:
            break
    assert checked == 3, "only %d positions let a crafted logit carry the pick" % checked


def test_cand_logits_fn_none_result_is_the_old_call():
    """A hook present for this side but declining (`None`) never surfaces the
    throwaway call's `cand_logits` and never touches `policy_mode` — the pick
    is byte-identical to no hook at all, which is every caller written
    before this seam existed."""
    lines = [json.loads(l) for l in open(FIXTURES / "acts_25.jsonl", encoding="utf-8")]
    core = nml_core.load(str(REPO))
    core.set_header(lines[0])
    act = lines[1]
    state = core.state_of(act["state"])
    player = act["player"]
    plain = sp._pick_for(core, state, player)
    hooked = sp._pick_for(
        core, state, player, cand_logits_fn={player: lambda *a: None}, policy_mode="order",
    )
    assert hooked == plain, "a declining hook must not move the pick"
