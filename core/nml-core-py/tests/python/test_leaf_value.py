"""R4 (DESIGN_value_net_2026-09-03.md §7) -- the `leaf_value_fn` seam at the
PYTHON boundary: a value net prices the SEARCH'S OWN leaf states -- the round
boundaries of every pooled candidate's rollout -- and the blend happens inside
`Search::run`, before the rollout backs up (door B, §2 of the design).

Three claims, each provable to fail:

  * `leaf_value_fn=None` / `leaf_value_w=0.0` -- every call written before
    this seam existed -- answers with the EXACT dict `plan_with_rollout` has
    always answered with;
  * the batch is ONE call per activation carrying EVERY leaf, state-only
    (`cands_mask` all zero, so `t[69] is_the_acting_unit` reads 0, the zero
    the trainer masks) and on the LIVE board (`terr_mask` non-empty since
    #608). A per-leaf hook would answer 34 times instead of once;
  * armed with a crafted value that favours ONE pooled candidate's leaves,
    the pick moves to that candidate -- even one the hand rollout ranks LAST
    -- proving the blend, not just its plumbing, is live.

The leaf layout is POOL ORDER then BOUNDARY ORDER, which is what lets the
crafted test address one pool row by a contiguous slice. It only uses acts
whose rollouts all returned the same number of boundaries (`n % rows == 0`);
a wrong slice would bump the wrong row and the assertion would fail loudly.
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
FAST = {"top_k": 2, "horizon": 1}
#: `test_policy_tokens.PINNED_DIGESTS[27]` — the same seed-27 fast game, kept
#: here as one literal rather than imported so a failure names THIS file.
#: Re-pinned 2026-09-05 (armies-basename fix, DIGEST_DIVERGENCE_2026-09-05.md):
#: `armies` moved from the caller's absolute path to the list basename plus
#: `armies_sha256`; the game did not move.
SEED_27_FAST_DIGEST = "23edd5cdb09ea738c67bfd3092d46abe5a72983f612151436d396658e46cce68"


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


@pytest.fixture(autouse=True)
def legacy_no_cond_ap():
    # Same pin `test_pool_value.py` sets -- `acts_25.jsonl` predates
    # `AiEv.stamp_conditional_ap`.
    nml_core.set_legacy_no_cond_ap(True)
    yield
    nml_core.set_legacy_no_cond_ap(False)


def _acts():
    lines = [json.loads(l) for l in open(FIXTURES / "acts_25.jsonl", encoding="utf-8")]
    core = nml_core.load(str(REPO))
    core.set_header(lines[0])
    return core, lines[1:]


def test_leaf_value_fn_none_is_the_old_call():
    """No hook, and a hook the weight leaves unarmed, both answer with the
    dict the search has always answered with."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        state = core.state_of(act["state"])
        plain = core.plan_with_rollout(state, act["player"], sp.TRAINER_STATICS)
        if not plain["used"]:
            continue
        calls = []
        armed = core.plan_with_rollout(
            state, act["player"], sp.TRAINER_STATICS,
            leaf_value_fn=lambda leaves, side: calls.append(1) or [9e9] * len(leaves),
        )
        assert armed == plain, "a hook at w=0.0 moved the search"
        assert calls == [], "a hook at w=0.0 was called anyway"
        checked += 1
        if checked == 10:
            break
    assert checked == 10, "only %d positions answered" % checked


def test_leaf_batch_is_one_call_of_state_only_tokens_on_the_live_board():
    """ONE call, every leaf in it, exported the way `policy_tokens` exports a
    position -- with the board's own terrain and no candidate rows."""
    core, acts = _acts()
    seen = []

    def hook(leaves, side):
        seen.append((len(leaves), side, leaves[0]))
        return [0.0] * len(leaves)

    state = core.state_of(acts[0]["state"])
    pick = core.plan_with_rollout(
        state, acts[0]["player"], sp.TRAINER_STATICS,
        leaf_value_fn=hook, leaf_value_w=1.0,
    )
    assert pick["used"]
    assert len(seen) == 1, "the leaf batch was not ONE call per activation"
    n, side, first = seen[0]
    assert n >= len(pick["trace"]["pool_idx"]), "fewer leaves than pooled rollouts"
    assert side == acts[0]["player"], "the batch was not framed in the searching side"
    assert set(first) >= {"units", "units_mask", "objs", "terr", "terr_mask", "glob", "cands_mask"}
    assert sum(first["cands_mask"]) == 0, "the leaf export is state-only (cands=[])"
    assert sum(first["units_mask"]) > 0
    # `acts_25.jsonl` is an act-corpus header with an empty sandbox, so its
    # terrain block is legitimately blank; the LIVE board's rows are the next
    # test's business.
    assert len(first["terr"]) == 18 and len(first["terr_mask"]) == 18


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_the_live_leaf_batch_rides_the_banked_board_and_moves_no_default_game():
    """#608 through the R4 door: a leaf batch taken in a REAL `play_game`
    carries the board's own 16/18 terrain rows, not 18 zeros — a value net
    played on a blank board would be judging a different table. The same game
    played with NO hook has to answer with the pinned digest, which is the
    byte-identity half."""
    # The autouse pin above is for `acts_25.jsonl`; the seed-27 digest was
    # measured with today's conditional-AP stamp, so this one test drops it.
    nml_core.set_legacy_no_cond_ap(False)
    core = nml_core.load(str(REPO))
    pieces = sp.load_board(27, BANK_DIR)[2]
    seen: dict = {}

    def hook(leaves, side):
        seen.setdefault("first", leaves[0])
        seen["calls"] = seen.get("calls", 0) + 1
        seen["leaves"] = seen.get("leaves", 0) + len(leaves)
        return [0.0] * len(leaves)

    armed = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST,
                         **sp.LEGACY_FIDELITY_KNOBS,
                         leaf_value_fn={1: hook, 2: hook}, leaf_value_w=1.0)
    assert seen["calls"] > 0, "no activation reached the hook"
    assert seen["leaves"] >= seen["calls"], "an activation handed out no leaf at all"
    assert sum(seen["first"]["terr_mask"]) == len(pieces), (
        "the leaf export lost the live board (#608): mask %d != %d pieces"
        % (sum(seen["first"]["terr_mask"]), len(pieces))
    )
    # An all-zero value is a neutral blend, so the armed game is the hand game.
    assert sp.result_digest(armed) == SEED_27_FAST_DIGEST
    plain = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST,
                         **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(plain) == SEED_27_FAST_DIGEST, "the seam moved the default game"


def test_crafted_leaf_value_carries_the_pick_at_w_one():
    """A value that favours the leaves of the pool row the HAND rollout likes
    LEAST makes the search play that row instead."""
    core, acts = _acts()
    checked = 0
    for act in acts:
        state = core.state_of(act["state"])
        base = core.plan_with_rollout(state, act["player"], sp.TRAINER_STATICS, cands=True)
        if not base["used"]:
            continue
        pool_idx = base["trace"]["pool_idx"]
        hand_rs = [e["rs"] for e in base["trace"]["rs"]]
        if len(pool_idx) < 2 or min(hand_rs) == max(hand_rs):
            continue
        worst = min(range(len(pool_idx)), key=lambda j: hand_rs[j])
        if worst == max(range(len(pool_idx)), key=lambda j: hand_rs[j]):
            continue
        size = {"n": 0}

        def probe(leaves, side, size=size):
            size["n"] = len(leaves)
            return [0.0] * len(leaves)

        neutral = core.plan_with_rollout(
            state, act["player"], sp.TRAINER_STATICS, cands=True,
            leaf_value_fn=probe, leaf_value_w=1.0,
        )
        assert neutral["action"] == base["action"], "an all-zero value moved the pick"
        if size["n"] % len(pool_idx):
            continue  # ragged boundary counts -- the slice below cannot address one row
        per = size["n"] // len(pool_idx)

        def hook(leaves, side, lo=worst * per, hi=(worst + 1) * per):
            return [1e6 if lo <= j < hi else 0.0 for j in range(len(leaves))]

        got = core.plan_with_rollout(
            state, act["player"], sp.TRAINER_STATICS, cands=True,
            leaf_value_fn=hook, leaf_value_w=1.0,
        )
        want = base["trace"]["cands"][pool_idx[worst]]
        assert got["action"] == want, "the crafted leaf value did not carry the pick"
        if got["action"] != base["action"]:
            checked += 1
        if checked == 3:
            break
    assert checked == 3, "only %d positions let a crafted leaf value move the pick" % checked


def test_a_wrong_length_batch_and_a_missing_hook_both_decline():
    """A batch that does not line up prices the WRONG leaves, and a weight
    with no hook is a value-net game that never had a value net -- both
    decline rather than quietly play the hand leaf."""
    core, acts = _acts()
    state = core.state_of(acts[0]["state"])
    short = core.plan_with_rollout(
        state, acts[0]["player"], sp.TRAINER_STATICS,
        leaf_value_fn=lambda leaves, side: [0.0, 0.0, 0.0], leaf_value_w=1.0,
    )
    assert not short["used"] and short["unsupported"].startswith("LeafValue(3,")
    bare = core.plan_with_rollout(
        state, acts[0]["player"], sp.TRAINER_STATICS, leaf_value_w=0.5
    )
    assert not bare["used"] and bare["unsupported"] == "LeafValueMissing"


def test_a_raising_hook_propagates_rather_than_falling_back():
    """The §6 tripwire: a hook that fails must not be flattened into a
    decline, or the A/B would measure the hand player against itself."""
    core, acts = _acts()
    state = core.state_of(acts[0]["state"])

    def boom(leaves, side):
        raise ValueError("no value for you")

    with pytest.raises(ValueError, match="no value for you"):
        core.plan_with_rollout(
            state, acts[0]["player"], sp.TRAINER_STATICS,
            leaf_value_fn=boom, leaf_value_w=1.0,
        )
