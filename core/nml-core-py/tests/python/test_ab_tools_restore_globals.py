"""The A/B twins use the shared armed() restore — red-green.

`search_ab_one.py` and `eval_ab_one.py` monkeypatched `nml_core.objective_layout`
and `nml_core.Tray` at IMPORT time with no restore — PR #613 flagged them as a
dormant follow-up: importing either tool in-process left the rest of the suite
playing the +500000 layout with the tray of dice seed 0. Now both wrap the game
in `gen0_replay_one.armed()` (PR #613), which applies the harness shims inside
the `with` block and restores every global on the way out. This test pins that:
importing either tool leaves `nml_core.objective_layout`, `nml_core.Tray` and
`selfplay._pick_for` exactly as they were, one armed() block really arms, and
leaving it restores all three.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import nml_core  # noqa: E402
import selfplay  # noqa: E402
import gen0_replay_one as gr  # noqa: E402

# Snapshot BEFORE either A/B tool is imported anywhere: the pristine core.
_PRISTINE = (nml_core.objective_layout, nml_core.Tray, selfplay._pick_for)


def test_ab_tools_restore_globals():
    import eval_ab_one  # noqa: F401
    import search_ab_one  # noqa: F401
    now = (nml_core.objective_layout, nml_core.Tray, selfplay._pick_for)
    assert now == _PRISTINE, "importing an A/B tool left harness shims behind"
    with gr.armed(selfplay._pick_for):
        assert nml_core.objective_layout is not _PRISTINE[0]
        assert nml_core.Tray is not _PRISTINE[1]
    now = (nml_core.objective_layout, nml_core.Tray, selfplay._pick_for)
    assert now == _PRISTINE, "one armed() block did not restore every global"
