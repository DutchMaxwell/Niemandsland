"""
Model Forge Gradio Web-UI
=========================

Automatisierte 3D-Modell-Pipeline fuer OpenTTS Tabletop Wargaming.
Orchestriert den gesamten Workflow:

    OPR Share-Link -> Design Language -> Image Generation -> Review -> 3D Conversion -> Export

6 Tabs: Armee laden, Prompts, Bilder generieren, 3D-Konvertierung, Export, Einstellungen.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import gradio as gr

from opr_client import OPRArmy, OPRUnit, fetch_army, extract_list_id
from prompt_engine import (
    PromptEngine,
    DesignLanguage,
    create_army_from_design_language,
    load_design_language,
)
from pipeline_state import PipelineSession, UnitState, UnitStatus
from image_generator import ImageGenerator, ImageModel, GenerationResult
from trellis_bridge import convert_image_to_glb, convert_batch
from exporter import export_army, ExportResult, _unit_name_to_key


# =============================================================================
# KONSTANTEN
# =============================================================================

MODEL_FORGE_DIR: Path = Path(__file__).parent
PROJECT_ROOT: Path = MODEL_FORGE_DIR.parent.parent
DESIGN_LANGUAGES_DIR: Path = MODEL_FORGE_DIR / "design_languages"
STATE_DIR: Path = MODEL_FORGE_DIR / "state"
OUTPUT_DIR: Path = MODEL_FORGE_DIR / "output"

HF_TOKEN_FILE: Path = MODEL_FORGE_DIR / ".hf_token"
GEMINI_KEY_FILE: Path = MODEL_FORGE_DIR / ".gemini_key"
TRELLIS_SPACE_FILE: Path = MODEL_FORGE_DIR / ".trellis_space"

DEFAULT_TRELLIS_SPACE: str = "DutchyMaxwell/TRELLIS.2"

logger: logging.Logger = logging.getLogger(__name__)


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _scan_design_languages() -> list[str]:
    """Scannt verfuegbare Design Language YAML-Dateien.

    Returns:
        Sortierte Liste der YAML-Dateinamen (ohne Pfad, ohne _template).
    """
    if not DESIGN_LANGUAGES_DIR.exists():
        return []

    results: list[str] = []
    for yaml_file in sorted(DESIGN_LANGUAGES_DIR.glob("*.yaml")):
        if yaml_file.stem.startswith("_"):
            continue
        results.append(yaml_file.stem)
    return results


def _scan_existing_sessions() -> list[str]:
    """Scannt existierende Sessions im State-Verzeichnis.

    Returns:
        Sortierte Liste der Session-IDs (neueste zuerst).
    """
    if not STATE_DIR.exists():
        return []

    sessions: list[str] = []
    for session_dir in STATE_DIR.iterdir():
        if session_dir.is_dir() and (session_dir / "session.json").exists():
            sessions.append(session_dir.name)

    return sorted(sessions, reverse=True)


def _auto_detect_design_language(faction_folder: str) -> str | None:
    """Versucht eine passende Design Language anhand des faction_folder zu finden.

    Args:
        faction_folder: Normalisierter Fraktionsname (z.B. 'alien_hives').

    Returns:
        Name der Design Language oder None.
    """
    if not faction_folder:
        return None

    yaml_path: Path = DESIGN_LANGUAGES_DIR / f"{faction_folder}.yaml"
    if yaml_path.exists():
        return faction_folder

    return None


def _load_hf_token() -> str:
    """Laedt den HuggingFace Token aus der Token-Datei.

    Returns:
        Token-String oder leerer String.
    """
    if HF_TOKEN_FILE.exists():
        return HF_TOKEN_FILE.read_text(encoding="utf-8").strip()
    return ""


def _save_hf_token(token: str) -> str:
    """Speichert den HuggingFace Token in die Token-Datei.

    Args:
        token: HuggingFace API Token.

    Returns:
        Statusmeldung.
    """
    if not token or not token.strip():
        if HF_TOKEN_FILE.exists():
            HF_TOKEN_FILE.unlink()
        return "Token entfernt."

    HF_TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    HF_TOKEN_FILE.write_text(token.strip(), encoding="utf-8")
    return "Token gespeichert."


def _load_gemini_key() -> str:
    """Laedt den Gemini API Key aus der Key-Datei.

    Returns:
        Key-String oder leerer String.
    """
    if GEMINI_KEY_FILE.exists():
        return GEMINI_KEY_FILE.read_text(encoding="utf-8").strip()
    return ""


def _save_gemini_key(key: str) -> str:
    """Speichert den Gemini API Key in die Key-Datei.

    Args:
        key: Google Gemini API Key.

    Returns:
        Statusmeldung.
    """
    if not key or not key.strip():
        if GEMINI_KEY_FILE.exists():
            GEMINI_KEY_FILE.unlink()
        return "Gemini Key entfernt."

    GEMINI_KEY_FILE.parent.mkdir(parents=True, exist_ok=True)
    GEMINI_KEY_FILE.write_text(key.strip(), encoding="utf-8")
    return "Gemini Key gespeichert."


def _load_trellis_space() -> str:
    """Laedt die gespeicherte TRELLIS Space-ID.

    Returns:
        Space-ID oder der Default-Wert.
    """
    if TRELLIS_SPACE_FILE.exists():
        saved: str = TRELLIS_SPACE_FILE.read_text(encoding="utf-8").strip()
        if saved:
            return saved
    return DEFAULT_TRELLIS_SPACE


def _save_trellis_space(space_id: str) -> str:
    """Speichert die TRELLIS Space-ID in die Konfigurationsdatei.

    Args:
        space_id: HuggingFace Space-ID (z.B. "DutchyMaxwell/TRELLIS-2").

    Returns:
        Statusmeldung.
    """
    if not space_id or not space_id.strip():
        if TRELLIS_SPACE_FILE.exists():
            TRELLIS_SPACE_FILE.unlink()
        return f"Space-ID auf Default zurueckgesetzt: {DEFAULT_TRELLIS_SPACE}"

    TRELLIS_SPACE_FILE.parent.mkdir(parents=True, exist_ok=True)
    TRELLIS_SPACE_FILE.write_text(space_id.strip(), encoding="utf-8")
    return f"Space-ID gespeichert: {space_id.strip()}"


def _army_to_dataframe(army: OPRArmy) -> list[list[str]]:
    """Konvertiert eine OPRArmy in Dataframe-Zeilen.

    Args:
        army: Geladene Armee.

    Returns:
        Liste von Zeilen [Name, Size, Points, Quality, Defense, Base].
    """
    rows: list[list[str]] = []
    seen: set[str] = set()

    for unit in army.units:
        if unit.name in seen:
            continue
        seen.add(unit.name)

        base_str: str
        if unit.base_is_oval:
            base_str = f"{unit.base_width_mm}x{unit.base_depth_mm}mm (oval)"
        else:
            base_str = f"{unit.base_size_round}mm"

        rows.append([
            unit.name,
            str(unit.size),
            str(unit.cost),
            f"{unit.quality}+",
            f"{unit.defense}+",
            base_str,
        ])

    return rows


def _army_summary(army: OPRArmy) -> str:
    """Erstellt eine Zusammenfassung der Armee als Text.

    Args:
        army: Geladene Armee.

    Returns:
        Mehrzeiliger Zusammenfassungstext.
    """
    unique_count: int = len(army.get_unique_unit_names())
    total_models: int = army.get_total_models()

    lines: list[str] = [
        f"Armee: {army.name}",
        f"Fraktion: {army.faction_name}" if army.faction_name else "",
        f"Spielsystem: {army.game_system}",
        f"Punkte: {army.points}",
        f"Einheitstypen: {unique_count}",
        f"Modelle gesamt: {total_models}",
    ]
    return "\n".join(line for line in lines if line)


def _prompts_to_dataframe(session: PipelineSession) -> list[list[str]]:
    """Konvertiert Session-Units in Prompt-Dataframe-Zeilen.

    Args:
        session: Aktive Pipeline-Session.

    Returns:
        Liste von Zeilen [Unit Key, Unit Name, Prompt].
    """
    rows: list[list[str]] = []
    for unit_state in session.get_all_units():
        rows.append([
            unit_state.unit_key,
            unit_state.unit_name,
            unit_state.prompt,
        ])
    return rows


def _status_to_german(status: UnitStatus) -> str:
    """Uebersetzt UnitStatus in deutschen Anzeigetext.

    Args:
        status: UnitStatus-Enum.

    Returns:
        Deutscher Statustext.
    """
    translations: dict[UnitStatus, str] = {
        UnitStatus.PENDING: "Ausstehend",
        UnitStatus.PROMPT_GENERATED: "Prompt erstellt",
        UnitStatus.IMAGE_GENERATED: "Bild generiert",
        UnitStatus.IMAGE_APPROVED: "Bild genehmigt",
        UnitStatus.IMAGE_REJECTED: "Bild abgelehnt",
        UnitStatus.GLB_READY: "3D-Modell bereit",
        UnitStatus.EXPORTED: "Exportiert",
    }
    return translations.get(status, status.value)


# =============================================================================
# TAB 1: ARMEE LADEN
# =============================================================================

def _handle_load_from_design_language(
    dl_name: str,
) -> tuple[list[list[str]], str, str, Any, OPRArmy | None]:
    """Laedt Units direkt aus einer Design Language ohne OPR API.

    Args:
        dl_name: Name der Design Language (ohne .yaml).

    Returns:
        Tuple: (dataframe_rows, summary_text, faction_folder, dl_dropdown_update, army).
    """
    if not dl_name:
        return [], "Bitte eine Design Language auswaehlen.", "", gr.update(), None

    yaml_path: Path = DESIGN_LANGUAGES_DIR / f"{dl_name}.yaml"

    try:
        dl: DesignLanguage = load_design_language(yaml_path)
    except Exception as exc:
        return [], f"Fehler beim Laden: {exc}", "", gr.update(), None

    army: OPRArmy = create_army_from_design_language(dl, dl_name)
    rows: list[list[str]] = _army_to_dataframe(army)
    summary: str = _army_summary(army)

    return rows, summary, dl_name, gr.update(value=dl_name), army


def _handle_load_army(
    share_link: str,
) -> tuple[list[list[str]], str, str, gr.update]:
    """Laedt eine Armee von der OPR API.

    Args:
        share_link: Share-Link oder List-ID.

    Returns:
        Tuple: (dataframe_rows, summary_text, faction_folder, design_language_update).
    """
    if not share_link or not share_link.strip():
        return [], "Bitte Share-Link oder List-ID eingeben.", "", gr.update()

    try:
        army: OPRArmy = fetch_army(share_link)
    except Exception as exc:
        return [], f"Fehler beim Laden: {exc}", "", gr.update()

    rows: list[list[str]] = _army_to_dataframe(army)
    summary: str = _army_summary(army)

    # Auto-Detect Design Language
    dl_update: dict[str, Any] = {}
    detected: str | None = _auto_detect_design_language(army.faction_folder)
    if detected is not None:
        dl_update = gr.update(value=detected)
    else:
        dl_update = gr.update()

    return rows, summary, army.faction_folder, dl_update


def _handle_new_session(
    army_state: OPRArmy | None,
    share_link: str,
) -> tuple[OPRArmy | None, PipelineSession | None, str]:
    """Erstellt eine neue Pipeline-Session fuer die geladene Armee.

    Args:
        army_state: Geladene Armee (oder None).
        share_link: Share-Link fuer erneutes Laden falls army_state None.

    Returns:
        Tuple: (army, session, status_message).
    """
    army: OPRArmy | None = army_state

    if army is None and share_link:
        try:
            army = fetch_army(share_link)
        except Exception as exc:
            return None, None, f"Fehler beim Laden der Armee: {exc}"

    if army is None:
        return None, None, "Keine Armee geladen. Bitte zuerst eine Armee laden."

    if not army.faction_folder:
        return army, None, "Armee hat keinen faction_folder. Kann keine Session erstellen."

    STATE_DIR.mkdir(parents=True, exist_ok=True)

    session: PipelineSession = PipelineSession.create(
        base_dir=STATE_DIR,
        army_name=army.name,
        faction_folder=army.faction_folder,
    )

    # Units zur Session hinzufuegen (dedupliziert)
    for unit_name in army.get_unique_unit_names():
        unit_key: str = _unit_name_to_key(unit_name)
        session.add_unit(unit_key, unit_name)

    session.save()

    return (
        army,
        session,
        f"Neue Session erstellt: {session.session_id} ({len(session.get_all_units())} Einheiten)",
    )


def _handle_resume_session(
    session_id: str,
) -> tuple[PipelineSession | None, str]:
    """Laedt eine bestehende Session.

    Args:
        session_id: ID der Session.

    Returns:
        Tuple: (session, status_message).
    """
    if not session_id:
        return None, "Bitte eine Session auswaehlen."

    session_path: Path = STATE_DIR / session_id
    if not session_path.exists():
        return None, f"Session nicht gefunden: {session_id}"

    try:
        session: PipelineSession = PipelineSession.load(session_path)
    except Exception as exc:
        return None, f"Fehler beim Laden der Session: {exc}"

    progress: dict[str, int] = session.get_progress()
    status: str = (
        f"Session geladen: {session.session_id}\n"
        f"Armee: {session.army_name}\n"
        f"Einheiten: {progress['total']} "
        f"(Ausstehend: {progress['pending']}, "
        f"Generiert: {progress['generated']}, "
        f"Genehmigt: {progress['approved']}, "
        f"Konvertiert: {progress['converted']}, "
        f"Exportiert: {progress['exported']})"
    )

    return session, status


# =============================================================================
# TAB 2: PROMPTS
# =============================================================================

def _handle_generate_all_prompts(
    session: PipelineSession | None,
    army: OPRArmy | None,
    design_language_name: str,
) -> tuple[PipelineSession | None, list[list[str]], str]:
    """Generiert Prompts fuer alle Einheiten.

    Args:
        session: Aktive Pipeline-Session.
        army: Geladene Armee.
        design_language_name: Name der Design Language (ohne .yaml).

    Returns:
        Tuple: (session, dataframe_rows, status_message).
    """
    if session is None:
        return None, [], "Keine aktive Session. Bitte zuerst eine Session starten."

    if army is None:
        return session, [], "Keine Armee geladen."

    if not design_language_name:
        return session, _prompts_to_dataframe(session), "Bitte eine Design Language auswaehlen."

    yaml_path: Path = DESIGN_LANGUAGES_DIR / f"{design_language_name}.yaml"

    try:
        dl: DesignLanguage = load_design_language(yaml_path)
    except Exception as exc:
        return session, _prompts_to_dataframe(session), f"Fehler beim Laden der Design Language: {exc}"

    engine: PromptEngine = PromptEngine(dl)

    # Unit-Daten aus Army holen (dedupliziert)
    unit_data_map: dict[str, OPRUnit] = {}
    for unit in army.units:
        key: str = _unit_name_to_key(unit.name)
        if key not in unit_data_map:
            unit_data_map[key] = unit

    generated_count: int = 0
    for unit_state in session.get_all_units():
        unit: OPRUnit | None = unit_data_map.get(unit_state.unit_key)
        if unit is None:
            continue

        prompt: str = engine.generate_prompt(
            unit_name=unit.name,
            unit_key=unit_state.unit_key,
            weapons=unit.weapons,
            special_rules=unit.special_rules,
            size=unit.size,
            base_size=unit.base_size_round,
        )

        session.update_status(
            unit_state.unit_key,
            UnitStatus.PROMPT_GENERATED,
            prompt=prompt,
        )
        generated_count += 1

    session.save()

    rows: list[list[str]] = _prompts_to_dataframe(session)
    return session, rows, f"{generated_count} Prompts generiert."


def _handle_update_prompts_from_dataframe(
    session: PipelineSession | None,
    dataframe_data: list[list[str]],
) -> tuple[PipelineSession | None, str]:
    """Aktualisiert Prompts aus dem editierten Dataframe.

    Args:
        session: Aktive Pipeline-Session.
        dataframe_data: Zeilen aus dem Dataframe [Unit Key, Unit Name, Prompt].

    Returns:
        Tuple: (session, status_message).
    """
    if session is None:
        return None, "Keine aktive Session."

    import pandas as pd

    if dataframe_data is None:
        return session, "Keine Daten im Dataframe."

    rows: list[list[str]]
    if isinstance(dataframe_data, pd.DataFrame):
        if dataframe_data.empty:
            return session, "Keine Daten im Dataframe."
        rows = dataframe_data.values.tolist()
    else:
        if not dataframe_data:
            return session, "Keine Daten im Dataframe."
        rows = dataframe_data

    updated_count: int = 0
    for row in rows:
        if len(row) < 3:
            continue

        unit_key: str = row[0]
        prompt: str = row[2]

        unit_state: UnitState | None = session.get_unit(unit_key)
        if unit_state is None:
            continue

        if unit_state.prompt != prompt:
            unit_state.prompt = prompt
            if unit_state.status == UnitStatus.PENDING:
                unit_state.status = UnitStatus.PROMPT_GENERATED
            updated_count += 1

    session.save()
    return session, f"{updated_count} Prompts aktualisiert."


# =============================================================================
# TAB 3: BILDER GENERIEREN
# =============================================================================

def _handle_generate_all_images(
    session: PipelineSession | None,
    model_name: str,
    progress: gr.Progress = gr.Progress(),
    selected_keys: list[str] | None = None,
) -> tuple[PipelineSession | None, list[tuple[str, str]], str]:
    """Generiert Bilder fuer alle Einheiten mit Prompts.

    Args:
        session: Aktive Pipeline-Session.
        model_name: Name des ImageModel (z.B. 'Z_IMAGE_TURBO').
        progress: Gradio Progress-Tracker.
        selected_keys: Optionale Liste von Unit-Keys die generiert werden sollen.

    Returns:
        Tuple: (session, gallery_items, status_message).
    """
    if session is None:
        return None, [], "Keine aktive Session."

    # Einheiten mit Prompts sammeln
    units_to_generate: list[UnitState] = []
    for unit_state in session.get_all_units():
        if unit_state.prompt and unit_state.status in (
            UnitStatus.PROMPT_GENERATED,
            UnitStatus.IMAGE_REJECTED,
        ):
            if selected_keys is not None and unit_state.unit_key not in selected_keys:
                continue
            units_to_generate.append(unit_state)

    if not units_to_generate:
        gallery: list[tuple[str, str]] = _build_gallery(session)
        return session, gallery, "Keine Einheiten zum Generieren. Alle bereits generiert oder kein Prompt vorhanden."

    # Image Generator erstellen
    try:
        model_enum: ImageModel = ImageModel[model_name]
    except KeyError:
        model_enum = ImageModel.NANO_BANANA

    hf_token: str = _load_hf_token()
    gemini_key: str = _load_gemini_key()
    generator: ImageGenerator = ImageGenerator(
        model=model_enum,
        hf_token=hf_token if hf_token else None,
        gemini_api_key=gemini_key if gemini_key else None,
    )

    # Session-Image-Verzeichnis
    session_dir: Path = STATE_DIR / session.session_id
    images_dir: Path = session_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    total: int = len(units_to_generate)
    success_count: int = 0
    error_count: int = 0

    for index, unit_state in enumerate(units_to_generate):
        progress((index, total), desc=f"Generiere: {unit_state.unit_name}")

        effective_prompt: str = unit_state.prompt
        if unit_state.rejection_feedback:
            effective_prompt += f"\n\nIMPORTANT CHANGES REQUESTED: {unit_state.rejection_feedback}"
        if session.general_prompt:
            effective_prompt = (
                f"IMPORTANT OVERRIDES (must be followed):\n{session.general_prompt}\n\n"
                f"{effective_prompt}"
            )

        output_path: Path = images_dir / f"{unit_state.unit_key}.png"
        result: GenerationResult = generator.generate(
            prompt=effective_prompt,
            output_path=output_path,
        )

        if result.success:
            session.update_status(
                unit_state.unit_key,
                UnitStatus.IMAGE_GENERATED,
                image_path=result.image_path,
                seed=result.seed,
                model_used=result.model_used,
                generation_count=unit_state.generation_count + 1,
                rejection_feedback="",
            )
            success_count += 1
        else:
            error_count += 1
            logger.warning(
                "Bildgenerierung fehlgeschlagen fuer %s: %s",
                unit_state.unit_key,
                result.error,
            )

    session.save()

    gallery_items: list[tuple[str, str]] = _build_gallery(session)
    status: str = f"Generierung abgeschlossen: {success_count} erfolgreich, {error_count} fehlgeschlagen."
    return session, gallery_items, status


def _handle_regenerate_rejected(
    session: PipelineSession | None,
    model_name: str,
    progress: gr.Progress = gr.Progress(),
) -> tuple[PipelineSession | None, list[tuple[str, str]], str]:
    """Regeneriert nur abgelehnte Bilder.

    Args:
        session: Aktive Pipeline-Session.
        model_name: Name des ImageModel.
        progress: Gradio Progress-Tracker.

    Returns:
        Tuple: (session, gallery_items, status_message).
    """
    if session is None:
        return None, [], "Keine aktive Session."

    rejected: list[UnitState] = session.get_units_by_status(UnitStatus.IMAGE_REJECTED)
    if not rejected:
        gallery: list[tuple[str, str]] = _build_gallery(session)
        return session, gallery, "Keine abgelehnten Bilder vorhanden."

    rejected_keys: list[str] = [u.unit_key for u in rejected]
    return _handle_generate_all_images(session, model_name, progress, selected_keys=rejected_keys)


def _handle_approve_image(
    session: PipelineSession | None,
    unit_key: str,
) -> tuple[PipelineSession | None, list[tuple[str, str]], str]:
    """Genehmigt ein Bild (setzt Status auf IMAGE_APPROVED).

    Args:
        session: Aktive Pipeline-Session.
        unit_key: Schluessel der Einheit.

    Returns:
        Tuple: (session, gallery_items, status_message).
    """
    if session is None:
        return None, [], "Keine aktive Session."

    if not unit_key:
        gallery: list[tuple[str, str]] = _build_gallery(session)
        return session, gallery, "Kein Bild ausgewaehlt."

    unit_state: UnitState | None = session.get_unit(unit_key)
    if unit_state is None:
        gallery = _build_gallery(session)
        return session, gallery, f"Einheit nicht gefunden: {unit_key}"

    if unit_state.status not in (UnitStatus.IMAGE_GENERATED, UnitStatus.IMAGE_REJECTED):
        gallery = _build_gallery(session)
        return session, gallery, f"Einheit '{unit_state.unit_name}' hat Status '{_status_to_german(unit_state.status)}' - kann nicht genehmigt werden."

    session.update_status(unit_key, UnitStatus.IMAGE_APPROVED)
    session.save()

    gallery = _build_gallery(session)
    return session, gallery, f"Bild genehmigt: {unit_state.unit_name}"


def _handle_reject_image(
    session: PipelineSession | None,
    unit_key: str,
    feedback: str = "",
) -> tuple[PipelineSession | None, list[tuple[str, str]], str]:
    """Lehnt ein Bild ab (setzt Status auf IMAGE_REJECTED).

    Args:
        session: Aktive Pipeline-Session.
        unit_key: Schluessel der Einheit.
        feedback: Optionaler Aenderungswunsch des Users.

    Returns:
        Tuple: (session, gallery_items, status_message).
    """
    if session is None:
        return None, [], "Keine aktive Session."

    if not unit_key:
        gallery: list[tuple[str, str]] = _build_gallery(session)
        return session, gallery, "Kein Bild ausgewaehlt."

    unit_state: UnitState | None = session.get_unit(unit_key)
    if unit_state is None:
        gallery = _build_gallery(session)
        return session, gallery, f"Einheit nicht gefunden: {unit_key}"

    if unit_state.status not in (UnitStatus.IMAGE_GENERATED, UnitStatus.IMAGE_APPROVED):
        gallery = _build_gallery(session)
        return session, gallery, f"Einheit '{unit_state.unit_name}' hat Status '{_status_to_german(unit_state.status)}' - kann nicht abgelehnt werden."

    session.update_status(
        unit_key,
        UnitStatus.IMAGE_REJECTED,
        rejection_feedback=feedback.strip() if feedback else "",
    )
    session.save()

    feedback_note: str = f" (Feedback: {feedback.strip()})" if feedback and feedback.strip() else ""
    gallery = _build_gallery(session)
    return session, gallery, f"Bild abgelehnt: {unit_state.unit_name}{feedback_note}"


def _handle_gallery_select(
    session: PipelineSession | None,
    evt: gr.SelectData,
) -> tuple[str, str]:
    """Verarbeitet die Auswahl eines Bildes in der Gallery.

    Args:
        session: Aktive Pipeline-Session.
        evt: Gradio SelectData Event.

    Returns:
        Tuple: (unit_key, unit_info_text).
    """
    if session is None:
        return "", "Keine aktive Session."

    # Unit-Key per Gallery-Index ermitteln
    index: int = evt.index if hasattr(evt, "index") else -1
    image_units: list[UnitState] = [
        u for u in session.get_all_units()
        if u.image_path and Path(u.image_path).exists()
    ]

    if index < 0 or index >= len(image_units):
        return "", "Kein Bild ausgewaehlt."

    unit_key: str = image_units[index].unit_key
    unit_state: UnitState | None = session.get_unit(unit_key)
    if unit_state is None:
        return unit_key, f"Einheit nicht gefunden: {unit_key}"

    info_lines: list[str] = [
        f"Einheit: {unit_state.unit_name}",
        f"Key: {unit_state.unit_key}",
        f"Status: {_status_to_german(unit_state.status)}",
        f"Modell: {unit_state.model_used}" if unit_state.model_used else "",
        f"Seed: {unit_state.seed}" if unit_state.seed else "",
        f"Generierungen: {unit_state.generation_count}" if unit_state.generation_count else "",
    ]

    return unit_key, "\n".join(line for line in info_lines if line)


def _build_gallery(session: PipelineSession) -> list[tuple[str, str]]:
    """Erstellt Gallery-Items aus der Session.

    Args:
        session: Aktive Pipeline-Session.

    Returns:
        Liste von (image_path, caption) Tuples.
    """
    items: list[tuple[str, str]] = []

    for unit_state in session.get_all_units():
        if not unit_state.image_path:
            continue

        image_path: Path = Path(unit_state.image_path)
        if not image_path.exists():
            continue

        label: str
        if unit_state.status == UnitStatus.IMAGE_APPROVED:
            label = f"GENEHMIGT - {unit_state.unit_name}"
        elif unit_state.status == UnitStatus.IMAGE_REJECTED:
            label = f"ABGELEHNT - {unit_state.unit_name}"
        elif unit_state.status == UnitStatus.GLB_READY:
            label = f"3D FERTIG - {unit_state.unit_name}"
        elif unit_state.status == UnitStatus.EXPORTED:
            label = f"EXPORTIERT - {unit_state.unit_name}"
        else:
            label = unit_state.unit_name

        items.append((str(image_path), label))

    return items


# =============================================================================
# TAB 4: 3D-KONVERTIERUNG
# =============================================================================

def _handle_convert_approved(
    session: PipelineSession | None,
    progress: gr.Progress = gr.Progress(),
) -> tuple[PipelineSession | None, str, str]:
    """Konvertiert alle genehmigten Bilder zu GLB-3D-Modellen.

    Args:
        session: Aktive Pipeline-Session.
        progress: Gradio Progress-Tracker.

    Returns:
        Tuple: (session, status_list_text, status_message).
    """
    if session is None:
        return None, "", "Keine aktive Session."

    approved: list[UnitState] = session.get_units_by_status(UnitStatus.IMAGE_APPROVED)
    if not approved:
        status_list: str = _build_conversion_status_list(session)
        return session, status_list, "Keine genehmigten Bilder zum Konvertieren."

    # Image-Pfade sammeln
    image_paths: dict[str, Path] = {}
    for unit_state in approved:
        if unit_state.image_path:
            image_path: Path = Path(unit_state.image_path)
            if image_path.exists():
                image_paths[unit_state.unit_key] = image_path

    if not image_paths:
        status_list = _build_conversion_status_list(session)
        return session, status_list, "Keine gueltigen Bilddateien gefunden."

    # GLB-Ausgabeverzeichnis
    session_dir: Path = STATE_DIR / session.session_id
    glb_dir: Path = session_dir / "glb"
    glb_dir.mkdir(parents=True, exist_ok=True)

    hf_token: str = _load_hf_token()
    space_id: str = _load_trellis_space()
    total: int = len(image_paths)

    def progress_cb(current: int, total_count: int, unit_key: str) -> None:
        progress((current, total_count), desc=f"Konvertiere: {unit_key}")

    results: dict[str, Path | None] = convert_batch(
        image_paths=image_paths,
        output_dir=glb_dir,
        hf_token=hf_token if hf_token else None,
        preprocess=True,
        progress_callback=progress_cb,
        space_id=space_id,
    )

    success_count: int = 0
    error_count: int = 0

    for unit_key, glb_path in results.items():
        if glb_path is not None:
            session.update_status(
                unit_key,
                UnitStatus.GLB_READY,
                glb_path=str(glb_path),
            )
            success_count += 1
        else:
            error_count += 1

    session.save()

    status_list = _build_conversion_status_list(session)
    message: str = f"Konvertierung abgeschlossen: {success_count} erfolgreich, {error_count} fehlgeschlagen."
    return session, status_list, message


def _build_conversion_status_list(session: PipelineSession) -> str:
    """Erstellt eine Statusliste aller Einheiten fuer die 3D-Konvertierung.

    Args:
        session: Aktive Pipeline-Session.

    Returns:
        Mehrzeiliger Statustext.
    """
    lines: list[str] = []
    for unit_state in session.get_all_units():
        status_text: str = _status_to_german(unit_state.status)
        glb_info: str = ""
        if unit_state.glb_path:
            glb_name: str = Path(unit_state.glb_path).name
            glb_info = f" -> {glb_name}"

        lines.append(f"  {unit_state.unit_name}: {status_text}{glb_info}")

    if not lines:
        return "Keine Einheiten in der Session."

    return "\n".join(lines)


# =============================================================================
# TAB 5: EXPORT
# =============================================================================

def _handle_export(
    session: PipelineSession | None,
    army: OPRArmy | None,
) -> tuple[PipelineSession | None, str]:
    """Exportiert fertige GLB-Dateien und units.json nach OpenTTS.

    Args:
        session: Aktive Pipeline-Session.
        army: Geladene Armee.

    Returns:
        Tuple: (session, result_message).
    """
    if session is None:
        return None, "Keine aktive Session."

    if army is None:
        return session, "Keine Armee geladen. Bitte zuerst eine Armee laden."

    unit_states: list[UnitState] = session.get_all_units()

    result: ExportResult = export_army(
        army=army,
        unit_states=unit_states,
        project_root=PROJECT_ROOT,
    )

    if result.success:
        # Status der exportierten Units aktualisieren
        for unit_state in unit_states:
            if unit_state.status == UnitStatus.GLB_READY:
                session.update_status(unit_state.unit_key, UnitStatus.EXPORTED)

        session.save()

        message: str = (
            f"Export erfolgreich!\n\n"
            f"Exportierte Einheiten: {result.exported_count}\n"
            f"units.json: {result.units_json_path}\n"
            f"GLB-Verzeichnis: {result.glb_dir}"
        )
        if result.errors:
            message += f"\n\nWarnungen:\n" + "\n".join(f"  - {e}" for e in result.errors)

        return session, message

    error_text: str = "\n".join(f"  - {e}" for e in result.errors) if result.errors else "Unbekannter Fehler"
    return session, f"Export fehlgeschlagen:\n{error_text}"


def _build_export_summary(session: PipelineSession | None) -> str:
    """Erstellt eine Zusammenfassung fuer den Export-Tab.

    Args:
        session: Aktive Pipeline-Session.

    Returns:
        Zusammenfassungstext.
    """
    if session is None:
        return "Keine aktive Session."

    progress_data: dict[str, int] = session.get_progress()
    total: int = progress_data["total"]
    ready: int = progress_data["converted"]
    exported: int = progress_data["exported"]
    approved: int = progress_data["approved"]

    lines: list[str] = [
        f"Einheiten gesamt: {total}",
        f"Bereit zum Export (GLB fertig): {ready}",
        f"Bereits exportiert: {exported}",
        f"Genehmigt (noch nicht konvertiert): {approved}",
        "",
        f"Exportierbar: {ready} Einheiten",
    ]

    return "\n".join(lines)


# =============================================================================
# TAB 3: HILFSFUNKTIONEN
# =============================================================================

def _build_unit_choices(session: PipelineSession | None) -> list[tuple[str, str]]:
    """Erstellt Choices fuer die Unit-Auswahl CheckboxGroup.

    Args:
        session: Aktive Pipeline-Session.

    Returns:
        Liste von (label, value) Tuples fuer CheckboxGroup.
    """
    if session is None:
        return []

    choices: list[tuple[str, str]] = []
    for unit_state in session.get_all_units():
        if not unit_state.prompt:
            continue
        choices.append((unit_state.unit_name, unit_state.unit_key))

    return choices


def _build_status_summary(session: PipelineSession | None) -> str:
    """Erstellt eine Markdown-Status-Zusammenfassung fuer den Bilder-Tab.

    Args:
        session: Aktive Pipeline-Session.

    Returns:
        Markdown-formatierter Statustext.
    """
    if session is None:
        return ""

    total: int = 0
    approved: int = 0
    rejected: int = 0
    pending: int = 0

    for unit_state in session.get_all_units():
        total += 1
        if unit_state.status == UnitStatus.IMAGE_APPROVED:
            approved += 1
        elif unit_state.status == UnitStatus.IMAGE_REJECTED:
            rejected += 1
        elif unit_state.status in (UnitStatus.GLB_READY, UnitStatus.EXPORTED):
            approved += 1
        elif unit_state.status in (UnitStatus.PENDING, UnitStatus.PROMPT_GENERATED, UnitStatus.IMAGE_GENERATED):
            pending += 1

    if total == 0:
        return ""

    return f"**Status:** {approved} genehmigt, {rejected} abgelehnt, {pending} ausstehend von {total} Einheiten"


# =============================================================================
# APP ERSTELLEN
# =============================================================================

def create_app() -> gr.Blocks:
    """Erstellt und konfiguriert die Gradio Web-UI.

    Returns:
        Konfigurierte gr.Blocks-Instanz.
    """
    available_design_languages: list[str] = _scan_design_languages()
    available_sessions: list[str] = _scan_existing_sessions()
    image_model_choices: list[str] = [m.name for m in ImageModel]

    with gr.Blocks(
        title="Model Forge - OpenTTS 3D Pipeline",
    ) as demo:

        # =================================================================
        # GLOBALER STATE
        # =================================================================

        army_state: gr.State = gr.State(value=None)
        session_state: gr.State = gr.State(value=None)
        selected_unit_key_state: gr.State = gr.State(value="")

        gr.Markdown("# Model Forge - Automatisierte 3D-Modell-Pipeline")
        gr.Markdown("OPR Share-Link -> Design Language -> Bildgenerierung -> Review -> 3D-Konvertierung -> Export")

        # =================================================================
        # TAB 1: ARMEE LADEN
        # =================================================================

        with gr.Tab("Armee laden"):
            load_mode_radio: gr.Radio = gr.Radio(
                choices=["OPR Share-Link", "Design Language Only"],
                value="OPR Share-Link",
                label="Lade-Modus",
            )

            with gr.Row():
                with gr.Column(scale=2):
                    share_link_input: gr.Textbox = gr.Textbox(
                        label="Share-Link oder List-ID",
                        placeholder="https://army-forge.onepagerules.com/share?id=... oder direkt die ID",
                    )
                    load_army_btn: gr.Button = gr.Button(
                        "Armee laden",
                        variant="primary",
                    )

                with gr.Column(scale=1):
                    design_language_dropdown: gr.Dropdown = gr.Dropdown(
                        choices=available_design_languages,
                        label="Design Language",
                        info="Wird automatisch erkannt, falls vorhanden",
                    )

            army_summary_text: gr.Textbox = gr.Textbox(
                label="Zusammenfassung",
                interactive=False,
                lines=6,
            )

            army_dataframe: gr.Dataframe = gr.Dataframe(
                headers=["Name", "Groesse", "Punkte", "Qualitaet", "Verteidigung", "Base"],
                label="Einheiten-Uebersicht",
                interactive=False,
            )

            gr.Markdown("---")
            gr.Markdown("### Session-Verwaltung")

            with gr.Row():
                with gr.Column():
                    new_session_btn: gr.Button = gr.Button(
                        "Neue Session starten",
                        variant="primary",
                    )

                with gr.Column():
                    session_dropdown: gr.Dropdown = gr.Dropdown(
                        choices=available_sessions,
                        label="Bestehende Session fortsetzen",
                        info="Neueste Sessions zuerst",
                    )
                    resume_session_btn: gr.Button = gr.Button(
                        "Session fortsetzen",
                    )

            session_status_text: gr.Textbox = gr.Textbox(
                label="Session-Status",
                interactive=False,
                lines=4,
            )

            # Faction-Folder als Hidden State
            faction_folder_state: gr.State = gr.State(value="")

            # --- Event Handler: Modus-Wechsel ---

            def on_mode_change(
                mode: str,
            ) -> tuple[Any, Any]:
                """Blendet Share-Link Feld je nach Modus ein/aus."""
                is_share_link: bool = mode == "OPR Share-Link"
                return (
                    gr.update(visible=is_share_link),
                    gr.update(
                        value="Armee laden" if is_share_link else "Aus Design Language laden",
                    ),
                )

            load_mode_radio.change(
                fn=on_mode_change,
                inputs=[load_mode_radio],
                outputs=[share_link_input, load_army_btn],
            )

            # --- Event Handler: Armee laden ---

            def on_load_army(
                mode: str,
                share_link: str,
                dl_name: str,
            ) -> tuple[list[list[str]], str, str, Any, OPRArmy | None]:
                """Laedt Armee je nach Modus (Share-Link oder DL-Only)."""
                if mode == "Design Language Only":
                    return _handle_load_from_design_language(dl_name)

                if not share_link or not share_link.strip():
                    return (
                        [],
                        "Bitte Share-Link oder List-ID eingeben.",
                        "",
                        gr.update(),
                        None,
                    )

                try:
                    army: OPRArmy = fetch_army(share_link)
                except Exception as exc:
                    return [], f"Fehler beim Laden: {exc}", "", gr.update(), None

                rows: list[list[str]] = _army_to_dataframe(army)
                summary: str = _army_summary(army)

                dl_update: Any = gr.update()
                detected: str | None = _auto_detect_design_language(army.faction_folder)
                if detected is not None:
                    dl_update = gr.update(value=detected)

                return rows, summary, army.faction_folder, dl_update, army

            load_army_btn.click(
                fn=on_load_army,
                inputs=[load_mode_radio, share_link_input, design_language_dropdown],
                outputs=[
                    army_dataframe,
                    army_summary_text,
                    faction_folder_state,
                    design_language_dropdown,
                    army_state,
                ],
            )

            # Session-Event-Handler werden nach Tab 2 registriert (cross-tab outputs)

        # =================================================================
        # TAB 2: PROMPTS
        # =================================================================

        with gr.Tab("Prompts"):
            gr.Markdown("### Prompt-Generierung und -Bearbeitung")
            gr.Markdown(
                "Prompts werden aus der Design Language und den Einheitsdaten generiert. "
                "Einzelne Prompts koennen im Dataframe manuell angepasst werden."
            )

            general_prompt_input: gr.Textbox = gr.Textbox(
                label="General-Prompt (wird an alle Unit-Prompts angehaengt)",
                placeholder="z.B. 'All armor is painted deep red with gold trim'",
                lines=3,
            )

            generate_prompts_btn: gr.Button = gr.Button(
                "Alle Prompts generieren",
                variant="primary",
            )

            prompts_dataframe: gr.Dataframe = gr.Dataframe(
                headers=["Unit Key", "Name", "Prompt"],
                label="Prompts pro Einheit",
                interactive=True,
                wrap=True,
                column_widths=["15%", "15%", "70%"],
            )

            with gr.Row():
                save_prompts_btn: gr.Button = gr.Button(
                    "Aenderungen speichern",
                )
                prompts_status_text: gr.Textbox = gr.Textbox(
                    label="Status",
                    interactive=False,
                )

            # --- Event Handler: Prompts generieren ---

            # Prompt-Generierung wird als Cross-Tab Handler unten registriert

            # --- Event Handler: Prompts speichern ---

            def on_save_prompts(
                session: PipelineSession | None,
                df_data: list[list[str]],
                general_prompt: str,
            ) -> tuple[PipelineSession | None, str]:
                if session is not None:
                    session.general_prompt = general_prompt
                return _handle_update_prompts_from_dataframe(session, df_data)

            save_prompts_btn.click(
                fn=on_save_prompts,
                inputs=[session_state, prompts_dataframe, general_prompt_input],
                outputs=[session_state, prompts_status_text],
            )

        # =================================================================
        # TAB 3: BILDER GENERIEREN
        # =================================================================

        with gr.Tab("Bilder generieren"):
            gr.Markdown("### Bildgenerierung via HuggingFace Spaces")

            with gr.Row():
                image_model_dropdown: gr.Dropdown = gr.Dropdown(
                    choices=image_model_choices,
                    value=ImageModel.NANO_BANANA.name,
                    label="Bildgenerierungs-Modell",
                )
                generate_images_btn: gr.Button = gr.Button(
                    "Ausgewaehlte Bilder generieren",
                    variant="primary",
                )
                regenerate_rejected_btn: gr.Button = gr.Button(
                    "Abgelehnte regenerieren",
                )

            with gr.Accordion("Einheiten-Auswahl", open=True):
                unit_selection_checkboxes: gr.CheckboxGroup = gr.CheckboxGroup(
                    choices=[],
                    label="Einheiten zum Generieren auswaehlen",
                )
                with gr.Row():
                    select_all_btn: gr.Button = gr.Button("Alle auswaehlen", size="sm")
                    select_none_btn: gr.Button = gr.Button("Keine auswaehlen", size="sm")

            image_status_summary: gr.Markdown = gr.Markdown("")

            image_gallery: gr.Gallery = gr.Gallery(
                label="Generierte Bilder",
                columns=4,
                height="auto",
                object_fit="contain",
            )

            with gr.Row():
                with gr.Column(scale=2):
                    unit_info_text: gr.Textbox = gr.Textbox(
                        label="Einheitsinfo (ausgewaehltes Bild)",
                        interactive=False,
                        lines=6,
                    )

                with gr.Column(scale=1):
                    approve_btn: gr.Button = gr.Button(
                        "Genehmigen",
                        variant="primary",
                    )
                    reject_btn: gr.Button = gr.Button(
                        "Ablehnen",
                        variant="stop",
                    )
                    rejection_feedback_input: gr.Textbox = gr.Textbox(
                        label="Was soll geaendert werden?",
                        placeholder="z.B. 'Waffe groesser', 'Andere Pose', 'Hellere Farben'...",
                        lines=2,
                    )

            images_status_text: gr.Textbox = gr.Textbox(
                label="Status",
                interactive=False,
            )

            # --- Event Handler: Alle/Keine auswaehlen ---

            def on_select_all(
                session: PipelineSession | None,
            ) -> Any:
                choices: list[tuple[str, str]] = _build_unit_choices(session)
                all_keys: list[str] = [key for _, key in choices]
                return gr.update(value=all_keys)

            select_all_btn.click(
                fn=on_select_all,
                inputs=[session_state],
                outputs=[unit_selection_checkboxes],
            )

            def on_select_none() -> Any:
                return gr.update(value=[])

            select_none_btn.click(
                fn=on_select_none,
                inputs=[],
                outputs=[unit_selection_checkboxes],
            )

            # --- Event Handler: Alle Bilder generieren ---

            def on_generate_images(
                session: PipelineSession | None,
                model_name: str,
                selected_keys: list[str],
                progress: gr.Progress = gr.Progress(),
            ) -> tuple[PipelineSession | None, list[tuple[str, str]], str, str]:
                session_out, gallery, status = _handle_generate_all_images(
                    session, model_name, progress, selected_keys=selected_keys,
                )
                summary: str = _build_status_summary(session_out)
                return session_out, gallery, status, summary

            generate_images_btn.click(
                fn=on_generate_images,
                inputs=[session_state, image_model_dropdown, unit_selection_checkboxes],
                outputs=[session_state, image_gallery, images_status_text, image_status_summary],
            )

            # --- Event Handler: Abgelehnte regenerieren ---

            def on_regenerate_rejected(
                session: PipelineSession | None,
                model_name: str,
                progress: gr.Progress = gr.Progress(),
            ) -> tuple[PipelineSession | None, list[tuple[str, str]], str, str]:
                session_out, gallery, status = _handle_regenerate_rejected(session, model_name, progress)
                summary: str = _build_status_summary(session_out)
                return session_out, gallery, status, summary

            regenerate_rejected_btn.click(
                fn=on_regenerate_rejected,
                inputs=[session_state, image_model_dropdown],
                outputs=[session_state, image_gallery, images_status_text, image_status_summary],
            )

            # --- Event Handler: Gallery-Auswahl ---

            def on_gallery_select(
                session: PipelineSession | None,
                evt: gr.SelectData,
            ) -> tuple[str, str]:
                return _handle_gallery_select(session, evt)

            image_gallery.select(
                fn=on_gallery_select,
                inputs=[session_state],
                outputs=[selected_unit_key_state, unit_info_text],
            )

            # --- Event Handler: Genehmigen ---

            def on_approve(
                session: PipelineSession | None,
                unit_key: str,
            ) -> tuple[PipelineSession | None, list[tuple[str, str]], str, str]:
                session_out, gallery, status = _handle_approve_image(session, unit_key)
                summary: str = _build_status_summary(session_out)
                return session_out, gallery, status, summary

            approve_btn.click(
                fn=on_approve,
                inputs=[session_state, selected_unit_key_state],
                outputs=[session_state, image_gallery, images_status_text, image_status_summary],
            )

            # --- Event Handler: Ablehnen ---

            def on_reject(
                session: PipelineSession | None,
                unit_key: str,
                feedback: str,
            ) -> tuple[PipelineSession | None, list[tuple[str, str]], str, str]:
                session_out, gallery, status = _handle_reject_image(
                    session, unit_key, feedback=feedback,
                )
                summary: str = _build_status_summary(session_out)
                return session_out, gallery, status, summary

            reject_btn.click(
                fn=on_reject,
                inputs=[session_state, selected_unit_key_state, rejection_feedback_input],
                outputs=[session_state, image_gallery, images_status_text, image_status_summary],
            )

        # =================================================================
        # TAB 4: 3D-KONVERTIERUNG
        # =================================================================

        with gr.Tab("3D-Konvertierung"):
            gr.Markdown("### TRELLIS 3D-Konvertierung")
            gr.Markdown(
                "Konvertiert genehmigte Bilder (Status: IMAGE_APPROVED) "
                "via TRELLIS zu GLB-3D-Modellen."
            )

            convert_btn: gr.Button = gr.Button(
                "Genehmigte Bilder konvertieren",
                variant="primary",
            )

            conversion_status_list: gr.Textbox = gr.Textbox(
                label="Konvertierungsstatus",
                interactive=False,
                lines=15,
            )

            conversion_status_msg: gr.Textbox = gr.Textbox(
                label="Status",
                interactive=False,
            )

            # --- Event Handler: Konvertieren ---

            def on_convert(
                session: PipelineSession | None,
                progress: gr.Progress = gr.Progress(),
            ) -> tuple[PipelineSession | None, str, str]:
                return _handle_convert_approved(session, progress)

            convert_btn.click(
                fn=on_convert,
                inputs=[session_state],
                outputs=[session_state, conversion_status_list, conversion_status_msg],
            )

        # =================================================================
        # TAB 5: EXPORT
        # =================================================================

        with gr.Tab("Export"):
            gr.Markdown("### Export nach OpenTTS")
            gr.Markdown(
                "Exportiert fertige GLB-Dateien und units.json in das OpenTTS-Projektverzeichnis "
                f"(`{PROJECT_ROOT / 'assets' / 'miniatures'}`)."
            )

            export_summary_text: gr.Textbox = gr.Textbox(
                label="Export-Zusammenfassung",
                interactive=False,
                lines=6,
            )

            export_btn: gr.Button = gr.Button(
                "Nach OpenTTS exportieren",
                variant="primary",
            )

            export_result_text: gr.Textbox = gr.Textbox(
                label="Export-Ergebnis",
                interactive=False,
                lines=8,
            )

            # --- Zusammenfassung aktualisieren wenn Tab geoeffnet ---

            def on_export_tab_select(
                session: PipelineSession | None,
            ) -> str:
                return _build_export_summary(session)

            # --- Event Handler: Exportieren ---

            def on_export(
                session: PipelineSession | None,
                army: OPRArmy | None,
            ) -> tuple[PipelineSession | None, str, str]:
                session_out, result_msg = _handle_export(session, army)
                summary: str = _build_export_summary(session_out)
                return session_out, summary, result_msg

            export_btn.click(
                fn=on_export,
                inputs=[session_state, army_state],
                outputs=[session_state, export_summary_text, export_result_text],
            )

        # =================================================================
        # TAB 6: EINSTELLUNGEN
        # =================================================================

        with gr.Tab("Einstellungen"):
            gr.Markdown("### Konfiguration")

            with gr.Group():
                gr.Markdown("#### HuggingFace Token")
                gr.Markdown(
                    "Wird fuer die Bildgenerierung und 3D-Konvertierung benoetigt. "
                    "Der Token wird lokal in `.hf_token` gespeichert."
                )

                hf_token_input: gr.Textbox = gr.Textbox(
                    label="HuggingFace Token",
                    type="password",
                    value=_load_hf_token,
                    placeholder="hf_...",
                )

                save_token_btn: gr.Button = gr.Button(
                    "Token speichern",
                )

                token_status_text: gr.Textbox = gr.Textbox(
                    label="Status",
                    interactive=False,
                )

            with gr.Group():
                gr.Markdown("#### Google Gemini API Key")
                gr.Markdown(
                    "Wird fuer das Nano Banana Modell (Gemini 2.5 Flash Image) benoetigt. "
                    "Der Key wird lokal in `.gemini_key` gespeichert. "
                    "Free Tier: 2 Bilder/Minute."
                )

                gemini_key_input: gr.Textbox = gr.Textbox(
                    label="Gemini API Key",
                    type="password",
                    value=_load_gemini_key,
                    placeholder="AIza...",
                )

                save_gemini_key_btn: gr.Button = gr.Button(
                    "Gemini Key speichern",
                )

                gemini_key_status_text: gr.Textbox = gr.Textbox(
                    label="Status",
                    interactive=False,
                )

            with gr.Group():
                gr.Markdown("#### TRELLIS Space")
                gr.Markdown(
                    "Space fuer die 3D-Konvertierung mit TRELLIS.2. "
                    "Ein eigener Space mit dedizierter GPU (z.B. Nvidia A10G) "
                    "umgeht das ZeroGPU-Tageslimit. "
                    "Default: `microsoft/TRELLIS.2` (ZeroGPU, Quota-begrenzt)."
                )

                trellis_space_input: gr.Textbox = gr.Textbox(
                    label="Space-ID",
                    value=_load_trellis_space,
                    placeholder="owner/space-name",
                    info="z.B. DutchyMaxwell/TRELLIS-2 (dediziert) oder microsoft/TRELLIS.2 (ZeroGPU)",
                )

                save_trellis_space_btn: gr.Button = gr.Button(
                    "Space-ID speichern",
                )

                trellis_space_status_text: gr.Textbox = gr.Textbox(
                    label="Status",
                    interactive=False,
                )

            with gr.Group():
                gr.Markdown("#### Standard-Modell")
                default_model_dropdown: gr.Dropdown = gr.Dropdown(
                    choices=image_model_choices,
                    value=ImageModel.NANO_BANANA.name,
                    label="Standard Bildgenerierungs-Modell",
                    info="Wird als Vorauswahl im Tab 'Bilder generieren' verwendet",
                )

            with gr.Group():
                gr.Markdown("#### Pfade")
                gr.Textbox(
                    label="Projekt-Root",
                    value=str(PROJECT_ROOT),
                    interactive=False,
                )
                gr.Textbox(
                    label="Design Languages",
                    value=str(DESIGN_LANGUAGES_DIR),
                    interactive=False,
                )
                gr.Textbox(
                    label="Session-Verzeichnis",
                    value=str(STATE_DIR),
                    interactive=False,
                )
                gr.Textbox(
                    label="Output-Verzeichnis",
                    value=str(OUTPUT_DIR),
                    interactive=False,
                )

            # --- Event Handler: Token speichern ---

            def on_save_token(token: str) -> str:
                return _save_hf_token(token)

            save_token_btn.click(
                fn=on_save_token,
                inputs=[hf_token_input],
                outputs=[token_status_text],
            )

            # --- Event Handler: Gemini Key speichern ---

            def on_save_gemini_key(key: str) -> str:
                return _save_gemini_key(key)

            save_gemini_key_btn.click(
                fn=on_save_gemini_key,
                inputs=[gemini_key_input],
                outputs=[gemini_key_status_text],
            )

            # --- Event Handler: TRELLIS Space-ID speichern ---

            def on_save_trellis_space(space_id: str) -> str:
                return _save_trellis_space(space_id)

            save_trellis_space_btn.click(
                fn=on_save_trellis_space,
                inputs=[trellis_space_input],
                outputs=[trellis_space_status_text],
            )

        # =================================================================
        # CROSS-TAB EVENT HANDLER
        # =================================================================

        # --- Session erstellen (Tab 1 -> Tab 2 + Tab 3) ---

        def on_new_session(
            army: OPRArmy | None,
            share_link: str,
        ) -> tuple[OPRArmy | None, PipelineSession | None, str, str, Any, list[tuple[str, str]], str]:
            army_out, session_out, status = _handle_new_session(army, share_link)
            gp: str = session_out.general_prompt if session_out is not None else ""
            choices: list[tuple[str, str]] = _build_unit_choices(session_out)
            all_keys: list[str] = [key for _, key in choices]
            gallery: list[tuple[str, str]] = _build_gallery(session_out) if session_out is not None else []
            summary: str = _build_status_summary(session_out)
            return army_out, session_out, status, gp, gr.update(choices=choices, value=all_keys), gallery, summary

        new_session_btn.click(
            fn=on_new_session,
            inputs=[army_state, share_link_input],
            outputs=[
                army_state, session_state, session_status_text, general_prompt_input,
                unit_selection_checkboxes, image_gallery, image_status_summary,
            ],
        )

        # --- Session fortsetzen (Tab 1 -> Tab 2 + Tab 3) ---

        def on_resume_session(
            session_id: str,
        ) -> tuple[PipelineSession | None, str, str, Any, list[tuple[str, str]], str]:
            session_out, status = _handle_resume_session(session_id)
            gp: str = session_out.general_prompt if session_out is not None else ""
            choices: list[tuple[str, str]] = _build_unit_choices(session_out)
            all_keys: list[str] = [key for _, key in choices]
            gallery: list[tuple[str, str]] = _build_gallery(session_out) if session_out is not None else []
            summary: str = _build_status_summary(session_out)
            return session_out, status, gp, gr.update(choices=choices, value=all_keys), gallery, summary

        resume_session_btn.click(
            fn=on_resume_session,
            inputs=[session_dropdown],
            outputs=[
                session_state, session_status_text, general_prompt_input,
                unit_selection_checkboxes, image_gallery, image_status_summary,
            ],
        )

        # --- Prompts generieren (Tab 2 -> Tab 3 CheckboxGroup) ---

        def on_generate_prompts(
            session: PipelineSession | None,
            army: OPRArmy | None,
            dl_name: str,
            general_prompt: str,
        ) -> tuple[PipelineSession | None, list[list[str]], str, str, Any]:
            if session is not None:
                session.general_prompt = general_prompt
            session_out, rows, status = _handle_generate_all_prompts(session, army, dl_name)
            gp: str = session_out.general_prompt if session_out is not None else ""
            choices: list[tuple[str, str]] = _build_unit_choices(session_out)
            all_keys: list[str] = [key for _, key in choices]
            return session_out, rows, status, gp, gr.update(choices=choices, value=all_keys)

        generate_prompts_btn.click(
            fn=on_generate_prompts,
            inputs=[session_state, army_state, design_language_dropdown, general_prompt_input],
            outputs=[
                session_state, prompts_dataframe, prompts_status_text,
                general_prompt_input, unit_selection_checkboxes,
            ],
        )

    return demo


# =============================================================================
# HAUPTPROGRAMM
# =============================================================================

if __name__ == "__main__":
    demo: gr.Blocks = create_app()
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False,
        inbrowser=True,
    )
