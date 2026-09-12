"""Rejecting a header must leave the previous Core configuration usable."""
from pathlib import Path

import nml_core
import pytest

REPO = Path(__file__).resolve().parents[4]


def header(key, *, valid=True):
    return {"profiles": {key: {
        "unit_id": key, "name": key, "quality": 4, "defense": 4,
        "tough": 3, "wounds_max": [3], "model_count": 1,
        "base_radius": 0.016, "game_system": "gf",
        "faction_folder": "robot_legions", "special_rules": [], "weapons": [],
        "move_bands": {"advance": 6.0, "rush": 12.0}}},
        "knobs": {"horizon": 1 if valid else 7,
                  "rule_vocab_version": nml_core.RULE_VOCAB_VERSION if valid else 9999}}


def plain(key):
    return {"round": 1, "rounds_total": 4, "units": {key: {
        "player": 1, "alive": 1, "wounds": [3], "radii": [0.016],
        "positions": [[0.0, 0.0, 0.0]],
        "bands": {"advance": 6.0, "rush": 12.0}}}}


@pytest.mark.parametrize("check", ["profiles", "knobs", "vocabulary"])
def test_rejected_header_preserves_the_previous_configuration(check):
    core = nml_core.load(str(REPO))
    core.set_header(header("a"))
    before = core.state_of(plain("a"))
    knobs, rows = core.knobs(), core.board_rows(before)
    with pytest.raises(nml_core.Unsupported):
        core.set_header(header("b", valid=False))
    if check == "profiles":
        assert core.state_of(plain("a")).keys() == ["a"]
        with pytest.raises(nml_core.Unsupported, match="no profile for unit key b"):
            core.state_of(plain("b"))
    elif check == "knobs":
        assert core.knobs() == knobs
    else:
        assert core.board_rows(before) == rows


def test_rejected_first_header_leaves_core_unconfigured():
    core = nml_core.load(str(REPO))
    with pytest.raises(nml_core.Unsupported):
        core.set_header(header("b", valid=False))
    with pytest.raises(nml_core.Unsupported, match="no header"):
        core.state_of(plain("b"))
    core.set_header(header("a"))
    assert core.state_of(plain("a")).keys() == ["a"]
