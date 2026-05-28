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
import time
from collections import deque
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


# =============================================================================
# AUTO-RECOVERY-KONSTANTEN (TRELLIS-Broken-State)
# =============================================================================
# Ein extract_glb-Crash wedged das A100-Backend: alle weiteren Aufrufe failen
# in Sekunden, obwohl Stage=RUNNING bleibt. Erkennung: Fehler in <FAST_FAIL_S
# = unmoeglich schnell fuer echte Generierung (130-230s). Dann Space neu
# starten und Unit erneut versuchen.
FAST_FAIL_SECONDS: float = 20.0
MAX_RESTARTS: int = 10             # Restart-Budget pro Batch (A100-Boot kostet ~3-5min)
MAX_ATTEMPTS_PER_UNIT: int = 2     # deterministische Crasher nicht endlos retryen
RESTART_TIMEOUT_SECONDS: float = 480.0
RESTART_POLL_SECONDS: float = 10.0
POST_RESTART_BUFFER_SECONDS: float = 15.0  # Modell-Load-Puffer nach RUNNING


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


def _reset_generator() -> None:
    """Verwirft die gecachte Generator-Instanz, damit der naechste Aufruf
    eine frische GradioClient-Verbindung zum (neu gestarteten) Space aufbaut."""
    global _generator  # noqa: PLW0603
    _generator = None


def _restart_space_and_wait(
    space_id: str | None,
    hf_token: str | None,
    status_cb: "Callable[[str], None]",
    log: "Callable[[str], None]",
) -> bool:
    """Startet den HF-Space neu (restart_space) und wartet bis Stage=RUNNING.

    Returns True wenn der Space wieder RUNNING ist, sonst False. Setzt bei
    Erfolg den Generator-Cache zurueck (frische Verbindung noetig).
    """
    if not space_id or not hf_token:
        log("Auto-Restart nicht moeglich: space_id oder hf_token fehlt")
        return False
    try:
        from huggingface_hub import HfApi
    except ImportError:
        log("huggingface_hub fehlt — Auto-Restart nicht moeglich")
        return False

    api = HfApi()
    try:
        status_cb("TRELLIS haengt (broken state) → starte Space neu…")
        api.restart_space(space_id, token=hf_token)
    except Exception as exc:
        log(f"restart_space fehlgeschlagen: {exc}")
        return False

    deadline = time.time() + RESTART_TIMEOUT_SECONDS
    while time.time() < deadline:
        try:
            stage = str(api.get_space_runtime(space_id, token=hf_token).stage)
        except Exception as exc:
            stage = f"?({exc})"
        secs = int(time.time() - (deadline - RESTART_TIMEOUT_SECONDS))
        status_cb(f"Warte auf TRELLIS-Neustart… Stage={stage} (+{secs}s)")
        if stage == "RUNNING":
            time.sleep(POST_RESTART_BUFFER_SECONDS)  # Modell-Load abwarten
            _reset_generator()
            log("TRELLIS wieder RUNNING nach Restart")
            return True
        time.sleep(RESTART_POLL_SECONDS)

    log("Timeout beim Warten auf TRELLIS-RUNNING nach Restart")
    return False


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
    unit_class: str | None = None,
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
        unit_class: Optionaler UnitClass-Wert (str). Steuert das
                    Decimation-Target via DECIMATION_BY_CLASS in trellis_core.

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
        unit_class=unit_class,
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
    unit_classes: dict[str, str] | None = None,
    status_callback: Callable[[str], None] | None = None,
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
        unit_classes: Mapping von Unit-Key zu UnitClass-Wert. Steuert pro Unit
                      das Decimation-Target (Titans brauchen 300000 statt 100000).

    Returns:
        Mapping von Unit-Key zu GLB-Pfad (oder None bei Fehler).
    """
    log: Callable[[str], None] = log_callback or logger.info
    status: Callable[[str], None] = status_callback or (lambda _msg: None)
    total: int = len(image_paths)
    results: dict[str, Path | None] = {}

    if total == 0:
        log("Keine Bilder zum Konvertieren.")
        return results

    log(f"Starte Batch-Konvertierung: {total} Bilder")
    classes_map: dict[str, str] = unit_classes or {}

    # Queue-basiert mit Auto-Recovery: bei einem Fehler ist das TRELLIS-Backend
    # wahrscheinlich wedged (siehe Konstanten oben). Dann Space neu starten und
    # die Unit erneut versuchen — mit Restart-Budget und Per-Unit-Attempt-Cap.
    queue: deque[tuple[str, Path]] = deque(image_paths.items())
    attempts: dict[str, int] = {}
    restarts: int = 0

    def _done_count() -> int:
        return sum(1 for k in image_paths if k in results)

    while queue:
        unit_key, image_path = queue.popleft()
        attempts[unit_key] = attempts.get(unit_key, 0) + 1

        if progress_callback is not None:
            progress_callback(_done_count(), total, unit_key)
        log(f"[{_done_count() + 1}/{total}] {unit_key} (Versuch {attempts[unit_key]})")

        t0 = time.time()
        glb_path: Path | None = convert_image_to_glb(
            image_path=image_path,
            output_dir=output_dir,
            hf_token=hf_token,
            preprocess=preprocess,
            log_callback=log_callback,
            space_id=space_id,
            unit_class=classes_map.get(unit_key),
        )
        elapsed = time.time() - t0

        if glb_path is not None:
            results[unit_key] = glb_path
            continue

        # Fehler. Backend ist nach jedem Fehler potenziell wedged.
        too_fast = elapsed < FAST_FAIL_SECONDS
        log(f"Fehlschlag {unit_key} nach {elapsed:.0f}s"
            f"{' (zu schnell → Backend wedged)' if too_fast else ' (crashte evtl. das Backend)'}")

        will_retry = attempts[unit_key] < MAX_ATTEMPTS_PER_UNIT

        # Restart nur sinnvoll, wenn danach noch was zu tun ist: diese Unit
        # nochmal ODER weitere in der Queue. Sonst (letzte Unit, aufgegeben)
        # spart man sich den teuren A100-Boot.
        if not will_retry and not queue:
            log(f"{unit_key}: {attempts[unit_key]} Versuche gescheitert — aufgegeben "
                f"(letzte Unit, kein Restart noetig)")
            results[unit_key] = None
            continue

        if restarts >= MAX_RESTARTS:
            log(f"Restart-Budget ({MAX_RESTARTS}) erschoepft — {unit_key} wird uebersprungen")
            results[unit_key] = None
            continue

        # Backend un-wedgen: Space neu starten und auf RUNNING warten.
        if not _restart_space_and_wait(space_id, hf_token, status, log):
            log("Restart fehlgeschlagen — Batch kann nicht fortgesetzt werden")
            results[unit_key] = None
            # restliche Queue als fehlgeschlagen markieren
            while queue:
                k, _ = queue.popleft()
                results.setdefault(k, None)
            break
        restarts += 1
        status(f"TRELLIS neu gestartet ({restarts}/{MAX_RESTARTS}) — setze fort")

        # Unit erneut in die Queue, falls Attempt-Budget bleibt; sonst aufgeben
        # (deterministische Crasher blockieren so nicht die restlichen Units).
        if will_retry:
            queue.appendleft((unit_key, image_path))
        else:
            log(f"{unit_key}: {attempts[unit_key]} Versuche gescheitert — aufgegeben")
            results[unit_key] = None

    # Zusammenfassung
    succeeded: int = sum(1 for path in results.values() if path is not None)
    failed: int = total - succeeded
    log(f"Batch abgeschlossen: {succeeded} erfolgreich, {failed} fehlgeschlagen "
        f"({restarts} TRELLIS-Restarts)")

    return results
