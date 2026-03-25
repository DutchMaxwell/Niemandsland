"""
Tests fuer Model Forge Exporter - Verifikation der Export-Logik.

Prueft die Kompatibilitaet mit dem opr_army_manager.gd Format:
- units.json Struktur
- GLB-Dateibenennung ({NN}_{UnitName}.glb)
- Equipment-Formatierung
- Unit-Key-Konvertierung
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from exporter import (
    ExportResult,
    _build_units_dict,
    _format_equipment_list,
    _unit_name_to_key,
    export_army,
)
from opr_client import OPRArmy, OPRUnit, OPRWeapon
from pipeline_state import UnitState, UnitStatus


# =============================================================================
# _unit_name_to_key
# =============================================================================

class TestUnitNameToKey:
    """Konvertierung von Unit-Namen zu Dictionary-Keys."""

    def test_simple_name(self) -> None:
        """Einfacher Name mit Leerzeichen."""
        assert _unit_name_to_key("Hive Lord") == "hive_lord"

    def test_hyphenated_name(self) -> None:
        """Name mit Bindestrich."""
        assert _unit_name_to_key("Carnivo-Rex") == "carnivo_rex"

    def test_hyphenated_multi_word(self) -> None:
        """Mehrteiliger Name mit Bindestrich."""
        assert _unit_name_to_key("Soul-Snatchers") == "soul_snatchers"

    def test_single_word(self) -> None:
        """Einzelnes Wort."""
        assert _unit_name_to_key("Spores") == "spores"

    def test_multi_word_with_hyphen(self) -> None:
        """Name mit Bindestrich und Leerzeichen gemischt."""
        assert _unit_name_to_key("Psycho-Grunts") == "psycho_grunts"

    def test_already_lowercase(self) -> None:
        """Bereits in Kleinbuchstaben."""
        assert _unit_name_to_key("hive lord") == "hive_lord"

    def test_multiple_spaces(self) -> None:
        """Mehrfache Leerzeichen werden zusammengefasst."""
        assert _unit_name_to_key("Hive  Lord") == "hive_lord"

    def test_trailing_special_chars(self) -> None:
        """Fuehrende/nachfolgende Sonderzeichen werden entfernt."""
        assert _unit_name_to_key("-Test Unit-") == "test_unit"

    def test_numbers_preserved(self) -> None:
        """Zahlen im Namen bleiben erhalten."""
        assert _unit_name_to_key("Unit Type 3") == "unit_type_3"

    def test_matches_existing_units_json(self) -> None:
        """Verifikation gegen die bekannten Keys aus alien_hives/units.json."""
        assert _unit_name_to_key("Hive Lord") == "hive_lord"
        assert _unit_name_to_key("Prime Warrior") == "prime_warrior"
        assert _unit_name_to_key("Assault Grunts") == "assault_grunts"
        assert _unit_name_to_key("Carnivo-Rex") == "carnivo_rex"
        assert _unit_name_to_key("Psycho-Rex") == "psycho_rex"
        assert _unit_name_to_key("Invasion Carrier Spore") == "invasion_carrier_spore"
        assert _unit_name_to_key("Tyrant Heavy Beast") == "tyrant_heavy_beast"


# =============================================================================
# _format_equipment_list
# =============================================================================

class TestFormatEquipmentList:
    """Formatierung von Waffen in das units.json Equipment-Format."""

    def test_ranged_weapon_with_rules(self) -> None:
        """Fernkampfwaffe mit Special Rules."""
        weapons = [
            OPRWeapon(
                name="Shredder Cannon",
                range_value=18,
                attacks=4,
                count=1,
                special_rules=["Rending"],
            ),
        ]
        result = _format_equipment_list(weapons)
        assert result == ['1x Shredder Cannon (18", A4, Rending)']

    def test_melee_weapon_with_ap(self) -> None:
        """Nahkampfwaffe mit AP-Regel (kein Range-Wert)."""
        weapons = [
            OPRWeapon(
                name="Heavy Razor Claws",
                range_value=0,
                attacks=3,
                count=2,
                special_rules=["AP(1)"],
            ),
        ]
        result = _format_equipment_list(weapons)
        assert result == ["2x Heavy Razor Claws (A3, AP(1))"]

    def test_simple_melee_no_rules(self) -> None:
        """Einfache Nahkampfwaffe ohne Special Rules."""
        weapons = [
            OPRWeapon(
                name="Razor Claws",
                range_value=0,
                attacks=2,
                count=10,
            ),
        ]
        result = _format_equipment_list(weapons)
        assert result == ["10x Razor Claws (A2)"]

    def test_multiple_weapons(self) -> None:
        """Mehrere Waffen in korrekter Reihenfolge."""
        weapons = [
            OPRWeapon(
                name="Shredder Cannon",
                range_value=18,
                attacks=4,
                count=1,
                special_rules=["Rending"],
            ),
            OPRWeapon(
                name="Heavy Razor Claws",
                range_value=0,
                attacks=3,
                count=2,
                special_rules=["AP(1)"],
            ),
            OPRWeapon(
                name="Stomp",
                range_value=0,
                attacks=4,
                count=1,
                special_rules=["AP(1)"],
            ),
        ]
        result = _format_equipment_list(weapons)
        assert len(result) == 3
        assert result[0] == '1x Shredder Cannon (18", A4, Rending)'
        assert result[1] == "2x Heavy Razor Claws (A3, AP(1))"
        assert result[2] == "1x Stomp (A4, AP(1))"

    def test_multiple_special_rules(self) -> None:
        """Waffe mit mehreren Special Rules."""
        weapons = [
            OPRWeapon(
                name="Spore Gun",
                range_value=24,
                attacks=2,
                count=1,
                special_rules=["Blast(3)", "Indirect", "Shred"],
            ),
        ]
        result = _format_equipment_list(weapons)
        assert result == ['1x Spore Gun (24", A2, Blast(3), Indirect, Shred)']

    def test_empty_weapons_list(self) -> None:
        """Leere Waffenliste ergibt leere Equipment-Liste."""
        assert _format_equipment_list([]) == []

    def test_matches_existing_units_json_format(self) -> None:
        """Verifikation gegen die bekannten Equipment-Strings aus alien_hives/units.json."""
        weapons = [
            OPRWeapon(
                name="Shredder Bio-Artillery",
                range_value=36,
                attacks=3,
                count=1,
                special_rules=["Blast(6)", "Indirect", "Rending"],
            ),
        ]
        result = _format_equipment_list(weapons)
        assert result == ['1x Shredder Bio-Artillery (36", A3, Blast(6), Indirect, Rending)']


# =============================================================================
# export_army - units.json Struktur
# =============================================================================

class TestExportCreatesUnitsJson:
    """Verifikation der erzeugten units.json Struktur."""

    def test_units_json_structure(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Erzeugte units.json hat die erwartete Top-Level-Struktur."""
        # GLB-Dateien vorbereiten
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        assert result.success
        assert result.units_json_path

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))

        # Top-Level-Felder pruefen
        assert "army" in data
        assert "version" in data
        assert "units" in data
        assert "total_units" in data
        assert "total_models_if_full" in data

    def test_army_name_with_game_prefix(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Army-Name enthaelt das Spielsystem-Kuerzel."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        assert data["army"] == "GF - Alien Hives"

    def test_version_is_auto_generated(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Version ist 'auto-generated'."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        assert data["version"] == "auto-generated"

    def test_unit_entry_fields(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Jeder Unit-Eintrag hat alle erforderlichen Felder."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        units = data["units"]

        assert "hive_lord" in units
        hive_lord = units["hive_lord"]

        assert hive_lord["name"] == "Hive Lord"
        assert hive_lord["size"] == 1
        assert hive_lord["points"] == 345
        assert hive_lord["qua"] == "3+"
        assert hive_lord["def"] == "2+"
        assert isinstance(hive_lord["equipment"], list)
        assert isinstance(hive_lord["special_rules"], list)
        assert hive_lord["base_size_mm"] == 50

    def test_total_units_count(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """total_units zaehlt die eindeutigen Unit-Typen."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        assert data["total_units"] == 2  # Hive Lord + Assault Grunts

    def test_total_models_if_full(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """total_models_if_full summiert alle Modelle aller Einheiten."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        # Hive Lord (1) + Assault Grunts (10) = 11
        assert data["total_models_if_full"] == 11

    def test_special_rules_in_unit(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Special Rules werden korrekt in die units.json uebernommen."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        hive_lord = data["units"]["hive_lord"]
        assert "Fear(2)" in hive_lord["special_rules"]
        assert "Fearless" in hive_lord["special_rules"]
        assert "Tough(12)" in hive_lord["special_rules"]

    def test_equipment_formatting(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Equipment-Strings entsprechen dem erwarteten Format."""
        unit_states = self._create_unit_states_with_glb(sample_army, tmp_path)

        result = export_army(sample_army, unit_states, tmp_path)

        data = json.loads(Path(result.units_json_path).read_text(encoding="utf-8"))
        hive_lord = data["units"]["hive_lord"]

        assert '1x Shredder Cannon (18", A4, Rending)' in hive_lord["equipment"]
        assert "2x Heavy Razor Claws (A3, AP(1))" in hive_lord["equipment"]

    def test_only_exportable_units_copied(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Nur Units mit Status GLB_READY oder EXPORTED werden als GLB kopiert."""
        glb_source = tmp_path / "source_glb"
        glb_source.mkdir()

        # Nur Hive Lord hat GLB_READY, Assault Grunts hat PENDING
        hive_lord_glb = glb_source / "hive_lord.glb"
        hive_lord_glb.write_bytes(b"fake-glb-hive-lord")

        unit_states = [
            UnitState(
                unit_key="hive_lord",
                unit_name="Hive Lord",
                status=UnitStatus.GLB_READY,
                glb_path=str(hive_lord_glb),
            ),
            UnitState(
                unit_key="assault_grunts",
                unit_name="Assault Grunts",
                status=UnitStatus.PENDING,
                glb_path="",
            ),
        ]

        result = export_army(sample_army, unit_states, tmp_path)

        assert result.success
        assert result.exported_count == 1

        glb_dir = Path(result.glb_dir)
        glb_files = list(glb_dir.glob("*.glb"))
        assert len(glb_files) == 1
        assert glb_files[0].name == "01_Hive Lord.glb"

    def test_no_exportable_units_fails(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Export schlaegt fehl wenn keine Einheiten exportierbar sind."""
        unit_states = [
            UnitState(
                unit_key="hive_lord",
                unit_name="Hive Lord",
                status=UnitStatus.PENDING,
            ),
        ]

        result = export_army(sample_army, unit_states, tmp_path)

        assert not result.success
        assert result.exported_count == 0

    def test_missing_faction_folder_fails(self, tmp_path: Path) -> None:
        """Export schlaegt fehl wenn faction_folder leer ist."""
        army = OPRArmy(name="Test", faction_folder="")
        result = export_army(army, [], tmp_path)

        assert not result.success
        assert any("faction_folder" in e for e in result.errors)

    # =========================================================================
    # HILFSMETHODEN
    # =========================================================================

    @staticmethod
    def _create_unit_states_with_glb(
        army: OPRArmy,
        tmp_path: Path,
    ) -> list[UnitState]:
        """Erstellt UnitState-Objekte mit vorhandenen Dummy-GLB-Dateien."""
        glb_source = tmp_path / "source_glb"
        glb_source.mkdir(exist_ok=True)

        unit_states: list[UnitState] = []
        for unit in army.units:
            key = _unit_name_to_key(unit.name)
            glb_file = glb_source / f"{key}.glb"
            glb_file.write_bytes(b"fake-glb-data")

            unit_states.append(
                UnitState(
                    unit_key=key,
                    unit_name=unit.name,
                    status=UnitStatus.GLB_READY,
                    glb_path=str(glb_file),
                )
            )

        return unit_states


# =============================================================================
# GLB-Benennungskonvention
# =============================================================================

class TestGlbNamingConvention:
    """Verifikation der GLB-Dateibenennung: {NN}_{UnitName}.glb."""

    def test_numbered_prefix(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """GLB-Dateien erhalten zweistellige Nummern-Praefixe."""
        unit_states = TestExportCreatesUnitsJson._create_unit_states_with_glb(
            sample_army, tmp_path,
        )

        result = export_army(sample_army, unit_states, tmp_path)

        assert result.success
        glb_dir = Path(result.glb_dir)
        glb_files = sorted(glb_dir.glob("*.glb"))

        assert len(glb_files) == 2
        assert glb_files[0].name == "01_Hive Lord.glb"
        assert glb_files[1].name == "02_Assault Grunts.glb"

    def test_preserves_original_unit_name(
        self,
        tmp_path: Path,
    ) -> None:
        """Der originale Unit-Name (mit Grossbuchstaben, Bindestrichen) bleibt erhalten."""
        army = OPRArmy(
            name="Test",
            game_system="Grimdark Future",
            faction_name="Test Faction",
            faction_folder="test_faction",
            units=[
                OPRUnit(name="Carnivo-Rex", size=1, cost=280, quality=4, defense=2),
            ],
        )

        glb_source = tmp_path / "source_glb"
        glb_source.mkdir()
        glb_file = glb_source / "carnivo_rex.glb"
        glb_file.write_bytes(b"fake-glb")

        unit_states = [
            UnitState(
                unit_key="carnivo_rex",
                unit_name="Carnivo-Rex",
                status=UnitStatus.GLB_READY,
                glb_path=str(glb_file),
            ),
        ]

        result = export_army(army, unit_states, tmp_path)

        assert result.success
        glb_dir = Path(result.glb_dir)
        glb_files = list(glb_dir.glob("*.glb"))

        assert len(glb_files) == 1
        assert glb_files[0].name == "01_Carnivo-Rex.glb"

    def test_glb_directory_path(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """GLB-Dateien liegen im korrekten Unterverzeichnis."""
        unit_states = TestExportCreatesUnitsJson._create_unit_states_with_glb(
            sample_army, tmp_path,
        )

        result = export_army(sample_army, unit_states, tmp_path)

        expected_glb_dir = tmp_path / "assets" / "miniatures" / "alien_hives" / "glb"
        assert Path(result.glb_dir) == expected_glb_dir

    def test_missing_glb_file_reports_error(
        self,
        sample_army: OPRArmy,
        tmp_path: Path,
    ) -> None:
        """Fehlende GLB-Quelldatei wird als Fehler gemeldet."""
        unit_states = [
            UnitState(
                unit_key="hive_lord",
                unit_name="Hive Lord",
                status=UnitStatus.GLB_READY,
                glb_path="/nicht/existent/hive_lord.glb",
            ),
        ]

        result = export_army(sample_army, unit_states, tmp_path)

        assert not result.success
        assert result.exported_count == 0
        assert any("nicht gefunden" in e for e in result.errors)

    def test_exported_status_also_copied(
        self,
        tmp_path: Path,
    ) -> None:
        """Einheiten mit Status EXPORTED werden ebenfalls kopiert."""
        army = OPRArmy(
            name="Test",
            game_system="Grimdark Future",
            faction_name="Test Faction",
            faction_folder="test_faction",
            units=[
                OPRUnit(name="Test Unit", size=1, cost=100, quality=4, defense=4),
            ],
        )

        glb_source = tmp_path / "source_glb"
        glb_source.mkdir()
        glb_file = glb_source / "test_unit.glb"
        glb_file.write_bytes(b"fake-glb")

        unit_states = [
            UnitState(
                unit_key="test_unit",
                unit_name="Test Unit",
                status=UnitStatus.EXPORTED,
                glb_path=str(glb_file),
            ),
        ]

        result = export_army(army, unit_states, tmp_path)

        assert result.success
        assert result.exported_count == 1
