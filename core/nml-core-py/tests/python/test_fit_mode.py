"""NML-1158a — the `--fit-mode residual` seam on the fast core's selfplay path.

The blend ablation (BLEND ABLATION VERDICT, PLAN.md 04:49) closed arm (a)'s
first reading: MORE NET = WORSE, because the net replaces a hand eval that is
itself the strongest player. The residual seam is the answer: the net no longer
replaces anything — its sigmoid is read as a DELTA on the hand scale
(`combine_residual`, score.rs: `hand + 2*p - scale`, clamped to [0, 1]) and it
can only add what the heuristic misses. The trainer side (netlab) fits the
label `outcome - f(hand)` with the SAME convention, so the scale is defined
once, at the core.

Proofs here, the `test_fit_blend.py` pattern:

  * an unknown mode string is a CLEAN ERROR at `Core.load_net`, never a
    silently reinterpreted net;
  * the default ("blend") is byte-identical — the knobs stamp is ABSENT, the
    deployment knob's pattern (`result_digest` does not strip `knobs`);
  * residual plays a DIFFERENT game than blend on the same net — compared
    WITHOUT the knobs stamp, so a cut wire that only moved the label could not
    pass;
  * a junk CLI value fails the ARGUMENT, before any core is loaded.

The net is `test_fitted.py`'s `tiny_net`: its fitted half is CONSTANT
(`sigmoid(2)` for any state with a living own unit), so blend shrinks every
leaf toward 0.8808 while residual pushes every leaf up by `2*0.8808 - 1` —
two different gradients, and the divergence check is arithmetic, not luck.
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
#: arm here holds them in common, so the ONLY free variable is the mode.
FAST = {"top_k": 2, "horizon": 1}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _digest_without_knobs(result: dict) -> str:
    return sp.result_digest({k: v for k, v in result.items() if k != "knobs"})


def test_load_net_rejects_an_unknown_mode(tmp_path):
    """A typo'd mode must RAISE at load with a message that names the bargain,
    not fall back to blend (or anything else) and quietly play."""
    core = nml_core.load(str(REPO))
    for bad in ("delta", "resid", "BLEND", ""):
        with pytest.raises(Exception) as e:
            core.load_net(write_net(tmp_path, tiny_net()), mode=bad)
        assert "blend" in str(e.value) and "residual" in str(e.value)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_fit_mode_default_is_byte_identical(tmp_path):
    """The default must leave the pre-knob game untouched: same FULL digest
    with and without the explicit "blend", and NO stamp — a default corpus is
    the same object it was before this knob existed."""
    net = write_net(tmp_path, tiny_net())
    base = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                        net=net, **FAST)
    explicit = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                            net=net, fit_mode="blend", **FAST)
    assert sp.result_digest(base) == sp.result_digest(explicit)
    assert "fit_mode" not in base["knobs"]
    assert "fit_mode" not in explicit["knobs"]


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_residual_diverges_from_blend(tmp_path):
    """MUTATION GUARD: the same net under 'residual' must play a DIFFERENT
    game than under 'blend' — compared WITHOUT the knobs stamp, so a cut wire
    that only moved the label could not pass. The stamp assert doubles as the
    RED proof: remove the conditional stamp from `play_game` and this fails."""
    net = write_net(tmp_path, tiny_net())
    for seed in SEEDS:
        a = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                         net=net, **FAST)
        b = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)),
                         net=net, fit_mode="residual", **FAST)
        if _digest_without_knobs(a) != _digest_without_knobs(b):
            assert b["knobs"]["fit_mode"] == "residual"
            assert "fit_mode" not in a["knobs"]
            return
    pytest.fail("no seed in %d..%d diverged under fit_mode residual" % (SEEDS[0], SEEDS[-1]))


def test_fit_mode_junk_is_a_clean_argparse_error():
    """argparse `choices` — a junk value fails the ARGUMENT (exit 2, before
    any core is loaded), never a silently reinterpreted net."""
    with pytest.raises(SystemExit) as e:
        sp.main(["--fit-mode", "delta", "--army1", "x", "--army2", "y"])
    assert e.value.code == 2
