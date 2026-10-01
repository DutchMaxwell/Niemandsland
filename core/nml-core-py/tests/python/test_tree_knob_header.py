"""Tree search knobs: `Core.knobs()` round-trip and loud refusals (NML tree step 1)."""
import pytest

import nml_core

from pathlib import Path

REPO = Path(__file__).resolve().parents[4]


def _core():
    return nml_core.load(str(REPO))


def test_absent_tree_knobs_read_back_the_defaults():
    core = _core()
    core.set_header({"profiles": {}, "knobs": {}})
    k = core.knobs()
    assert (k["search_mode"], k["tree_leaf"], k["tree_dice"]) == ("oneply", "blend", "ev")
    assert (k["tree_budget"], k["tree_samples"], k["tree_batch"]) == (128, 4, 8)
    assert (k["tree_wall_ms"], k["pool_wall_ms"]) == (0, 0)


def test_stamped_tree_knobs_round_trip():
    core = _core()
    core.set_header({"profiles": {}, "knobs": {
        "search_mode": "tree", "tree_leaf": "terminal", "tree_dice": "tray",
        "tree_budget": 64, "tree_samples": 2, "tree_batch": 4,
        "tree_wall_ms": 500, "pool_wall_ms": 700}})
    k = core.knobs()
    assert (k["search_mode"], k["tree_leaf"], k["tree_dice"]) == ("tree", "terminal", "tray")
    assert (k["tree_budget"], k["tree_samples"], k["tree_batch"]) == (64, 2, 4)
    assert (k["tree_wall_ms"], k["pool_wall_ms"]) == (500, 700)


def test_an_unknown_search_mode_is_refused_loudly():
    with pytest.raises(Exception, match="search_mode"):
        _core().set_header({"profiles": {}, "knobs": {"search_mode": "maze"}})


def test_a_tree_header_with_a_zero_budget_is_refused_loudly():
    with pytest.raises(Exception, match="tree_budget"):
        _core().set_header({"profiles": {}, "knobs": {"search_mode": "tree", "tree_budget": 0}})
