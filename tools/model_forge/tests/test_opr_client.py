"""
Tests fuer OPR API Client - Parsing-Logik mit Mock-Daten.
"""

import pytest

from opr_client import (
    OPRArmy,
    OPRUnit,
    OPRWeapon,
    _format_rating,
    _parse_base_size,
    _parse_tts_response,
    _parse_tts_unit,
    _safe_int,
    extract_list_id,
)


# =============================================================================
# _safe_int
# =============================================================================

class TestSafeInt:
    def test_none_returns_default(self) -> None:
        assert _safe_int(None) == 0
        assert _safe_int(None, 42) == 42

    def test_int_passthrough(self) -> None:
        assert _safe_int(50) == 50

    def test_float_truncates(self) -> None:
        assert _safe_int(3.7) == 3

    def test_string_int(self) -> None:
        assert _safe_int("32") == 32

    def test_string_float(self) -> None:
        assert _safe_int("3.5") == 3

    def test_oval_format_returns_max(self) -> None:
        assert _safe_int("60x35") == 60
        assert _safe_int("120x92") == 120

    def test_invalid_string_returns_default(self) -> None:
        assert _safe_int("abc") == 0
        assert _safe_int("abc", 25) == 25


# =============================================================================
# _parse_base_size
# =============================================================================

class TestParseBaseSize:
    def test_none_returns_default_round(self) -> None:
        is_oval, width, depth = _parse_base_size(None)
        assert is_oval is False
        assert width == 32
        assert depth == 32

    def test_int_round_base(self) -> None:
        is_oval, width, depth = _parse_base_size(50)
        assert is_oval is False
        assert width == 50
        assert depth == 50

    def test_string_round_base(self) -> None:
        is_oval, width, depth = _parse_base_size("25")
        assert is_oval is False
        assert width == 25
        assert depth == 25

    def test_oval_base(self) -> None:
        is_oval, width, depth = _parse_base_size("60x35")
        assert is_oval is True
        assert width == 35  # Kleinere Dimension
        assert depth == 60  # Groessere Dimension (Blickrichtung)

    def test_oval_base_large(self) -> None:
        is_oval, width, depth = _parse_base_size("120x92")
        assert is_oval is True
        assert width == 92
        assert depth == 120

    def test_float_round_base(self) -> None:
        is_oval, width, depth = _parse_base_size(32.0)
        assert is_oval is False
        assert width == 32

    def test_custom_default(self) -> None:
        is_oval, width, depth = _parse_base_size(None, 40)
        assert width == 40
        assert depth == 40


# =============================================================================
# _format_rating
# =============================================================================

class TestFormatRating:
    def test_whole_float(self) -> None:
        assert _format_rating(2.0) == "2"
        assert _format_rating(12.0) == "12"

    def test_fractional_float(self) -> None:
        assert _format_rating(1.5) == "1.5"

    def test_int(self) -> None:
        assert _format_rating(3) == "3"

    def test_string(self) -> None:
        assert _format_rating("2") == "2"


# =============================================================================
# extract_list_id
# =============================================================================

class TestExtractListId:
    def test_raw_id(self) -> None:
        assert extract_list_id("abc123") == "abc123"

    def test_share_link(self) -> None:
        url = "https://army-forge.onepagerules.com/share?id=abc123&name=TestArmy"
        assert extract_list_id(url) == "abc123"

    def test_share_link_id_only(self) -> None:
        url = "https://army-forge.onepagerules.com/share?id=xyz789"
        assert extract_list_id(url) == "xyz789"

    def test_empty_returns_empty(self) -> None:
        assert extract_list_id("") == ""

    def test_whitespace_stripped(self) -> None:
        assert extract_list_id("  abc123  ") == "abc123"

    def test_url_without_id_returns_empty(self) -> None:
        url = "https://army-forge.onepagerules.com/share?name=Test"
        assert extract_list_id(url) == ""


# =============================================================================
# _parse_tts_unit
# =============================================================================

class TestParseTtsUnit:
    def test_basic_unit(self, mock_tts_response: dict) -> None:
        """Parsed eine normale Einheit korrekt."""
        unit_data = mock_tts_response["units"][0]  # Hive Lord
        unit = _parse_tts_unit(unit_data)

        assert unit.name == "Hive Lord"
        assert unit.size == 1
        assert unit.cost == 345
        assert unit.quality == 3
        assert unit.defense == 2
        assert unit.base_size_round == 50

    def test_special_rules_with_rating(self, mock_tts_response: dict) -> None:
        """Rules mit Ratings werden korrekt formatiert."""
        unit_data = mock_tts_response["units"][0]  # Hive Lord
        unit = _parse_tts_unit(unit_data)

        assert "Fear(2)" in unit.special_rules
        assert "Fearless" in unit.special_rules
        assert "Tough(12)" in unit.special_rules

    def test_weapons_parsed(self, mock_tts_response: dict) -> None:
        """Waffen werden korrekt geparst."""
        unit_data = mock_tts_response["units"][0]  # Hive Lord
        unit = _parse_tts_unit(unit_data)

        assert len(unit.weapons) == 3

        cannon = unit.weapons[0]
        assert cannon.name == "Shredder Cannon"
        assert cannon.range_value == 18
        assert cannon.attacks == 4
        assert "Rending" in cannon.special_rules

        claws = unit.weapons[1]
        assert claws.name == "Heavy Razor Claws"
        assert claws.range_value == 0
        assert claws.count == 2
        assert "AP(1)" in claws.special_rules

    def test_multi_model_unit(self, mock_tts_response: dict) -> None:
        """Units mit mehreren Modellen."""
        unit_data = mock_tts_response["units"][1]  # Assault Grunts
        unit = _parse_tts_unit(unit_data)

        assert unit.size == 10
        assert unit.base_size_round == 25

    def test_oval_base(self, mock_oval_base_unit: dict) -> None:
        """Ovale Basen werden korrekt erkannt."""
        unit = _parse_tts_unit(mock_oval_base_unit)

        assert unit.base_is_oval is True
        assert unit.base_width_mm == 92
        assert unit.base_depth_mm == 120
        assert unit.base_size_round == 120

    def test_equipment_grants_rules(self, mock_equipment_unit: dict) -> None:
        """Equipment mit content-Feld waehrt Special Rules."""
        unit = _parse_tts_unit(mock_equipment_unit)

        # Caster(3) und Resistance kommen aus dem content-Feld
        assert "Caster(3)" in unit.special_rules
        assert "Resistance" in unit.special_rules
        # Das Equipment selbst wird auch als Rule aufgenommen
        assert "Psychic Synapses" in unit.special_rules


# =============================================================================
# _parse_tts_response
# =============================================================================

class TestParseTtsResponse:
    def test_army_metadata(self, mock_tts_response: dict) -> None:
        """Army-Metadaten werden korrekt geparst."""
        army = _parse_tts_response(mock_tts_response)

        assert army.name == "Test Army"
        assert army.game_system == "Grimdark Future"
        assert army.points == 2000

    def test_all_units_parsed(self, mock_tts_response: dict) -> None:
        """Alle Units werden geparst."""
        army = _parse_tts_response(mock_tts_response)
        assert len(army.units) == 3

    def test_total_models(self, mock_tts_response: dict) -> None:
        """Gesamtzahl Modelle korrekt berechnet."""
        army = _parse_tts_response(mock_tts_response)
        assert army.get_total_models() == 12  # 1 + 10 + 1

    def test_unique_unit_names(self, mock_tts_response: dict) -> None:
        """Unique Unit Names werden korrekt extrahiert."""
        army = _parse_tts_response(mock_tts_response)
        names = army.get_unique_unit_names()
        assert "Hive Lord" in names
        assert "Assault Grunts" in names
        assert "Carnivo-Rex" in names


# =============================================================================
# OPRWeapon
# =============================================================================

class TestOPRWeapon:
    def test_display_text_ranged(self) -> None:
        weapon = OPRWeapon(name="Shredder Cannon", range_value=18, attacks=4, count=1, special_rules=["Rending"])
        assert weapon.get_display_text() == 'Shredder Cannon (18", A4) [Rending]'

    def test_display_text_melee(self) -> None:
        weapon = OPRWeapon(name="Razor Claws", range_value=0, attacks=2, count=1)
        assert weapon.get_display_text() == "Razor Claws (Melee, A2)"

    def test_display_text_multi_count(self) -> None:
        weapon = OPRWeapon(name="Razor Claws", range_value=0, attacks=2, count=3)
        assert weapon.get_display_text() == "3x Razor Claws (Melee, A2)"


# =============================================================================
# OPRUnit
# =============================================================================

class TestOPRUnit:
    def test_display_name_single(self) -> None:
        unit = OPRUnit(name="Hive Lord", size=1)
        assert unit.get_display_name() == "Hive Lord"

    def test_display_name_multi(self) -> None:
        unit = OPRUnit(name="Assault Grunts", size=10)
        assert unit.get_display_name() == "Assault Grunts [10]"
