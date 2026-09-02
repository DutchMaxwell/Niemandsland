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
PINNED_DIGESTS = {
    27: "15455727f2dace38d0ce9e30c0801d704baa6c7d0edd9bae2904d3a9df03bad7",
    28: "d1dac7763dfa2c610002dc8da5ed06fbf13c273c649aa5ca433f9f7a4b5cd0cd",
    29: "fcd119de04e5e725db23d17b01355f7b3a56920496ea3b4bb68428584bdb00f6",
    30: "ea0978b46e29dad33f83466edae9614c7700bcbe7bdbc56bae489be34e3eecce",
    31: "95525d88f28af6d9fb186e9c768dea632bfa1a7164ea5878add0dbf8b16b49b1",
    32: "4b55cdfeae5244d9fdec5a27b9e966888788240b04a71304c7f6c63c936587df",
    33: "de97ead2a41b6e0836c2133e58cd2e3444accf2779908be3e1a28d5c1aefaa42",
    34: "de29c82da76035fdd68b2da843bdf405f1b284856883c2140682aab5efb40f22",
    35: "6f0543b7ed0a9d8b83996e6c6cfd7b66ba45c48468aef8a4c81f1ab9a92e95e1",
    36: "98dcb31a4cbc5995e8901df752884d33a12f77bfe0b9a73e1af8d7bea05f45ae",
    37: "7b72f959f53d27ffd1735182e718c6fe08dfc3d827ce97b289609db0b41887f9",
    38: "bfa2b7c454e3716203f9625327df5792c7f2c202f29068d990458bb4be410080",
    39: "6e938dc68c6db6e4eef8ec82fc0e87bfafc44340767f5bd0096105591854c3d7",
    40: "9031d6b7f9acf5de916e8039b12dbac5d35c63586e598d58ec05db989551077d",
    41: "6de60db79e66a305e6ce1aa3f278ce30748e345559f3c2e457db86d8dc86cf91",
    42: "51cc12b0cb5883853d8516981cdab6715d69f91f03445d8d67149d303653f331",
    43: "70401fac299ed2dc5435fd66b18bfcc608a36c8032e4743ab1b093326b3f9465",
    44: "652bf3c3abdec847616b34d99567eaede086cf5d3f61ae11432178ecfea8b0dd",
    45: "22981ad48c3ebfbb93d1876c1f5661ef360316d7869103ab28acaa74772a54b4",
    46: "0c12b74616c19508696743ccf9dd6f968a81df6da71e1f2a114ef62185678d56",
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
        assert len(toks["cands"]) == 80 and len(toks["cands"][0]) == 40
        assert len(toks["actor"]) == 80 and len(toks["target"]) == 80
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
    cands = [{"unit": unit_key, "kind": 0}] * 81
    with pytest.raises(nml_core.Unsupported):
        core.policy_tokens(state, act["player"], cands, 0)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_20_pinned_games_result_digest_unchanged_by_policy_tokens():
    """RED 5: `policy_tokens` has no default caller — `play_game`'s own
    result must not move by so much as one byte for any of the 20 pinned
    seeds `test_selfplay.py`'s `GATE_SEEDS` starts from."""
    core = nml_core.load(str(REPO))
    bad = []
    for seed, want in PINNED_DIGESTS.items():
        got = sp.result_digest(sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST))
        if got != want:
            bad.append((seed, want, got))
    assert not bad, "digests moved for seeds: %s" % bad
