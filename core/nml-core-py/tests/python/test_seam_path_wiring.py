"""NML-1073 M4-7 wiring guard — `seam_path` must reach the Python binding's SEARCH.

THE HOLE. The path seam makes the imagined rigid move follow a tier-2 route around
walls and Impassable terrain instead of walking straight through them
(`sim.rs`, the `seams.path` block of the rigid move). It only acts when the
search's `Policy` carries the tier-2 index (`Policy.reach`); `plan::reach_of`
builds that index for every plan.rs entry point, but `Core.plan_with_rollout` in
this binding builds its own `Policy` and never set it. So a header with
`seam_path: true` was accepted, stamped and silently ignored: every trainer or
arena game played with the seam "on" planned exactly like one with it off.

MUTATION GUARD. The test plays the same seeds with the seam off and on (both
through `TRAINER_KNOBS`, the dict every `play_game` header is built from) and
requires the knob-free game digest to differ for at least one of them. With the
index unwired the two games are byte-identical and the test fails.

SKIP: needs the terrain bank and the private AI-list corpus outside the repo,
the same escape hatch `test_knob_wiring.py` uses.
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
SEEDS = range(27, 41)


def _digest_without_knobs(result: dict) -> str:
    return sp.result_digest({k: v for k, v in result.items() if k != "knobs"})


@pytest.mark.skipif(
    not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_path_seam_changes_the_python_search(monkeypatch):
    core = nml_core.load(str(REPO))
    for seed in SEEDS:
        monkeypatch.setitem(sp.TRAINER_KNOBS, "seam_path", False)
        off = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, sidecars=False)
        monkeypatch.setitem(sp.TRAINER_KNOBS, "seam_path", True)
        on = sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, sidecars=False)
        if _digest_without_knobs(off) != _digest_without_knobs(on):
            return
    pytest.fail("seam_path on/off played byte-identical games on seeds %d-%d: the path seam "
                "never reaches the search's Policy (Policy.reach unset)" % (SEEDS[0], SEEDS[-1]))
