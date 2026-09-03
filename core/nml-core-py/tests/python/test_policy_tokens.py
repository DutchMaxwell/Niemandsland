"""NML-1073 M3-6b — DESIGN_gen0_training_2026-09-02.md §8.2 step 3a: the
`Core.policy_tokens` export binding.

The exhaustive, hand-computed field-by-field proof lives in Rust
(`core/nml-core/src/tokens.rs`'s own `#[cfg(test)]` module) because every
number there is arithmetic over `State`, which is a Rust-only fixture. This
file carries the two things that need the Python seam itself:

  * a functional smoke test — the binding marshals a REAL replayed position
    (the `acts_25.jsonl` fixture `test_trace_cands.py` already uses) into the
    padded arrays without raising, with the right shapes and an in-range
    label; and
  * RED 5, "no default caller": `policy_tokens` is never called by
    `play_game`'s default path, so the seed 27-46 fast games' `result_digest`
    must be BYTE IDENTICAL to what they were before this method existed. The
    20 digests below were captured on this branch's PARENT commit (the
    `test_trace_cands.py` SEED_27_FAST_DIGEST pattern, one pin per seed
    instead of one) and re-measured unchanged after adding `tokens.rs` +
    `policy_tokens`.
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

#: `sp.result_digest` for seeds 27..46, measured on this branch's parent
#: commit (before `tokens.rs`/`policy_tokens` existed) and required unchanged
#: — `policy_tokens` has no default caller, so nothing here should move.
#: Re-pinned after PR #600 (`dangerous_end_morale`, default True) landed and
#: moved every one of these under `LEGACY_FIDELITY_KNOBS` too — this file is
#: about policy_tokens, not that knob, so the pin just follows today's other
#: defaults rather than pinning a growing list of unrelated ones.
PINNED_DIGESTS = {
    27: "86249fc93149f8d49e74f19fbef634e985f3224710aba39d4248f535f8c94504",
    28: "4df07e24f01f1127b3ef4f9b1d6340b6357a0c846c17b9106173de4929053a84",
    29: "2a7d66e94bfe9826c2d76a304d1b49f7e21f204ee0f5f7ee3d5b7ca128413ba1",
    30: "f2b4d9225004e053baa8e01e2564e3535e79c4345b0907f9cabe8810ecfa9794",
    31: "bc7701a896ef585382f1a2da0a1fba28fd8b644aa2b270cd754a6fc4318fd258",
    32: "de68eb4bd2b9ac2bea914603d803afc097815fe78f26d8872820dad4244128a2",
    33: "4a2dbb92752bbdd01aeb8ce579c00aade056d02c25deaf2ea8f29559c8968c62",
    34: "873b68bea1c137ebc13d01b66d415a9072de599850661263d305397332108fb2",
    35: "5015dcd5dbb32c2a7b0747417c7f5014eba05eec5d54abd2d2267735d3c010fd",
    36: "a0ea7fd124995d82753f11607e86fd1ede4ba573e5dcc3127d895656738aa919",
    37: "df2a0cb870f3edf9e8aadb4d6ac00a9cb029d3ed8861f27d154837a9c566c9d4",
    38: "381515ab64b09e6c032c0d3c6f0f8fbf22d37e8dbb55366fe3bac25273255edc",
    39: "6ba0eb641534f5ff5c8055881e7b6cfb397c1eb484487361791e52dd9a686706",
    40: "1a74c8e92271833d08c2164a443f9e9424cf7c7a16e95859873e4960c5430299",
    41: "7b7e0b159170c1644a13644b173f376a3d1901eda5de4ac065c34646703001e5",
    42: "11f3236a5c13738e01297f889712631100fddd4bd835b0f3c719fe931c6a4c45",
    43: "ed5a42c3ee52e1d3cc5b0bb32ee991f4f3a3094350c11f13a26615e452bc345d",
    44: "dcd0b529ccb7006363902cca971015677173ee27b1e6cefe3a8912747bd6094f",
    45: "0747db2e0c87574e9d3081a2e424de1045b2494837733f26672a4e04fd337fff",
    46: "74f3b3789ec6037a1dd8881887153a6119a29e312ad60a7a95000e5c832a7684",
}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _read_acts(name: str):
    lines = [json.loads(l) for l in open(FIXTURES / name, encoding="utf-8")]
    return lines[0], lines[1:]


def test_policy_tokens_shapes_on_a_real_replayed_position():
    """A real corpus position, marshalled end to end: no exception, the
    padded shapes DESIGN §8.2 promises, masks that sum to the live counts,
    and a label that indexes a real, mask-1 candidate row."""
    header, acts = _read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    checked = 0
    for act in acts:
        rec = act["trace"].get("arbitration")
        sig = rec["sig"] if rec else None
        state = core.state_of(act["state"])
        got = core.plan_with_rollout(state, act["player"], act["statics"], sig, cands=True)
        if not got["used"]:
            continue
        tr = got["trace"]
        best_idx = tr["scored"][tr["best_idx"]]["idx"]
        toks = core.policy_tokens(state, act["player"], tr["cands"], best_idx)
        assert len(toks["units"]) == 24 and len(toks["units"][0]) == 72
        assert len(toks["units_mask"]) == 24
        assert len(toks["objs"]) == 6 and len(toks["objs"][0]) == 12
        assert len(toks["terr"]) == 18 and len(toks["terr"][0]) == 12
        assert len(toks["glob"]) == 16
        assert len(toks["cands"]) == 160 and len(toks["cands"][0]) == 40
        assert len(toks["actor"]) == 160 and len(toks["target"]) == 160
        n_live_units = sum(toks["units_mask"])
        assert 0 < n_live_units <= 24
        assert sum(1 for m in toks["units_mask"] if m) == n_live_units
        n_cands = sum(toks["cands_mask"])
        assert 0 < n_cands == len(tr["cands"])
        assert 0 <= toks["label"] < n_cands
        assert toks["cands_mask"][toks["label"]] == 1
        # every populated `actor` pointer names a MASKED-IN unit row
        for k in range(n_cands):
            a = toks["actor"][k]
            assert 0 <= a < n_live_units, "actor[%d] = %d out of the live rows" % (k, a)
        checked += 1
    assert checked > 0, "the corpus declined everywhere — the gate proves nothing"


def test_policy_tokens_refuses_an_oversized_menu():
    """RED 4 at the Python seam: the SAME `Unsupported` `board_rows`/
    `plan_with_rollout` already raise, not a truncated row."""
    header, acts = _read_acts("acts_25.jsonl")
    core = nml_core.load(str(REPO))
    core.set_header(header)
    act = acts[0]
    state = core.state_of(act["state"])
    unit_key = next(iter(act["state"]["units"]))
    cands = [{"unit": unit_key, "kind": 0}] * 161
    with pytest.raises(nml_core.Unsupported):
        core.policy_tokens(state, act["player"], cands, 0)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_20_pinned_games_result_digest_unchanged_by_policy_tokens():
    """RED 5: `policy_tokens` has no default caller — `play_game`'s own
    result must not move by so much as one byte for any of the 20 pinned
    seeds `test_selfplay.py`'s `GATE_SEEDS` starts from."""
    # W5a: pinned to the legacy fidelity knobs — this test is about
    # policy_tokens, not the shipped-defaults flip, so it keeps the ORIGINAL
    # pins instead of moving them for an unrelated reason.
    core = nml_core.load(str(REPO))
    bad = []
    for seed, want in PINNED_DIGESTS.items():
        got = sp.result_digest(sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core,
                                            **FAST, **sp.LEGACY_FIDELITY_KNOBS))
        if got != want:
            bad.append((seed, want, got))
    assert not bad, "digests moved for seeds: %s" % bad


def _first_live_export(seed: int) -> tuple[int, dict, str]:
    """The FIRST activation of a real `play_game`, exported the way a live
    token player does it (DESIGN_policy_player §1.1): a second, cheap
    `plan_with_rollout(cands=True)` for the menu, then `policy_tokens` off the
    same live state with `best=-1`. The probe delegates to the real
    `_pick_for` and returns its answer unchanged, so the game it rides is the
    game that would have been played — which the returned digest proves."""
    core = nml_core.load(str(REPO))
    seen: dict = {}
    real = sp._pick_for

    def probe(c, state, player, *a, **kw):
        pick = real(c, state, player, *a, **kw)
        if pick and not seen:
            menu = c.plan_with_rollout(state, player, sp.TRAINER_STATICS, cands=True)
            if menu.get("used"):
                seen["side"] = player
                seen["toks"] = c.policy_tokens(state, player, menu["trace"]["cands"], -1)
        return pick

    sp._pick_for = probe
    try:
        result = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    finally:
        sp._pick_for = real
    assert seen, "seed %d: no activation reached the probe" % seed
    return seen["side"], seen["toks"], sp.result_digest(result)


#: One 18-piece board and one 16-piece board — the bank's only two counts
#: (34,858 / 342 of its boards), both inside the pinned-digest seed range, so
#: the count comes from the record and never from a constant.
@pytest.mark.parametrize("seed", [27, 29])
@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_live_export_carries_the_banked_terrain_rows(seed):
    """NML-1163 — THE TERRAIN HOLE. `tokens::build` read `Terrain::sandbox()`,
    the header's freely placed shapes, and a BANKED board leaves that list
    empty: every live `policy_tokens` returned 18 ZERO rows with
    `sum(terr_mask) == 0` while the board carried 16 or 18 real pieces. The
    bar is the shard exporter's own reading — the same rows
    `gen0_replay_shards.terrain_rows` packs from the record's drawing list,
    same columns, same order, same count, mirrored the same way per side.

    RED without the fix on both halves: the mask sums to 0, and the rows are
    all-zero instead of the exporter's. The digest assert is the other half of
    the contract: the pieces ride the header, they must not move the game."""
    np = pytest.importorskip("numpy")
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
    from gen0_replay_shards import terrain_rows  # noqa: PLC0415

    pieces = sp.load_board(seed, BANK_DIR)[2]
    assert len(pieces) in (16, 18), "the bank's boards carry 16 or 18 pieces"
    side, toks, digest = _first_live_export(seed)

    assert sum(toks["terr_mask"]) == len(pieces), "the live mask must count the board's pieces"
    assert list(toks["terr_mask"][: len(pieces)]) == [1] * len(pieces)
    got = np.array(toks["terr"][: len(pieces)], dtype=np.float16)
    want = terrain_rows(pieces, side)
    assert got.shape == want.shape
    assert np.array_equal(got, want), "live rows differ from the shard exporter's:\n%r\n%r" % (
        got, want,
    )
    assert not any(any(v for v in row) for row in toks["terr"][len(pieces) :]), "padding not zero"
    assert digest == PINNED_DIGESTS[seed], "the header's `pieces` key moved the game"
