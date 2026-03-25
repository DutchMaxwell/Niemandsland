"""
Tests fuer Pipeline State Management - Session CRUD, JSON Round-Trip.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from pipeline_state import (
    PipelineSession,
    UnitState,
    UnitStatus,
)


# =============================================================================
# UNIT STATUS
# =============================================================================

class TestUnitStatus:
    def test_status_values(self) -> None:
        """Alle Status-Werte existieren."""
        assert UnitStatus.PENDING == "pending"
        assert UnitStatus.PROMPT_GENERATED == "prompt_generated"
        assert UnitStatus.IMAGE_GENERATED == "image_generated"
        assert UnitStatus.IMAGE_APPROVED == "image_approved"
        assert UnitStatus.IMAGE_REJECTED == "image_rejected"
        assert UnitStatus.GLB_READY == "glb_ready"
        assert UnitStatus.EXPORTED == "exported"


# =============================================================================
# SESSION CRUD
# =============================================================================

class TestPipelineSession:
    def test_create_session(self, tmp_path: Path) -> None:
        """Session wird erstellt mit korrektem Verzeichnis."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        assert session.army_name == "Test Army"
        assert session.faction_folder == "alien_hives"
        assert session.session_id.startswith("alien_hives_")

    def test_add_unit(self, tmp_path: Path) -> None:
        """Units koennen hinzugefuegt werden."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        state = session.add_unit("hive_lord", "Hive Lord")

        assert state.unit_key == "hive_lord"
        assert state.unit_name == "Hive Lord"
        assert state.status == UnitStatus.PENDING

    def test_get_unit(self, tmp_path: Path) -> None:
        """Units koennen abgerufen werden."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")

        retrieved = session.get_unit("hive_lord")
        assert retrieved is not None
        assert retrieved.unit_name == "Hive Lord"

    def test_get_unit_not_found(self, tmp_path: Path) -> None:
        """Nicht existierende Unit gibt None zurueck."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        assert session.get_unit("nonexistent") is None

    def test_update_status(self, tmp_path: Path) -> None:
        """Status-Update funktioniert."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")

        session.update_status("hive_lord", UnitStatus.PROMPT_GENERATED, prompt="Test prompt")

        state = session.get_unit("hive_lord")
        assert state.status == UnitStatus.PROMPT_GENERATED
        assert state.prompt == "Test prompt"

    def test_update_status_with_kwargs(self, tmp_path: Path) -> None:
        """Zusaetzliche Felder werden beim Status-Update gesetzt."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")

        session.update_status(
            "hive_lord",
            UnitStatus.IMAGE_GENERATED,
            image_path="/path/to/image.png",
            seed=42,
            model_used="nano-banana",
        )

        state = session.get_unit("hive_lord")
        assert state.image_path == "/path/to/image.png"
        assert state.seed == 42
        assert state.model_used == "nano-banana"

    def test_get_units_by_status(self, tmp_path: Path) -> None:
        """Filtern nach Status funktioniert."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")
        session.add_unit("assault_grunts", "Assault Grunts")

        session.update_status("hive_lord", UnitStatus.PROMPT_GENERATED)

        pending = session.get_units_by_status(UnitStatus.PENDING)
        generated = session.get_units_by_status(UnitStatus.PROMPT_GENERATED)

        assert len(pending) == 1
        assert pending[0].unit_key == "assault_grunts"
        assert len(generated) == 1
        assert generated[0].unit_key == "hive_lord"

    def test_get_all_units(self, tmp_path: Path) -> None:
        """Alle Units werden zurueckgegeben."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")
        session.add_unit("assault_grunts", "Assault Grunts")

        all_units = session.get_all_units()
        assert len(all_units) == 2


# =============================================================================
# JSON ROUND-TRIP
# =============================================================================

class TestJsonRoundTrip:
    def test_save_and_load(self, tmp_path: Path) -> None:
        """Session kann gespeichert und geladen werden."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")
        session.update_status("hive_lord", UnitStatus.PROMPT_GENERATED, prompt="Test")
        session.save()

        # Neu laden
        loaded = PipelineSession.load(session._session_dir)
        unit = loaded.get_unit("hive_lord")

        assert unit is not None
        assert unit.status == UnitStatus.PROMPT_GENERATED
        assert unit.prompt == "Test"
        assert loaded.army_name == "Test Army"

    def test_round_trip_preserves_all_fields(self, tmp_path: Path) -> None:
        """Alle Felder ueberleben den JSON Round-Trip."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")
        session.update_status(
            "hive_lord",
            UnitStatus.IMAGE_GENERATED,
            prompt="Full prompt",
            image_path="/images/hive_lord.png",
            seed=12345,
            model_used="nano-banana",
            generation_count=3,
        )
        session.save()

        loaded = PipelineSession.load(session._session_dir)
        unit = loaded.get_unit("hive_lord")

        assert unit.prompt == "Full prompt"
        assert unit.image_path == "/images/hive_lord.png"
        assert unit.seed == 12345
        assert unit.model_used == "nano-banana"
        assert unit.generation_count == 3


# =============================================================================
# PROGRESS
# =============================================================================

class TestGeneralPrompt:
    def test_general_prompt_default_empty(self, tmp_path: Path) -> None:
        """Neue Session hat leeren general_prompt."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        assert session.general_prompt == ""

    def test_general_prompt_set_and_get(self, tmp_path: Path) -> None:
        """general_prompt kann gesetzt und gelesen werden."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.general_prompt = "All armor is painted deep red"
        assert session.general_prompt == "All armor is painted deep red"

    def test_general_prompt_in_to_dict(self, tmp_path: Path) -> None:
        """general_prompt wird in to_dict() serialisiert."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.general_prompt = "Red armor"
        data = session.to_dict()
        assert data["general_prompt"] == "Red armor"

    def test_general_prompt_from_dict(self, tmp_path: Path) -> None:
        """general_prompt wird aus from_dict() deserialisiert."""
        data = {
            "session_id": "test_123",
            "army_name": "Test Army",
            "faction_folder": "alien_hives",
            "created_at": "2026-01-01T00:00:00",
            "general_prompt": "Gold trim",
            "units": [],
        }
        session = PipelineSession.from_dict(data, tmp_path)
        assert session.general_prompt == "Gold trim"

    def test_general_prompt_from_dict_missing(self, tmp_path: Path) -> None:
        """Fehlender general_prompt in alten Sessions wird als leerer String geladen."""
        data = {
            "session_id": "test_123",
            "army_name": "Test Army",
            "faction_folder": "alien_hives",
            "created_at": "2026-01-01T00:00:00",
            "units": [],
        }
        session = PipelineSession.from_dict(data, tmp_path)
        assert session.general_prompt == ""

    def test_general_prompt_json_round_trip(self, tmp_path: Path) -> None:
        """general_prompt ueberlebt Save/Load Round-Trip."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.general_prompt = "All weapons glow blue"
        session.save()

        loaded = PipelineSession.load(session._session_dir)
        assert loaded.general_prompt == "All weapons glow blue"


# =============================================================================
# PROGRESS
# =============================================================================

class TestProgress:
    def test_progress_counts(self, tmp_path: Path) -> None:
        """Progress zaehlt korrekt."""
        session = PipelineSession.create(tmp_path, "Test Army", "alien_hives")
        session.add_unit("hive_lord", "Hive Lord")
        session.add_unit("assault_grunts", "Assault Grunts")
        session.add_unit("carnivo_rex", "Carnivo-Rex")

        session.update_status("hive_lord", UnitStatus.IMAGE_APPROVED)
        session.update_status("assault_grunts", UnitStatus.PROMPT_GENERATED)

        progress = session.get_progress()
        assert progress["total"] == 3
        # PROMPT_GENERATED zaehlt als pending (noch kein Bild)
        assert progress["pending"] == 2  # carnivo_rex (PENDING) + assault_grunts (PROMPT_GENERATED)
        assert progress["approved"] == 1  # hive_lord
