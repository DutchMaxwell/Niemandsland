"""Expert-iteration step 2 — the AUX targets and the playout-cap knob.

Three proofs, the knob-wiring pattern (`test_knob_wiring.py`,
`test_explore_knob.py`):

  * a default `play_game` call digests BYTE-IDENTICAL to the pre-step build
    (`DEFAULT_27_DIGEST`, captured before the step landed) — no cap rows, no
    aux keys in `rounds_log`, no `cap_share` stamp: the knobs are purely
    additive and opt-in, because `result_digest` hashes `rounds_log` and the
    rows;
  * `record_aux=True` hangs the KataGo-style AUX targets on every
    `rounds_log` entry and on the result beside `objectives` — models alive
    per side, wounds taken per side — and the targets are PLAUSIBLE: alive
    can only fall, wounds only rise (a dead unit counts its full health);
  * `cap_share=0.25` stamps EVERY played row with `cap`, fires on exactly 12
    of the 51 activations of seed 27 (the coin's own rate, pinned seed for
    seed), plays a DIFFERENT game than the default and is deterministic —
    the dedicated `CAP_SEED_STRIDE` stream, never process entropy.
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

#: the fast trainer's own knobs — every arm holds them in common, so the only
#: free variables are the two this step adds.
FAST = {"top_k": 2, "horizon": 1}

#: seed 27, robot_legions vs blessed_sisters, FAST — captured BEFORE the step
#: touched `selfplay.py`. The one digest a default call must still produce.
DEFAULT_27_DIGEST = "15455727f2dace38d0ce9e30c0801d704baa6c7d0edd9bae2904d3a9df03bad7"

#: `cap_share=0.25`'s coin on seed 27: 12 of 51 activations fire. The stream
#: is `seed * CAP_SEED_STRIDE + seq`, so the count is pinned, not statistical.
CAP_27_FIRED = 12


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_default_is_byte_identical():
    """Passing nothing must leave the pre-step game untouched: the FULL result
    digest equals the digest captured before the step, and no new key rides
    anywhere — not on the rows, not in `rounds_log`, not in `knobs`."""
    # W5a: pinned to the legacy fidelity knobs — this test is about
    # record_aux/cap_share, not the shipped-defaults flip, so it keeps the
    # ORIGINAL vintage pin instead of moving it for an unrelated reason.
    core = nml_core.load(str(REPO))
    res = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core,
                       **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(res) == DEFAULT_27_DIGEST
    assert sp.result_digest(
        sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core,
                     record_aux=False, cap_share=0.0, **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    ) == DEFAULT_27_DIGEST
    assert all("cap" not in row for row in res["planner_positions"])
    assert all("alive" not in e and "wounds" not in e for e in res["rounds_log"])
    assert "cap_share" not in res["knobs"]
    assert "alive" not in res and "wounds" not in res


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_record_aux_targets_are_plausible():
    """`record_aux=True` must hang `alive`/`wounds` on every round entry and
    beside `objectives` at game end, with plausible values: alive per side
    never rises, wounds taken per side never falls. The digest MOVES (it
    hashes `rounds_log`), which is exactly why the flag is opt-in."""
    core = nml_core.load(str(REPO))
    base = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    aux = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, record_aux=True, **FAST)
    assert sp.result_digest(aux) != sp.result_digest(base)
    entries = aux["rounds_log"]
    assert entries and all("alive" in e and "wounds" in e for e in entries)
    for side in ("p1", "p2"):
        alive = [e["alive"][side] for e in entries]
        wounds = [e["wounds"][side] for e in entries]
        assert all(a > 0 for a in alive), side
        assert all(w >= 0 for w in wounds), side
        assert all(x >= y for x, y in zip(alive, alive[1:])), (side, alive)
        assert all(x <= y for x, y in zip(wounds, wounds[1:])), (side, wounds)
    assert aux["alive"].keys() == {"p1", "p2"}
    assert aux["wounds"].keys() == {"p1", "p2"}
    # game end == the last round boundary: the same state, read twice.
    assert aux["alive"] == entries[-1]["alive"]
    assert aux["wounds"] == entries[-1]["wounds"]


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_cap_share_marks_its_rows():
    """`cap_share=0.25` must stamp EVERY row with `cap`, fire on exactly
    `CAP_27_FIRED` of seed 27's activations, play a DIFFERENT game than the
    default (digest, without relying on the stamp), stamp `knobs["cap_share"]`
    (the NML-1147a pattern) and replay byte-identically from the seed."""
    # W5a: pinned to the legacy fidelity knobs — CAP_27_FIRED was measured
    # under them, and this test is about cap_share, not the flip.
    core = nml_core.load(str(REPO))
    base = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    cap = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, cap_share=0.25,
                       **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    rows = cap["planner_positions"]
    assert rows and all("cap" in row for row in rows)
    assert sum(1 for row in rows if row["cap"]) == CAP_27_FIRED
    assert sp.result_digest(cap) != sp.result_digest(base)
    assert cap["knobs"]["cap_share"] == 0.25
    assert "cap_share" not in base["knobs"]
    again = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, cap_share=0.25,
                         **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(cap) == sp.result_digest(again)
