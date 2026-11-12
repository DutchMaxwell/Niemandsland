"""Test of parity_melee_core.py's per-model kits (needs the nml_core wheel for its CHARGE constant; skipped without it)."""
import copy
import json
import sys
from pathlib import Path

import pytest

pytest.importorskip("nml_core")
sys.path.insert(0, str(Path(__file__).parent))
import parity_melee_core  # noqa: E402

SCENARIO = Path(__file__).parents[2] / "test" / "parity" / "scenarios" / "melee" / "strike_back_bearers_e75.json"


def kit_weapons(sc, key):
    _, state, _ = parity_melee_core.build(sc)
    return [k["weapons"] for k in state["units"][key]["kits"]]


def test_first_count_models_carry_the_weapon():
    sc = json.loads(SCENARIO.read_text())
    assert kit_weapons(sc, "def") == [["Blade"]] * 3 + [[]] * 5   # count 3 of 8 models
    assert kit_weapons(sc, "att") == [["Blade"]] * 10             # count 10 of 10 models


def test_count_above_the_model_count_arms_every_model():
    sc = copy.deepcopy(json.loads(SCENARIO.read_text()))
    sc["defender_weapon"]["count"] = 20
    assert kit_weapons(sc, "def") == [["Blade"]] * 8
