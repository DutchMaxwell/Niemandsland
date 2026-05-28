"""
Hero-First Workflow fuer Style-Konsistenz
==========================================

Pro Fraktion wird eine "Hero-Mini" (typischerweise der teuerste Charakter mit
Tough(12)+ und voller Detailtiefe) zuerst generiert + reviewed. Dieses Bild
dient als Style-Reference fuer alle weiteren Minis derselben Fraktion (via
reference_image_path in image_generator).

Hero-Unit-Bestimmung (Heuristik):
    1. Wenn Faction-YAML einen `hero_unit_key` Top-Level-Eintrag hat -> dieser
    2. Sonst: unter den unit_overrides die Unit mit hoechster `cost`,
       sekundaer hoechster `tough`-Wert (parsed aus rules)
    3. Falls keine Heuristik greift: erster unit_override

Reference-Image-Persistenz:
    assets/miniatures/{faction_folder}/_reference.webp

Diese Datei wird von batch_generate.py geladen und an image_generator
weitergegeben. Loeschen der Datei zwingt Neu-Generierung des Heros.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from prompt_engine import DesignLanguage


# =============================================================================
# KONSTANTEN
# =============================================================================

REFERENCE_IMAGE_FILENAME: str = "_reference.webp"
REFERENCE_VEHICLE_FILENAME: str = "_reference_vehicle.webp"
REFERENCE_WALKER_FILENAME: str = "_reference_walker.webp"
REFERENCE_AIRCRAFT_FILENAME: str = "_reference_aircraft.webp"
REFERENCE_TITAN_FILENAME: str = "_reference_titan.webp"
MINIATURES_DIR: str = "assets/miniatures"

# Pattern fuer Tough(N) Regel-Parsing
TOUGH_PATTERN: re.Pattern[str] = re.compile(r"^Tough\((\d+)\)$")

# Schwellwert fuer automatische Titan-Klassifikation aus Tough(N).
TITAN_TOUGH_THRESHOLD: int = 16


class UnitClass(str, Enum):
    """Visuelle Klasse einer Unit fuer Reference-Anchor-Auswahl.

    Bestimmt, welches Reference-Bild beim Image-Pinning verwendet wird:
        - INFANTRY: Hero-Reference (_reference.webp)
        - WALKER: Walker-Anchor (_reference_walker.webp) — Battlesuits, Mechs
        - VEHICLE: Vehicle-Anchor (_reference_vehicle.webp) — Tanks, Bikes,
          Transports
        - AIRCRAFT: Aircraft-Anchor (_reference_aircraft.webp) — Fighter, Bomber
        - TITAN: Titan-Anchor (_reference_titan.webp) — riesige Walker
    """

    INFANTRY = "infantry"
    WALKER = "walker"
    VEHICLE = "vehicle"
    AIRCRAFT = "aircraft"
    TITAN = "titan"


REFERENCE_FILENAMES: dict[UnitClass, str] = {
    UnitClass.INFANTRY: REFERENCE_IMAGE_FILENAME,
    UnitClass.WALKER: REFERENCE_WALKER_FILENAME,
    UnitClass.VEHICLE: REFERENCE_VEHICLE_FILENAME,
    UnitClass.AIRCRAFT: REFERENCE_AIRCRAFT_FILENAME,
    UnitClass.TITAN: REFERENCE_TITAN_FILENAME,
}

logger: logging.Logger = logging.getLogger(__name__)


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class HeroSelection:
    """Resultat der Hero-Auswahl fuer eine Fraktion."""

    unit_key: str
    unit_name: str
    cost: int
    tough_value: int
    reason: str


# =============================================================================
# HERO-AUSWAHL
# =============================================================================

def select_hero_unit(dl: DesignLanguage) -> HeroSelection | None:
    """
    Bestimmt die Hero-Mini einer Fraktion fuer Style-Reference.

    Auswahl-Reihenfolge (bessere Style-Anker zuerst):
        1. Top-Level YAML-Field `aesthetic.hero_unit_key` -> dieser
        2. Beste Hero-Infanterie: size=1, base<=50mm, hoechste cost
           (typischerweise Faction-Lord; zeigt charakteristischen Look)
        3. Beste Hero-Charakter (size=1, base<=60mm) ohne Base-Limit
        4. Beste Unit nach cost (kann Tank/Titan sein)
        5. Erste Unit als Fallback

    Vehicle-Heuristik: base > 60mm wird nicht bevorzugt, da Tanks/Titans
    schlechte Style-Anker fuer Infanterie sind.

    Args:
        dl: Geladene Design Language.

    Returns:
        HeroSelection oder None wenn keine unit_overrides vorhanden.
    """
    if not dl.unit_overrides:
        return None

    # 1. Explizite Auswahl ueber YAML
    explicit_key: str = _get_explicit_hero_key(dl)
    if explicit_key and explicit_key in dl.unit_overrides:
        override = dl.unit_overrides[explicit_key]
        stats = override.get("game_stats", {}) if isinstance(override, dict) else {}
        return HeroSelection(
            unit_key=explicit_key,
            unit_name=_key_to_display(explicit_key),
            cost=int(stats.get("cost", 0)),
            tough_value=_extract_tough(stats.get("rules", [])),
            reason="explicit hero_unit_key in YAML",
        )

    # 2. Hero-Charakter (Infanterie-Skala): size=1, base<=40mm
    #    Bevorzugt typische Faction-Lord-Charaktere. Tanks (base=50) und
    #    Titans/Walkers werden hier ausgeschlossen, weil sie schlechte
    #    Style-Anker fuer normale Infanterie sind.
    infantry_hero = _best_unit(dl, max_base=40, only_size_one=True)
    if infantry_hero is not None:
        return _wrap(infantry_hero, "infantry hero (size=1, base<=40mm, max cost)")

    # 3. Grosser Charakter: base<=50mm (Monster-Heroes, grosse Lords)
    medium_hero = _best_unit(dl, max_base=50, only_size_one=True)
    if medium_hero is not None:
        return _wrap(medium_hero, "monster hero (base<=50mm, max cost)")

    # 4. Egal welcher Typ — max cost
    any_hero = _best_unit(dl, max_base=None, only_size_one=False)
    if any_hero is not None:
        return _wrap(any_hero, "global max cost (Vehicle/Titan likely)")

    # 5. Fallback: erstes Element
    first_key = next(iter(dl.unit_overrides))
    return HeroSelection(
        unit_key=first_key,
        unit_name=_key_to_display(first_key),
        cost=0,
        tough_value=0,
        reason="fallback: first unit_override",
    )


VEHICLE_INDICATOR_RULES: frozenset[str] = frozenset({
    "Slow", "Aircraft", "Transport", "Artillery"
})


def classify_unit(override: object) -> UnitClass:
    """Klassifiziert eine Unit nach visueller Klasse fuer Reference-Auswahl.

    Vorrangig wird das explizite `type:`-Feld aus dem YAML-Override genutzt.
    Erlaubte Werte: infantry, walker, vehicle, aircraft, titan.

    Fallback bei fehlendem/unbekanntem type:
        - Tough(N) >= TITAN_TOUGH_THRESHOLD     -> TITAN
        - "Aircraft" in rules                   -> AIRCRAFT
        - "Slow"/"Transport"/"Artillery" rule   -> VEHICLE
        - sonst                                 -> INFANTRY

    Args:
        override: Roher unit_override-Wert (typischerweise dict aus YAML).

    Returns:
        UnitClass.
    """
    if not isinstance(override, dict):
        return UnitClass.INFANTRY

    raw_type = str(override.get("type", "")).strip().lower()
    if raw_type:
        try:
            return UnitClass(raw_type)
        except ValueError:
            logger.warning("Unbekannter type-Wert '%s' — fallback auf Rule-Heuristik", raw_type)

    stats = override.get("game_stats", {})
    if not isinstance(stats, dict):
        return UnitClass.INFANTRY

    rules = stats.get("rules", [])
    if not isinstance(rules, list):
        rules = []

    tough = _extract_tough([str(r) for r in rules])
    if tough >= TITAN_TOUGH_THRESHOLD:
        return UnitClass.TITAN

    has_aircraft: bool = False
    has_vehicle_rule: bool = False
    for rule in rules:
        match = re.match(r"^(\w+)", str(rule))
        if not match:
            continue
        token = match.group(1)
        if token == "Aircraft":
            has_aircraft = True
        elif token in VEHICLE_INDICATOR_RULES:
            has_vehicle_rule = True

    if has_aircraft:
        return UnitClass.AIRCRAFT
    if has_vehicle_rule:
        return UnitClass.VEHICLE
    return UnitClass.INFANTRY


def is_vehicle_unit(override: object) -> bool:
    """Behalten als Convenience-Wrapper.

    True wenn die Unit nicht zur Infanterie zaehlt (Walker, Vehicle, Aircraft,
    Titan). Wird im batch-Loop nicht mehr direkt fuer Reference-Dispatch
    genutzt — dort verwenden wir classify_unit() direkt.
    """
    return classify_unit(override) != UnitClass.INFANTRY


def _best_unit(
    dl: DesignLanguage,
    max_base: int | None,
    only_size_one: bool,
    exclude_vehicles: bool = True,
) -> tuple[str, dict] | None:
    """
    Findet die teuerste Unit, die die Filter erfuellt.

    Args:
        dl: Design Language.
        max_base: Max. Base-Groesse in mm (None = kein Filter). Oval-Bases
            werden auf max(width,depth) reduziert.
        only_size_one: Nur Heroes (size=1) zulassen.
        exclude_vehicles: Wenn True, schliesse Vehicles aus (per `type: vehicle`
            Override-Field oder Vehicle-typischen Regeln Slow/Aircraft/
            Transport/Artillery). Verhindert dass Tanks/Walkers/Speeders als
            Style-Anker fuer Infanterie gewaehlt werden.

    Returns:
        (unit_key, game_stats) oder None.
    """
    best: tuple[str, dict, int] | None = None
    for key, override in dl.unit_overrides.items():
        if not isinstance(override, dict):
            continue
        stats = override.get("game_stats", {})
        if not isinstance(stats, dict):
            continue
        size = int(stats.get("size", 1))
        if only_size_one and size != 1:
            continue

        base_mm = _extract_base_mm(stats.get("base", 32))
        if max_base is not None and base_mm > max_base:
            continue

        if exclude_vehicles and classify_unit(override) != UnitClass.INFANTRY:
            continue

        cost = int(stats.get("cost", 0))
        if best is None or cost > best[2]:
            best = (key, stats, cost)
    if best is None:
        return None
    return best[0], best[1]


def select_class_anchor(
    dl: DesignLanguage,
    target_class: UnitClass,
) -> HeroSelection | None:
    """Bestimmt das Anchor-Bild fuer eine Unit-Klasse innerhalb einer Fraktion.

    Liefert die repraesentativste Unit der gewuenschten Klasse, die als
    Style-/Body-Shape-Reference fuer alle weiteren Units derselben Klasse
    dient. Faction-Hero (INFANTRY) wird hier nicht erzeugt — der laeuft ueber
    select_hero_unit().

    Auswahl-Reihenfolge:
        1. Explizit ueber `aesthetic.{class}_anchor_key` in YAML
           (z.B. `walker_anchor_key`, `vehicle_anchor_key`, ...)
        2. Median-cost Unit der Klasse — vermeidet sowohl das kleinste
           als auch das groesste Exemplar
        3. None falls die Fraktion keine Unit dieser Klasse besitzt

    Args:
        dl: Geladene Design Language.
        target_class: Gesuchte Klasse (WALKER/VEHICLE/AIRCRAFT/TITAN).
            INFANTRY wird nicht unterstuetzt — dafuer select_hero_unit nutzen.

    Returns:
        HeroSelection oder None wenn keine passende Unit existiert.
    """
    if target_class == UnitClass.INFANTRY:
        raise ValueError("Fuer INFANTRY bitte select_hero_unit() nutzen")
    if not dl.unit_overrides:
        return None

    explicit_key: str = _get_explicit_anchor_key(dl, target_class)
    if explicit_key and explicit_key in dl.unit_overrides:
        override = dl.unit_overrides[explicit_key]
        stats = override.get("game_stats", {}) if isinstance(override, dict) else {}
        return HeroSelection(
            unit_key=explicit_key,
            unit_name=_key_to_display(explicit_key),
            cost=int(stats.get("cost", 0)),
            tough_value=_extract_tough(stats.get("rules", [])),
            reason=f"explicit {target_class.value}_anchor_key in YAML",
        )

    candidates: list[tuple[str, dict, int]] = []
    for key, override in dl.unit_overrides.items():
        if classify_unit(override) != target_class:
            continue
        stats = override.get("game_stats", {}) if isinstance(override, dict) else {}
        if not isinstance(stats, dict):
            stats = {}
        cost = int(stats.get("cost", 0))
        candidates.append((key, stats, cost))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[2])
    median_idx: int = len(candidates) // 2
    key, stats, _cost = candidates[median_idx]
    return HeroSelection(
        unit_key=key,
        unit_name=_key_to_display(key),
        cost=int(stats.get("cost", 0)),
        tough_value=_extract_tough(stats.get("rules", [])),
        reason=f"median-cost {target_class.value} ({len(candidates)} total)",
    )


def _get_explicit_anchor_key(dl: DesignLanguage, target_class: UnitClass) -> str:
    """Liest `{class}_anchor_key` aus aesthetic-Block der Design Language."""
    aesthetic = dl.aesthetic
    if not isinstance(aesthetic, dict):
        return ""
    raw = aesthetic.get(f"{target_class.value}_anchor_key", "")
    return str(raw) if raw else ""


def _wrap(found: tuple[str, dict], reason: str) -> HeroSelection:
    """Wickelt _best_unit-Resultat in HeroSelection."""
    key, stats = found
    return HeroSelection(
        unit_key=key,
        unit_name=_key_to_display(key),
        cost=int(stats.get("cost", 0)),
        tough_value=_extract_tough(stats.get("rules", [])),
        reason=reason,
    )


def _extract_base_mm(base: object) -> int:
    """
    Extrahiert effektive Basengroesse in mm.

    Akzeptiert int (rund) oder str "WxD" (oval). Bei oval wird max(W,D)
    zurueckgegeben. Default 32mm.
    """
    if isinstance(base, int):
        return base
    if isinstance(base, str):
        if "x" in base.lower():
            parts = base.lower().split("x")
            try:
                return max(int(parts[0]), int(parts[1]))
            except (ValueError, IndexError):
                return 32
        try:
            return int(base)
        except ValueError:
            return 32
    return 32


def _get_explicit_hero_key(dl: DesignLanguage) -> str:
    """
    Liest `hero_unit_key` aus der Design Language (top-level).

    DesignLanguage hat aktuell kein dedicated Feld dafuer; wir nutzen
    aesthetic.hero_unit_key als nicht-invasiven Hook (falls in YAML gesetzt).
    """
    aesthetic = dl.aesthetic
    if not isinstance(aesthetic, dict):
        return ""
    raw = aesthetic.get("hero_unit_key", "")
    return str(raw) if raw else ""


def _extract_tough(rules: list[str] | None) -> int:
    """Extrahiert Tough(N) aus einer Regelliste; 0 wenn nicht vorhanden."""
    if not rules:
        return 0
    max_tough: int = 0
    for rule in rules:
        match = TOUGH_PATTERN.match(str(rule))
        if match:
            value = int(match.group(1))
            if value > max_tough:
                max_tough = value
    return max_tough


def _key_to_display(key: str) -> str:
    """Konvertiert snake_case-Key zu Display-Namen (Hive Lord)."""
    return key.replace("_", " ").title()


# =============================================================================
# REFERENCE-IMAGE-PERSISTENZ
# =============================================================================

def reference_image_path(project_root: Path, faction_folder: str) -> Path:
    """
    Gibt den kanonischen Pfad zum Reference-Image einer Fraktion zurueck.

    Args:
        project_root: Wurzelverzeichnis des Godot-Projekts.
        faction_folder: Fraktionsname (z.B. "alien_hives").

    Returns:
        Pfad zu assets/miniatures/{faction}/_reference.webp
    """
    return (
        project_root
        / MINIATURES_DIR
        / faction_folder
        / REFERENCE_IMAGE_FILENAME
    )


def has_reference_image(project_root: Path, faction_folder: str) -> bool:
    """True wenn fuer die Fraktion bereits ein Reference-Image existiert."""
    return reference_image_path(project_root, faction_folder).exists()


def store_reference_image(
    source_image: Path,
    project_root: Path,
    faction_folder: str,
) -> Path:
    """
    Persistiert ein generiertes (und genehmigtes) Hero-Bild als Reference.

    Konvertiert nach WebP fuer Kompaktheit und Konsistenz mit den anderen
    Vorschau-Images im Projekt.

    Args:
        source_image: Pfad zum genehmigten Hero-Image (PNG/JPG/WebP).
        project_root: Wurzelverzeichnis des Godot-Projekts.
        faction_folder: Fraktionsname.

    Returns:
        Pfad des gespeicherten Reference-Image.
    """
    target: Path = reference_image_path(project_root, faction_folder)
    target.parent.mkdir(parents=True, exist_ok=True)

    if source_image.suffix.lower() == ".webp":
        target.write_bytes(source_image.read_bytes())
        return target

    # Andere Formate: ueber Pillow nach WebP konvertieren
    from PIL import Image

    with Image.open(source_image) as img:
        img.save(target, format="WEBP", quality=92, method=6)
    return target


def clear_reference_image(project_root: Path, faction_folder: str) -> bool:
    """Entfernt das gespeicherte Reference-Image. Returns True wenn entfernt."""
    target: Path = reference_image_path(project_root, faction_folder)
    if target.exists():
        target.unlink()
        return True
    return False


def class_reference_image_path(
    project_root: Path,
    faction_folder: str,
    target_class: UnitClass,
) -> Path:
    """Pfad zur Reference einer Unit-Klasse innerhalb einer Fraktion.

    INFANTRY = Hero-Reference (kompatibel zu reference_image_path).
    """
    filename: str = REFERENCE_FILENAMES[target_class]
    return project_root / MINIATURES_DIR / faction_folder / filename


def has_class_reference_image(
    project_root: Path,
    faction_folder: str,
    target_class: UnitClass,
) -> bool:
    """True wenn fuer die Fraktion bereits eine Klassen-Reference existiert."""
    return class_reference_image_path(project_root, faction_folder, target_class).exists()


def store_class_reference_image(
    source_image: Path,
    project_root: Path,
    faction_folder: str,
    target_class: UnitClass,
) -> Path:
    """Persistiert ein genehmigtes Bild als Klassen-Reference."""
    target: Path = class_reference_image_path(project_root, faction_folder, target_class)
    target.parent.mkdir(parents=True, exist_ok=True)

    if source_image.suffix.lower() == ".webp":
        target.write_bytes(source_image.read_bytes())
        return target

    from PIL import Image

    with Image.open(source_image) as img:
        img.save(target, format="WEBP", quality=92, method=6)
    return target


def clear_class_reference_image(
    project_root: Path,
    faction_folder: str,
    target_class: UnitClass,
) -> bool:
    """Entfernt die Klassen-Reference. Returns True wenn entfernt."""
    target: Path = class_reference_image_path(project_root, faction_folder, target_class)
    if target.exists():
        target.unlink()
        return True
    return False
