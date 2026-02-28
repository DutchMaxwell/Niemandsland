"""
Pipeline State Manager - Zustandsverwaltung fuer Model Forge
=============================================================

Verfolgt den Status jeder Einheit durch die Model-Forge-Pipeline
und persistiert den Zustand als JSON.

Status-Fluss:
    PENDING -> PROMPT_GENERATED -> IMAGE_GENERATED -> IMAGE_APPROVED -> GLB_READY -> EXPORTED
                                        |
                                 IMAGE_REJECTED -> (zurueck zu IMAGE_GENERATED nach Regenerierung)

Session-Verzeichnisstruktur:
    state/{session_id}/
        session.json     (Pipeline-Zustand)
        images/          (generierte Bilder)
        glb/             (konvertierte 3D-Modelle)
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path


# =============================================================================
# KONSTANTEN
# =============================================================================

SESSION_FILE_NAME = "session.json"
IMAGES_DIR_NAME = "images"
GLB_DIR_NAME = "glb"
TIMESTAMP_FORMAT = "%Y%m%d_%H%M%S"


# =============================================================================
# ENUMS
# =============================================================================

class UnitStatus(str, Enum):
    """Status einer Einheit in der Pipeline."""

    PENDING = "pending"
    PROMPT_GENERATED = "prompt_generated"
    IMAGE_GENERATED = "image_generated"
    IMAGE_APPROVED = "image_approved"
    IMAGE_REJECTED = "image_rejected"
    GLB_READY = "glb_ready"
    EXPORTED = "exported"


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class UnitState:
    """Zustand einer einzelnen Einheit in der Pipeline."""

    unit_key: str
    unit_name: str
    status: UnitStatus = UnitStatus.PENDING
    prompt: str = ""
    image_path: str = ""
    glb_path: str = ""
    seed: int = 0
    model_used: str = ""
    generation_count: int = 0
    rejection_feedback: str = ""

    def to_dict(self) -> dict:
        """Serialisiert den UnitState in ein Dictionary."""
        data = asdict(self)
        data["status"] = self.status.value
        return data

    @classmethod
    def from_dict(cls, data: dict) -> UnitState:
        """Erstellt einen UnitState aus einem Dictionary."""
        status_value = data.get("status", UnitStatus.PENDING.value)
        return cls(
            unit_key=data.get("unit_key", ""),
            unit_name=data.get("unit_name", ""),
            status=UnitStatus(status_value),
            prompt=data.get("prompt", ""),
            image_path=data.get("image_path", ""),
            glb_path=data.get("glb_path", ""),
            seed=data.get("seed", 0),
            model_used=data.get("model_used", ""),
            generation_count=data.get("generation_count", 0),
            rejection_feedback=data.get("rejection_feedback", ""),
        )


# =============================================================================
# PIPELINE SESSION
# =============================================================================

class PipelineSession:
    """
    Verwaltet eine Pipeline-Session mit allen Einheiten.

    Eine Session repraesentiert einen kompletten Durchlauf der
    Model-Forge-Pipeline fuer eine Armee/Fraktion.
    """

    def __init__(self, session_dir: Path) -> None:
        self._session_dir: Path = session_dir
        self._session_id: str = session_dir.name
        self._army_name: str = ""
        self._faction_folder: str = ""
        self._created_at: str = ""
        self._units: dict[str, UnitState] = {}
        self.general_prompt: str = ""

    # =========================================================================
    # PROPERTIES
    # =========================================================================

    @property
    def session_id(self) -> str:
        """Eindeutige Session-ID (Format: {faction_folder}_{timestamp})."""
        return self._session_id

    @property
    def army_name(self) -> str:
        """Name der Armee."""
        return self._army_name

    @property
    def faction_folder(self) -> str:
        """Normalisierter Ordnername der Fraktion."""
        return self._faction_folder

    @property
    def created_at(self) -> str:
        """Erstellungszeitpunkt der Session (ISO-Format)."""
        return self._created_at

    # =========================================================================
    # FACTORY METHODS
    # =========================================================================

    @classmethod
    def create(
        cls,
        base_dir: Path,
        army_name: str,
        faction_folder: str,
    ) -> PipelineSession:
        """
        Erstellt eine neue Pipeline-Session.

        Legt das Session-Verzeichnis inkl. Unterordner an und
        persistiert den initialen Zustand.

        Args:
            base_dir: Basisverzeichnis fuer Sessions (z.B. state/)
            army_name: Name der Armee
            faction_folder: Normalisierter Ordnername der Fraktion

        Returns:
            Neue PipelineSession-Instanz
        """
        timestamp = datetime.now(timezone.utc).strftime(TIMESTAMP_FORMAT)
        session_id = f"{faction_folder}_{timestamp}"
        session_dir = base_dir / session_id

        # Verzeichnisstruktur anlegen
        session_dir.mkdir(parents=True, exist_ok=True)
        (session_dir / IMAGES_DIR_NAME).mkdir(exist_ok=True)
        (session_dir / GLB_DIR_NAME).mkdir(exist_ok=True)

        session = cls(session_dir)
        session._army_name = army_name
        session._faction_folder = faction_folder
        session._created_at = datetime.now(timezone.utc).isoformat()
        session.save()

        return session

    @classmethod
    def load(cls, session_path: Path) -> PipelineSession:
        """
        Laedt eine bestehende Pipeline-Session von der Festplatte.

        Args:
            session_path: Pfad zum Session-Verzeichnis

        Returns:
            Geladene PipelineSession-Instanz

        Raises:
            FileNotFoundError: Wenn session.json nicht existiert
            json.JSONDecodeError: Wenn session.json ungueltig ist
        """
        session = cls(session_path)
        session._load()
        return session

    # =========================================================================
    # UNIT-VERWALTUNG
    # =========================================================================

    def add_unit(self, unit_key: str, unit_name: str) -> UnitState:
        """
        Fuegt eine neue Einheit zur Session hinzu.

        Falls eine Einheit mit dem gleichen Key bereits existiert,
        wird die bestehende zurueckgegeben.

        Args:
            unit_key: Eindeutiger Schluessel der Einheit
            unit_name: Anzeigename der Einheit

        Returns:
            Der UnitState der hinzugefuegten oder bestehenden Einheit
        """
        if unit_key in self._units:
            return self._units[unit_key]

        state = UnitState(unit_key=unit_key, unit_name=unit_name)
        self._units[unit_key] = state
        return state

    def get_unit(self, unit_key: str) -> UnitState | None:
        """
        Gibt den Zustand einer Einheit zurueck.

        Args:
            unit_key: Eindeutiger Schluessel der Einheit

        Returns:
            UnitState oder None wenn nicht gefunden
        """
        return self._units.get(unit_key)

    def get_all_units(self) -> list[UnitState]:
        """Gibt alle Einheiten der Session zurueck."""
        return list(self._units.values())

    def get_units_by_status(self, status: UnitStatus) -> list[UnitState]:
        """
        Gibt alle Einheiten mit einem bestimmten Status zurueck.

        Args:
            status: Gewuenschter Status zum Filtern

        Returns:
            Liste der Einheiten mit dem angegebenen Status
        """
        return [unit for unit in self._units.values() if unit.status == status]

    def update_status(self, unit_key: str, status: UnitStatus, **kwargs: object) -> None:
        """
        Aktualisiert den Status und optionale Felder einer Einheit.

        Args:
            unit_key: Eindeutiger Schluessel der Einheit
            status: Neuer Status
            **kwargs: Optionale Felder (prompt, image_path, glb_path,
                      seed, model_used, generation_count)

        Raises:
            KeyError: Wenn unit_key nicht in der Session existiert
        """
        unit = self._units.get(unit_key)
        if unit is None:
            raise KeyError(f"Einheit '{unit_key}' nicht in Session gefunden")

        unit.status = status

        allowed_fields = {
            "prompt", "image_path", "glb_path",
            "seed", "model_used", "generation_count",
            "rejection_feedback",
        }

        for key, value in kwargs.items():
            if key not in allowed_fields:
                raise ValueError(f"Unbekanntes Feld: '{key}'")
            setattr(unit, key, value)

    # =========================================================================
    # FORTSCHRITT
    # =========================================================================

    def get_progress(self) -> dict:
        """
        Berechnet den aktuellen Fortschritt der Session.

        Returns:
            Dictionary mit Zaehlerstaenden je Kategorie:
            - total: Gesamtanzahl Einheiten
            - pending: Noch nicht begonnen
            - generated: Bild generiert (inkl. abgelehnt)
            - approved: Bild genehmigt
            - converted: GLB erstellt
            - exported: Fertig exportiert
        """
        total = len(self._units)
        pending = 0
        generated = 0
        approved = 0
        converted = 0
        exported = 0

        for unit in self._units.values():
            if unit.status == UnitStatus.PENDING:
                pending += 1
            elif unit.status == UnitStatus.PROMPT_GENERATED:
                pending += 1
            elif unit.status in (UnitStatus.IMAGE_GENERATED, UnitStatus.IMAGE_REJECTED):
                generated += 1
            elif unit.status == UnitStatus.IMAGE_APPROVED:
                approved += 1
            elif unit.status == UnitStatus.GLB_READY:
                converted += 1
            elif unit.status == UnitStatus.EXPORTED:
                exported += 1

        return {
            "total": total,
            "pending": pending,
            "generated": generated,
            "approved": approved,
            "converted": converted,
            "exported": exported,
        }

    # =========================================================================
    # PERSISTIERUNG
    # =========================================================================

    def save(self) -> None:
        """Speichert den Session-Zustand als JSON-Datei."""
        file_path = self._session_dir / SESSION_FILE_NAME
        data = self.to_dict()

        file_path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    def _load(self) -> None:
        """Laedt den Session-Zustand aus der JSON-Datei."""
        file_path = self._session_dir / SESSION_FILE_NAME

        if not file_path.exists():
            raise FileNotFoundError(
                f"Session-Datei nicht gefunden: {file_path}"
            )

        raw = file_path.read_text(encoding="utf-8")
        data = json.loads(raw)

        self._army_name = data.get("army_name", "")
        self._faction_folder = data.get("faction_folder", "")
        self._created_at = data.get("created_at", "")
        self._session_id = data.get("session_id", self._session_dir.name)
        self.general_prompt = data.get("general_prompt", "")

        self._units.clear()
        for unit_data in data.get("units", []):
            unit_state = UnitState.from_dict(unit_data)
            self._units[unit_state.unit_key] = unit_state

    # =========================================================================
    # SERIALISIERUNG
    # =========================================================================

    def to_dict(self) -> dict:
        """Serialisiert die Session in ein Dictionary."""
        return {
            "session_id": self._session_id,
            "army_name": self._army_name,
            "faction_folder": self._faction_folder,
            "created_at": self._created_at,
            "general_prompt": self.general_prompt,
            "units": [unit.to_dict() for unit in self._units.values()],
        }

    @classmethod
    def from_dict(cls, data: dict, session_dir: Path) -> PipelineSession:
        """
        Erstellt eine PipelineSession aus einem Dictionary.

        Args:
            data: Serialisierte Session-Daten
            session_dir: Pfad zum Session-Verzeichnis

        Returns:
            PipelineSession-Instanz
        """
        session = cls(session_dir)
        session._session_id = data.get("session_id", session_dir.name)
        session._army_name = data.get("army_name", "")
        session._faction_folder = data.get("faction_folder", "")
        session._created_at = data.get("created_at", "")
        session.general_prompt = data.get("general_prompt", "")

        for unit_data in data.get("units", []):
            unit_state = UnitState.from_dict(unit_data)
            session._units[unit_state.unit_key] = unit_state

        return session
