"""NML-1158c — the `--explore` knob on the fast core's selfplay path.

PIVOT (PLAN.md 31.08. 01:01/04:49): the value-net labels are the twin's own
argmax picks, so a policy trained on them can only ever learn to imitate the
hand-ranked prefilter — the north-star pivot needs labels from decisions the
tree did NOT pre-shape. `--explore <eps>` is that source: with probability
`eps` per activation, the twin picks uniformly among the prefilter's rolled
top-K pool instead of the argmax, so a corpus recorded with it carries moves
the hand ranking would not have made.

Four proofs, the knob-wiring pattern (`test_knob_wiring.py`, `test_fit_blend.py`):

  * `eps=0.0` (the default) plays the BYTE-IDENTICAL game the pre-knob code
    played (same digest, stamp included) — "pass nothing" changes nothing;
  * `eps=0.2` plays a DIFFERENT game than the default (`_digest_without_knobs`,
    so the knobs stamp alone cannot pass) and marks 15-25 % of its acts
    `explored: true` over 20 games — the coin's OWN rate, not a proxy;
  * the SAME seed played twice at the same `eps` is byte-identical — the
    dedicated stream is deterministic, not process-entropy;
  * the value is STAMPED into `knobs` (the NML-1147a pattern), and an
    out-of-range value is a clean argparse error, never a silent rate.

RED PROOF (manual, not a standing test): drop the `"explored": bool(...)` row
key in `selfplay.py`'s `_play_round`, or the `out.insert("explored", ...)` in
`nml-core-py/src/lib.rs`'s `pick_plain` — `test_explore_stamp_and_rows` fails
either way, because it reads the flag back off a live row, not off a fixture.
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

#: seeds tried in order until one diverges — the `test_knob_wiring.py` range.
SEEDS = range(27, 33)
#: the fast trainer's own knobs (`mass_fast.FIDELITY_DEFAULTS` costs) — every
#: arm here holds them in common, so the ONLY free variable is `explore`.
FAST = {"top_k": 2, "horizon": 1}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _digest_without_knobs(result: dict) -> str:
    """`sp.result_digest` with `knobs` stripped — `play_game` stamps
    `knobs["explore"]` verbatim, so the full digest would differ between the
    arms even if the knob changed nothing about the game itself."""
    return sp.result_digest({k: v for k, v in result.items() if k != "knobs"})


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_explore_default_is_byte_identical():
    """`eps=0.0` (the CLI default) must leave the pre-knob game untouched:
    same seed, FULL result digest equal — a caller that passes nothing, and a
    corpus gate replaying an old file, see no change."""
    base = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)), **FAST)
    explicit = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                            explore=0.0, **FAST)
    assert sp.result_digest(base) == sp.result_digest(explicit)
    assert base["knobs"]["explore"] == 0.0  # the stamp (NML-1147a pattern)
    assert all(not row.get("explored") for row in base["planner_positions"])


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_explore_is_a_different_game_and_marks_its_acts():
    """MUTATION GUARD: `eps=0.2` must play a DIFFERENT game than `eps=0.0` at
    the SAME seed — compared WITHOUT the knobs stamp, so a cut wire that only
    moved the label could not pass — and over 20 seeds, 15-25 % of the played
    acts must carry `explored: true`: the coin's measured rate, not the
    knob's label."""
    core = nml_core.load(str(REPO))
    diverged = False
    for seed in SEEDS:
        off = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
        on = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, explore=0.2, **FAST)
        if _digest_without_knobs(off) != _digest_without_knobs(on):
            diverged = True
            assert on["knobs"]["explore"] == 0.2
            break
    assert diverged, "no seed in %d..%d diverged under explore 0.2" % (SEEDS[0], SEEDS[-1])

    acts = 0
    explored = 0
    for seed in range(100, 120):
        res = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, explore=0.2, **FAST)
        rows = res["planner_positions"]
        acts += len(rows)
        explored += sum(1 for r in rows if r.get("explored"))
    rate = explored / acts
    assert 0.15 <= rate <= 0.25, "explored rate %.3f over %d acts, want 0.15..0.25" % (rate, acts)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_explore_is_deterministic():
    """The dedicated stream is seeded from `(seed, seq)`, never from process
    entropy: the SAME seed at the SAME `eps` played twice is byte-identical,
    `explored` flags included."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(29, ARMY1, ARMY2, REPO, BANK_DIR, core, explore=0.2, **FAST)
    b = sp.play_game(29, ARMY1, ARMY2, REPO, BANK_DIR, core, explore=0.2, **FAST)
    assert sp.result_digest(a) == sp.result_digest(b)


def test_explore_out_of_range_is_a_clean_error():
    """`explore_arg` — a junk value must fail the ARGUMENT (argparse exit 2,
    before any core is loaded), not silently reshape the exploration rate."""
    for bad in ("1.5", "-0.1"):
        with pytest.raises(SystemExit) as e:
            sp.main(["--explore", bad, "--army1", "x", "--army2", "y"])
        assert e.value.code == 2
