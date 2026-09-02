"""R2 (DESIGN_value_net_2026-09-03.md SS7) -- the `pool_value_fn` seam at the
PYTHON boundary: a value net re-ranks the root POOL on its post-act states,
the search itself untouched (door C, SS2/SS5 of the design).

Two claims, each provable to fail:

  * `pool_value_fn=None` -- every call written before this seam existed --
    answers with the EXACT dict `_pick_for` has always answered with. An
    ARMED hook that DECLINES (returns `None`) leaves the DECIDED fields
    (`action`/`unit_key`, and everything downstream of them) just as
    untouched, but its `trace` legitimately gains a `cands` key: the real
    call must force `cands=True` to hand the hook a candidate to resolve at
    all, and doing that on a SEPARATE throwaway call would double the
    search's own cost (the R2 wall-clock budget this seam is built to, per
    DESIGN_value_net_2026-09-03.md SS5, is +12%, not +100%) -- the same
    trade `record_cands=True` already makes for an opt-in trace key;
  * armed with a crafted value function and a large weight, the pick moves
    to the pool candidate the net names -- even one the hand rollout ranks
    LAST -- proving the blend, not just its plumbing, is live.

`pool_value_fn`'s signature is `fn(core, state, cands, pool_idx, rs, side) ->
list[float] | None`, `pool_idx`/`rs` already index-aligned by construction
(`lib.rs`'s `pick_plain`: both are pushed in the same PHASE 4 loop over the
same `pool` vector) -- the hook resolves each pooled candidate's post-act
state itself (`core.resolve(state, cands[i])`) and hands back one value per
pooled row, in `pool_idx` order.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"


@pytest.fixture(autouse=True)
def legacy_no_cond_ap():
    # Same pin `test_cand_logits.py` sets -- `acts_25.jsonl` predates
    # `AiEv.stamp_conditional_ap`, so its recorded search priced Shatter/
    # Tear/... at their printed AP.
    nml_core.set_legacy_no_cond_ap(True)
    yield
    nml_core.set_legacy_no_cond_ap(False)


def _acts():
    lines = [json.loads(l) for l in open(FIXTURES / "acts_25.jsonl", encoding="utf-8")]
    core = nml_core.load(str(REPO))
    core.set_header(lines[0])
    return core, lines[1:]


def test_pool_value_fn_none_is_the_old_call():
    """No entry for the side, and an entry that declines, both leave the pick
    exactly where the search left it."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        state = core.state_of(act["state"])
        player = act["player"]
        plain = sp._pick_for(core, state, player)
        explicit_none = sp._pick_for(core, state, player, pool_value_fn=None)
        declining = sp._pick_for(
            core, state, player, pool_value_fn={player: lambda *a: None}, pool_value_w=1.0
        )
        if not plain:
            continue
        assert explicit_none == plain, "an explicit `None` is not the default call"
        assert declining["action"] == plain["action"], "a declining hook must not move the pick"
        assert declining["unit_key"] == plain["unit_key"]
        assert declining["expectation"] == plain["expectation"]
        checked += 1
        if checked == 10:
            break
    assert checked == 10, "only %d positions answered" % checked


def _crafted(core, act):
    """The default rollout's pool, plus which pooled row the hand value ranks
    WORST -- the contrast candidate a value-net re-rank would have to name."""
    state = core.state_of(act["state"])
    base = core.plan_with_rollout(state, act["player"], sp.TRAINER_STATICS, cands=True)
    if not base["used"]:
        return None
    pool_idx = base["trace"]["pool_idx"]
    if len(pool_idx) < 2:
        return None
    hand_rs = [e["rs"] for e in base["trace"]["rs"]]
    best_j = max(range(len(pool_idx)), key=lambda j: hand_rs[j])
    worst_j = min(range(len(pool_idx)), key=lambda j: hand_rs[j])
    if worst_j == best_j:
        return None  # every pooled row ties on hand value -- no contrast
    return state, base, pool_idx, worst_j


def test_pool_value_fn_hook_makes_the_seat_pick_its_worst_hand_row():
    """A crafted net that names the pool row the HAND rollout likes least,
    blended at `w=inf` (net-only), makes the seat play it anyway."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        made = _crafted(core, act)
        if made is None:
            continue
        state, base, pool_idx, worst_j = made
        calls = []

        def hook(core_, state_, cands_, pool_idx_, rs_, side_, worst_j=worst_j, calls=calls):
            calls.append(side_)
            assert pool_idx_ == pool_idx
            assert len(rs_) == len(pool_idx_)
            return [1.0 if j == worst_j else 0.0 for j in range(len(pool_idx_))]

        pick = sp._pick_for(
            core, state, act["player"], pool_value_fn={act["player"]: hook}, pool_value_w=math.inf
        )
        assert pick, "the seat went dry on a position the search itself answered"
        want = base["trace"]["cands"][pool_idx[worst_j]]
        assert pick["action"] == want, "the crafted net did not carry the pick"
        assert calls == [act["player"]], "the hook must fire exactly once, for the acting side"
        checked += 1
        if checked == 3:
            break
    assert checked == 3, "only %d positions let a crafted value carry the pick" % checked


def test_pool_value_w_zero_is_the_hand_pick():
    """A hook that is ARMED but weighted at zero reduces the blend to the
    hand value alone -- the same argmax the search already ran, not a
    coincidence of the crafted numbers."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        made = _crafted(core, act)
        if made is None:
            continue
        state, base, pool_idx, worst_j = made

        def hook(core_, state_, cands_, pool_idx_, rs_, side_, worst_j=worst_j):
            return [1.0 if j == worst_j else 0.0 for j in range(len(pool_idx_))]

        plain = sp._pick_for(core, state, act["player"])
        pick = sp._pick_for(
            core, state, act["player"], pool_value_fn={act["player"]: hook}, pool_value_w=0.0
        )
        assert pick["action"] == plain["action"], "w=0 must not move the pick"
        checked += 1
        if checked == 3:
            break
    assert checked == 3, "only %d positions answered" % checked
