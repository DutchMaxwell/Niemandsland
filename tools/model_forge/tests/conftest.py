"""
Fixtures fuer Model Forge Tests.
"""

import sys
from pathlib import Path

# model_forge-Verzeichnis zu sys.path hinzufuegen damit Imports funktionieren
_MODEL_FORGE_DIR = Path(__file__).parent.parent
if str(_MODEL_FORGE_DIR) not in sys.path:
    sys.path.insert(0, str(_MODEL_FORGE_DIR))

import pytest

from opr_client import OPRArmy, OPRUnit, OPRWeapon


# =============================================================================
# MOCK API RESPONSE - Entspricht dem echten TTS API Format
# =============================================================================

MOCK_TTS_RESPONSE = {
    "id": "test123",
    "name": "Test Army",
    "gameSystem": "gf",
    "listPoints": 2000,
    "units": [
        {
            "id": "unit_hive_lord",
            "armyId": "w7qor7b2kuifcyvk",
            "name": "Hive Lord",
            "size": 1,
            "cost": 345,
            "quality": 3,
            "defense": 2,
            "bases": {"round": "50", "square": "50"},
            "rules": [
                {"name": "Fear", "rating": 2},
                "Fearless",
                {"name": "Tough", "rating": 12},
            ],
            "loadout": [
                {
                    "name": "Shredder Cannon",
                    "range": 18,
                    "attacks": 4,
                    "count": 1,
                    "specialRules": [{"name": "Rending"}],
                },
                {
                    "name": "Heavy Razor Claws",
                    "range": 0,
                    "attacks": 3,
                    "count": 2,
                    "specialRules": [{"name": "AP", "rating": 1}],
                },
                {
                    "name": "Stomp",
                    "range": 0,
                    "attacks": 4,
                    "count": 1,
                    "specialRules": [{"name": "AP", "rating": 1}],
                },
            ],
        },
        {
            "id": "unit_assault_grunts",
            "armyId": "w7qor7b2kuifcyvk",
            "name": "Assault Grunts",
            "size": 10,
            "cost": 110,
            "quality": 5,
            "defense": 5,
            "bases": {"round": "25", "square": "25"},
            "rules": ["Fast", {"name": "Hive Bond"}],
            "loadout": [
                {
                    "name": "Razor Claws",
                    "range": 0,
                    "attacks": 2,
                    "count": 10,
                    "specialRules": [],
                },
            ],
        },
        {
            "id": "unit_carnivo_rex",
            "armyId": "w7qor7b2kuifcyvk",
            "name": "Carnivo-Rex",
            "size": 1,
            "cost": 280,
            "quality": 4,
            "defense": 2,
            "bases": {"round": "105", "square": "100"},
            "rules": [
                {"name": "Fear", "rating": 2},
                "Fearless",
                {"name": "Tough", "rating": 12},
            ],
            "loadout": [
                {
                    "name": "Heavy Razor Claws",
                    "range": 0,
                    "attacks": 3,
                    "count": 3,
                    "specialRules": [{"name": "AP", "rating": 1}],
                },
                {
                    "name": "Stomp",
                    "range": 0,
                    "attacks": 4,
                    "count": 1,
                    "specialRules": [{"name": "AP", "rating": 1}],
                },
            ],
        },
    ],
}


MOCK_OVAL_BASE_UNIT = {
    "id": "unit_rapacious",
    "armyId": "w7qor7b2kuifcyvk",
    "name": "Rapacious Beast",
    "size": 1,
    "cost": 225,
    "quality": 4,
    "defense": 2,
    "bases": {"round": "120x92", "square": "100"},
    "rules": [
        "Aircraft",
        "Fearless",
        {"name": "Tough", "rating": 6},
    ],
    "loadout": [
        {
            "name": "Caustic Cannon",
            "range": 12,
            "attacks": 2,
            "count": 1,
            "specialRules": [
                {"name": "Blast", "rating": 3},
                "Reliable",
            ],
        },
    ],
}


MOCK_EQUIPMENT_WITH_CONTENT = {
    "id": "unit_synapse_tyrant",
    "armyId": "w7qor7b2kuifcyvk",
    "name": "Synapse Tyrant",
    "size": 1,
    "cost": 180,
    "quality": 4,
    "defense": 4,
    "bases": {"round": "50", "square": "50"},
    "rules": [
        {"name": "Fear", "rating": 1},
        {"name": "Tough", "rating": 6},
    ],
    "loadout": [
        {
            "name": "Heavy Psy-Stinger",
            "range": 18,
            "attacks": 4,
            "count": 1,
            "specialRules": [
                {"name": "AP", "rating": 1},
                "Rupture",
            ],
        },
        {
            "name": "Psychic Synapses",
            "attacks": None,
            "range": None,
            "count": 1,
            "specialRules": [],
            "content": [
                {"name": "Caster", "rating": 3},
                "Resistance",
            ],
        },
    ],
}


# =============================================================================
# FIXTURES
# =============================================================================

@pytest.fixture
def mock_tts_response() -> dict:
    """Komplette Mock-TTS-API-Response."""
    return MOCK_TTS_RESPONSE.copy()


@pytest.fixture
def mock_oval_base_unit() -> dict:
    """Unit mit ovaler Base."""
    return MOCK_OVAL_BASE_UNIT.copy()


@pytest.fixture
def mock_equipment_unit() -> dict:
    """Unit mit Equipment das Sub-Rules hat (content-Feld)."""
    return MOCK_EQUIPMENT_WITH_CONTENT.copy()


@pytest.fixture
def sample_army() -> OPRArmy:
    """Fertig geparste Test-Armee."""
    army = OPRArmy(
        name="Test Army",
        game_system="Grimdark Future",
        points=2000,
        faction_name="Alien Hives",
        faction_folder="alien_hives",
    )

    hive_lord = OPRUnit(
        id="unit_hive_lord",
        name="Hive Lord",
        size=1,
        cost=345,
        quality=3,
        defense=2,
        base_size_round=50,
        base_width_mm=50,
        base_depth_mm=50,
        special_rules=["Fear(2)", "Fearless", "Tough(12)"],
        weapons=[
            OPRWeapon(name="Shredder Cannon", range_value=18, attacks=4, count=1, special_rules=["Rending"]),
            OPRWeapon(name="Heavy Razor Claws", range_value=0, attacks=3, count=2, special_rules=["AP(1)"]),
        ],
    )

    assault_grunts = OPRUnit(
        id="unit_assault_grunts",
        name="Assault Grunts",
        size=10,
        cost=110,
        quality=5,
        defense=5,
        base_size_round=25,
        base_width_mm=25,
        base_depth_mm=25,
        special_rules=["Fast", "Hive Bond"],
        weapons=[
            OPRWeapon(name="Razor Claws", range_value=0, attacks=2, count=10),
        ],
    )

    army.units = [hive_lord, assault_grunts]
    return army
