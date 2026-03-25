"""
Tests fuer Prompt Engine - Waffen/Rules zu visuellen Beschreibungen.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from opr_client import OPRArmy, OPRWeapon
from prompt_engine import (
    DesignLanguage,
    PromptEngine,
    _key_to_display_name,
    create_army_from_design_language,
    load_design_language,
)


# =============================================================================
# DESIGN LANGUAGE LADEN
# =============================================================================

DESIGN_LANGUAGES_DIR = Path(__file__).parent.parent / "design_languages"


class TestLoadDesignLanguage:
    def test_load_alien_hives(self) -> None:
        """Alien Hives YAML wird korrekt geladen."""
        dl = load_design_language(DESIGN_LANGUAGES_DIR / "alien_hives.yaml")
        assert dl.faction_name == "Alien Hives"
        assert dl.creature_type == "alien bioorganic creature"
        assert "dark purple carapace" in dl.colors["primary"]
        assert len(dl.materials) >= 2

    def test_load_template(self) -> None:
        """Template YAML wird geladen."""
        dl = load_design_language(DESIGN_LANGUAGES_DIR / "_template.yaml")
        assert dl.faction_name == "Faction Name"

    def test_unit_overrides_loaded(self) -> None:
        """Unit-Overrides werden korrekt geladen."""
        dl = load_design_language(DESIGN_LANGUAGES_DIR / "alien_hives.yaml")
        assert "hive_lord" in dl.unit_overrides
        assert "extra_details" in dl.unit_overrides["hive_lord"]


# =============================================================================
# WAFFEN ZU BESCHREIBUNG
# =============================================================================

class TestWeaponsToDescription:
    @pytest.fixture
    def engine(self) -> PromptEngine:
        dl = load_design_language(DESIGN_LANGUAGES_DIR / "alien_hives.yaml")
        return PromptEngine(dl)

    def test_ranged_weapon(self, engine: PromptEngine) -> None:
        """Fernkampfwaffen werden visuell beschrieben."""
        weapons = [OPRWeapon(name="Shredder Cannon", range_value=18, attacks=4, count=1)]
        desc = engine._weapons_to_description(weapons)
        assert "shredder cannon" in desc.lower()

    def test_melee_weapon(self, engine: PromptEngine) -> None:
        """Nahkampfwaffen werden visuell beschrieben."""
        weapons = [OPRWeapon(name="Heavy Razor Claws", range_value=0, attacks=3, count=2)]
        desc = engine._weapons_to_description(weapons)
        assert "claws" in desc.lower()

    def test_mixed_weapons(self, engine: PromptEngine) -> None:
        """Gemischte Waffen werden alle beschrieben."""
        weapons = [
            OPRWeapon(name="Bio-Cannon", range_value=24, attacks=3, count=1),
            OPRWeapon(name="Razor Claws", range_value=0, attacks=2, count=1),
        ]
        desc = engine._weapons_to_description(weapons)
        assert "cannon" in desc.lower()
        assert "claws" in desc.lower()


# =============================================================================
# RULES ZU VISUELLEN HINTS
# =============================================================================

class TestRulesToVisualHints:
    @pytest.fixture
    def engine(self) -> PromptEngine:
        dl = load_design_language(DESIGN_LANGUAGES_DIR / "alien_hives.yaml")
        return PromptEngine(dl)

    def test_flying_adds_wings(self, engine: PromptEngine) -> None:
        hints = engine._rules_to_visual_hints(["Flying"])
        assert "wing" in hints.lower()

    def test_fast_adds_agile(self, engine: PromptEngine) -> None:
        hints = engine._rules_to_visual_hints(["Fast"])
        assert "agile" in hints.lower() or "dynamic" in hints.lower()

    def test_tough_high_adds_massive(self, engine: PromptEngine) -> None:
        hints = engine._rules_to_visual_hints(["Tough(12)"])
        assert "massive" in hints.lower() or "towering" in hints.lower()

    def test_tough_medium_adds_armored(self, engine: PromptEngine) -> None:
        hints = engine._rules_to_visual_hints(["Tough(3)"])
        assert "armor" in hints.lower() or "sturdy" in hints.lower()

    def test_caster_adds_psychic(self, engine: PromptEngine) -> None:
        hints = engine._rules_to_visual_hints(["Caster(3)"])
        assert "psychic" in hints.lower() or "cranium" in hints.lower()

    def test_scout_adds_stealthy(self, engine: PromptEngine) -> None:
        hints = engine._rules_to_visual_hints(["Scout"])
        assert "stealthy" in hints.lower() or "crouch" in hints.lower()

    def test_multiple_rules(self, engine: PromptEngine) -> None:
        """Mehrere Rules werden kombiniert."""
        hints = engine._rules_to_visual_hints(["Flying", "Fast", "Tough(6)"])
        assert "wing" in hints.lower()
        assert len(hints) > 20  # Nicht leer


# =============================================================================
# PROMPT-GENERIERUNG
# =============================================================================

class TestGeneratePrompt:
    @pytest.fixture
    def engine(self) -> PromptEngine:
        dl = load_design_language(DESIGN_LANGUAGES_DIR / "alien_hives.yaml")
        return PromptEngine(dl)

    def test_prompt_contains_unit_name(self, engine: PromptEngine) -> None:
        prompt = engine.generate_prompt(
            unit_name="Hive Lord",
            unit_key="hive_lord",
            weapons=[],
            special_rules=[],
            size=1,
        )
        assert "Hive Lord" in prompt

    def test_prompt_contains_creature_type(self, engine: PromptEngine) -> None:
        prompt = engine.generate_prompt(
            unit_name="Hive Lord",
            unit_key="hive_lord",
            weapons=[],
            special_rules=[],
            size=1,
        )
        assert "bioorganic" in prompt.lower()

    def test_prompt_includes_overrides(self, engine: PromptEngine) -> None:
        """Unit-Overrides werden in den Prompt eingebaut."""
        prompt = engine.generate_prompt(
            unit_name="Hive Lord",
            unit_key="hive_lord",
            weapons=[],
            special_rules=["Tough(12)"],
            size=1,
        )
        assert "crown of horns" in prompt.lower()

    def test_prompt_no_base_instruction(self, engine: PromptEngine) -> None:
        """Prompt enthaelt Anti-Base Anweisung."""
        prompt = engine.generate_prompt(
            unit_name="Hive Lord",
            unit_key="hive_lord",
            weapons=[],
            special_rules=[],
            size=1,
        )
        assert "NO base" in prompt

    def test_prompt_white_background(self, engine: PromptEngine) -> None:
        """Prompt verlangt weissen Hintergrund."""
        prompt = engine.generate_prompt(
            unit_name="Hive Lord",
            unit_key="hive_lord",
            weapons=[],
            special_rules=[],
            size=1,
        )
        assert "white background" in prompt.lower()


# =============================================================================
# DESIGN LANGUAGE ONLY MODUS
# =============================================================================

class TestKeyToDisplayName:
    def test_single_word(self) -> None:
        """Einzelnes Wort wird korrekt konvertiert."""
        assert _key_to_display_name("champion") == "Champion"

    def test_multi_word(self) -> None:
        """Mehrere Woerter werden korrekt konvertiert."""
        assert _key_to_display_name("hive_lord") == "Hive Lord"

    def test_three_words(self) -> None:
        """Drei Woerter werden korrekt konvertiert."""
        assert _key_to_display_name("carnivo_rex") == "Carnivo Rex"


class TestCreateArmyFromDesignLanguage:
    @pytest.fixture
    def dl(self) -> DesignLanguage:
        return load_design_language(DESIGN_LANGUAGES_DIR / "battle_brothers.yaml")

    def test_army_is_created(self, dl: DesignLanguage) -> None:
        """Army-Objekt wird erzeugt."""
        army: OPRArmy = create_army_from_design_language(dl, "battle_brothers")
        assert isinstance(army, OPRArmy)
        assert army.name == "Battle Brothers"
        assert army.faction_name == "Battle Brothers"
        assert army.faction_folder == "battle_brothers"
        assert army.game_system == "Grimdark Future"

    def test_unit_count_matches_overrides(self, dl: DesignLanguage) -> None:
        """Anzahl Units stimmt mit unit_overrides ueberein."""
        army: OPRArmy = create_army_from_design_language(dl, "battle_brothers")
        assert len(army.units) == len(dl.unit_overrides)

    def test_unit_keys_consistent(self, dl: DesignLanguage) -> None:
        """Unit-Keys matchen zwischen Army-Unit-Names und Overrides."""
        army: OPRArmy = create_army_from_design_language(dl, "battle_brothers")
        army_unit_names: set[str] = {unit.name for unit in army.units}
        expected_names: set[str] = {
            _key_to_display_name(key) for key in dl.unit_overrides
        }
        assert army_unit_names == expected_names
