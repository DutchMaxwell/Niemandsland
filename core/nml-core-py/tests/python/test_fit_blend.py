"""NML-1158 arm (a) — the `--fit-blend` knob on the fast core's selfplay path.

The seam analysis (ABLATION_BLEND_2026-09-01) found the E4.2 blend hard-coded:
`Fitted::new` stamps `FIT_BLEND_DEFAULT` (fitted.rs:35), nothing on the
Python/twin path could move it, so every net game ever played here mixed 50 %
hand eval into its leaf scores. The knob threads `play_game(fit_blend=)` into
the existing `Core.load_net(blend=)` parameter (nml-core-py/src/lib.rs).

Four proofs, the knob-wiring pattern (`test_knob_wiring.py`):

  * the 0.5 default plays the BYTE-IDENTICAL game the pre-knob code played
    (same digest, stamp included) — "pass nothing" changes nothing;
  * blend 1.0 plays a DIFFERENT game than the default —
    `_digest_without_knobs`, so the knobs stamp alone cannot pass;
  * the value is STAMPED into `knobs` (the NML-1147a pattern);
  * an out-of-range value is a clean argparse error, never a silent blend.

The net is `test_fitted.py`'s `tiny_net` — small, and its fitted half is
CONSTANT (`sigmoid(2)` for any state with a living own unit), which makes the
blend arithmetic readable: at 1.0 every leaf ties, so the planner's picks move
wherever the hand-ranked order and the menu order disagree.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import selfplay as sp  # noqa: E402
from test_fitted import tiny_net, write_net  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"

#: seeds tried in order until one diverges — the `test_knob_wiring.py` range.
SEEDS = range(27, 33)

#: the fast trainer's own knobs (`mass_fast.FIDELITY_DEFAULTS` costs) — every
#: arm here holds them in common, so the ONLY free variable is the blend.
FAST = {"top_k": 2, "horizon": 1}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _digest_without_knobs(result: dict) -> str:
    """`sp.result_digest` over the result with its `knobs` field removed —
    `play_game` stamps `knobs["fit_blend"]` verbatim, so the full digest would
    differ between the arms even if the knob changed nothing about the game."""
    return sp.result_digest({k: v for k, v in result.items() if k != "knobs"})


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_fit_blend_default_is_byte_identical(tmp_path):
    """The CLI default (`--fit-blend 0.5`) must leave the pre-knob game
    untouched: same seed, same net, FULL result digest equal — a caller that
    passes nothing, and a corpus gate replaying an old file, see no change."""
    net = write_net(tmp_path, tiny_net())
    base = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                        net=net, **FAST)
    explicit = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                            net=net, fit_blend=0.5, **FAST)
    assert sp.result_digest(base) == sp.result_digest(explicit)
    assert base["knobs"]["fit_blend"] == 0.5  # the stamp (NML-1147a pattern)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_fit_blend_one_is_a_different_game(tmp_path):
    """MUTATION GUARD: blend 1.0 (pure net) must play a DIFFERENT game than the
    0.5 default — compared WITHOUT the knobs stamp, so a cut wire that only
    moved the label could not pass. The stamp assert doubles as the RED proof:
    remove `knobs["fit_blend"]` from `play_game` and this test fails."""
    net = write_net(tmp_path, tiny_net())
    for seed in SEEDS:
        a = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                         net=net, **FAST)
        b = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                         net=net, fit_blend=1.0, **FAST)
        if _digest_without_knobs(a) != _digest_without_knobs(b):
            assert b["knobs"]["fit_blend"] == 1.0
            return
    pytest.fail("no seed in %d..%d diverged under fit_blend 1.0" % (SEEDS[0], SEEDS[-1]))


def test_fit_blend_out_of_range_is_a_clean_error():
    """`fit_blend_arg` — a junk value must fail the ARGUMENT (argparse exit 2,
    before any core is loaded), not silently reshape the E4.2 blend."""
    for bad in ("1.5", "-0.1"):
        with pytest.raises(SystemExit) as e:
            sp.main(["--fit-blend", bad, "--army1", "x", "--army2", "y"])
        assert e.value.code == 2
