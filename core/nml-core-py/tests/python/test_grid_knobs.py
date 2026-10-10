"""LAZARUS M1 step 9a — the four `grid_k`-family knobs (default off, byte-identical). This PR only
registers them: `Core.knobs()` carries them, a header that sets the keys reads them back, and the
defaults are the OFF values. The widening that consumes them is step 9b.

RED on main: `Core.knobs()` has no `grid_k` key -> KeyError."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from test_deadline_after_preselect import _pick  # noqa: E402


def test_grid_knobs_default_off():
    core, _ = _pick({})
    k = core.knobs()
    assert k["grid_k"] == 0
    assert k["grid_units"] == 0
    assert k["grid_proposer"] == 0
    assert k["grid_margin"] == 0.0


def test_grid_knobs_read_from_the_header():
    core, _ = _pick({"grid_k": 4, "grid_units": 2, "grid_proposer": 1, "grid_margin": 0.5})
    k = core.knobs()
    assert k["grid_k"] == 4
    assert k["grid_units"] == 2
    assert k["grid_proposer"] == 1
    assert k["grid_margin"] == 0.5
