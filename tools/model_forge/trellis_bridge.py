"""
TRELLIS Bridge fuer Model Forge
================================

Bridge-Modul das den TrellisGenerator aus der 3D-Pipeline importiert
und fuer die Model Forge verfuegbar macht. Cached die Generator-Instanz
fuer wiederholte Aufrufe.

Abhaengigkeit: assets/3d_pipeline/trellis_core.py
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


# =============================================================================
# PROJEKT-PFADE
# =============================================================================

_PROJECT_ROOT: Path = Path(__file__).parent.parent.parent
_PIPELINE_DIR: Path = _PROJECT_ROOT / "assets" / "3d_pipeline"

logger: logging.Logger = logging.getLogger(__name__)


# =============================================================================
# TRELLIS-CORE IMPORT
# =============================================================================

def _ensure_pipeline_on_path() -> None:
    """Fuegt das 3D-Pipeline-Verzeichnis zu sys.path hinzu, falls noetig."""
    pipeline_str: str = str(_PIPELINE_DIR)
    if pipeline_str not in sys.path:
        sys.path.insert(0, pipeline_str)


_TRELLIS_AVAILABLE: bool = False

try:
    _ensure_pipeline_on_path()
    from trellis_core import TrellisGenerator, preprocess_image  # type: ignore[import-untyped]
    _TRELLIS_AVAILABLE = True
except ImportError:
    TrellisGenerator = None  # type: ignore[assignment,misc]
    preprocess_image = None  # type: ignore[assignment]
    logger.warning(
        "trellis_core nicht verfuegbar. "
        "Erwartet unter: %s/trellis_core.py",
        _PIPELINE_DIR,
    )


# =============================================================================
# GENERATOR-CACHE
# =============================================================================

_generator: TrellisGenerator | None = None  # type: ignore[assignment]


def _get_generator(
    hf_token: str | None = None,
    log_callback: Callable[[str], None] | None = None,
    space_id: str | None = None,
) -> TrellisGenerator:  # type: ignore[return]
    """
    Gibt die gecachte TrellisGenerator-Instanz zurueck.
    Erstellt sie beim ersten Aufruf. Bei geaenderter space_id wird
    die Instanz neu erstellt.

    Args:
        hf_token: Optionaler HuggingFace-Token fuer Pro-Quota.
        log_callback: Optionale Log-Funktion. Nur beim Erstellen relevant.
        space_id: Optionale HuggingFace Space-ID (z.B. "DutchyMaxwell/TRELLIS-2").

    Returns:
        TrellisGenerator-Instanz.

    Raises:
        ImportError: Wenn trellis_core nicht verfuegbar ist.
    """
    global _generator  # noqa: PLW0603

    if not _TRELLIS_AVAILABLE or TrellisGenerator is None:
        raise ImportError(
            "trellis_core ist nicht verfuegbar. "
            f"Stelle sicher, dass {_PIPELINE_DIR / 'trellis_core.py'} existiert "
            "und alle Abhaengigkeiten installiert sind (gradio_client, Pillow)."
        )

    if _generator is None:
        _generator = TrellisGenerator(
            hf_token=hf_token,
            log_callback=log_callback,
            space_id=space_id,
        )

    return _generator


# =============================================================================
# EINZELBILD-KONVERTIERUNG
# =============================================================================

def convert_image_to_glb(
    image_path: Path,
    output_dir: Path,
    hf_token: str | None = None,
    preprocess: bool = True,
    log_callback: Callable[[str], None] | None = None,
    space_id: str | None = None,
) -> Path | None:
    """
    Konvertiert ein einzelnes Bild zu einem GLB-3D-Modell via TRELLIS.

    Verwendet den gecachten TrellisGenerator. Beim ersten Aufruf wird
    die Verbindung zum HuggingFace Space hergestellt.

    Args:
        image_path: Pfad zum Eingabebild (.png, .jpg, .jpeg, .webp).
        output_dir: Zielverzeichnis fuer die GLB-Datei.
        hf_token: Optionaler HuggingFace-Token fuer Pro-Quota.
        preprocess: Bild vorverarbeiten (Wasserzeichen entfernen,
                    Hintergrund transparent machen).
        log_callback: Optionale Funktion fuer Log-Ausgaben.
        space_id: Optionale HuggingFace Space-ID (z.B. "DutchyMaxwell/TRELLIS-2").

    Returns:
        Pfad zur erzeugten GLB-Datei oder None bei Fehler.
    """
    log: Callable[[str], None] = log_callback or logger.info

    if not image_path.exists():
        log(f"FEHLER: Bilddatei nicht gefunden: {image_path}")
        return None

    try:
        generator: TrellisGenerator = _get_generator(  # type: ignore[assignment]
            hf_token=hf_token,
            log_callback=log_callback,
            space_id=space_id,
        )
    except ImportError as exc:
        log(f"FEHLER: {exc}")
        return None

    log(f"Konvertiere: {image_path.name}")
    result: Path | None = generator.convert(  # type: ignore[union-attr]
        image_path,
        output_dir,
        preprocess=preprocess,
    )

    if result is not None:
        log(f"Erfolgreich: {result.name}")
    else:
        log(f"Fehlgeschlagen: {image_path.name}")

    return result


# =============================================================================
# BATCH-KONVERTIERUNG
# =============================================================================

def convert_batch(
    image_paths: dict[str, Path],
    output_dir: Path,
    hf_token: str | None = None,
    preprocess: bool = True,
    progress_callback: Callable[[int, int, str], None] | None = None,
    log_callback: Callable[[str], None] | None = None,
    space_id: str | None = None,
) -> dict[str, Path | None]:
    """
    Konvertiert mehrere Bilder sequentiell zu GLB-3D-Modellen.

    TRELLIS unterstuetzt keine parallelen Anfragen, daher werden
    die Bilder nacheinander verarbeitet.

    Args:
        image_paths: Mapping von Unit-Key zu Bildpfad.
                     Beispiel: {"battle_brothers": Path("battle_brothers.png")}
        output_dir: Zielverzeichnis fuer alle GLB-Dateien.
        hf_token: Optionaler HuggingFace-Token fuer Pro-Quota.
        preprocess: Bilder vorverarbeiten.
        progress_callback: Optionale Fortschrittsfunktion.
                           Wird aufgerufen mit (current_index, total_count, unit_key).
        log_callback: Optionale Funktion fuer Log-Ausgaben.
        space_id: Optionale HuggingFace Space-ID (z.B. "DutchyMaxwell/TRELLIS-2").

    Returns:
        Mapping von Unit-Key zu GLB-Pfad (oder None bei Fehler).
    """
    log: Callable[[str], None] = log_callback or logger.info
    total: int = len(image_paths)
    results: dict[str, Path | None] = {}

    if total == 0:
        log("Keine Bilder zum Konvertieren.")
        return results

    log(f"Starte Batch-Konvertierung: {total} Bilder")

    for index, (unit_key, image_path) in enumerate(image_paths.items()):
        if progress_callback is not None:
            progress_callback(index, total, unit_key)

        log(f"[{index + 1}/{total}] {unit_key}")

        glb_path: Path | None = convert_image_to_glb(
            image_path=image_path,
            output_dir=output_dir,
            hf_token=hf_token,
            preprocess=preprocess,
            log_callback=log_callback,
            space_id=space_id,
        )
        results[unit_key] = glb_path

    # Zusammenfassung
    succeeded: int = sum(1 for path in results.values() if path is not None)
    failed: int = total - succeeded
    log(f"Batch abgeschlossen: {succeeded} erfolgreich, {failed} fehlgeschlagen")

    return results
