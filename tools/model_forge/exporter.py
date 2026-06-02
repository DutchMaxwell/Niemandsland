"""
Model Forge Exporter - Exportiert GLB-Dateien und units.json fuer Niemandsland
=========================================================================

Erzeugt die Verzeichnisstruktur und Dateien, die der opr_army_manager.gd
erwartet:
    assets/miniatures/{faction_folder}/
        units.json
        glb/
            01_UnitName.glb
            02_UnitName.glb
            ...

Benennungskonvention GLB-Dateien:
    {NN}_{UnitName}.glb  wobei NN = 01, 02, 03 ...
    Der opr_army_manager.gd sucht case-insensitive nach Uebereinstimmung.
"""

from __future__ import annotations

import json
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from glb_optimizer import (
    DEFAULT_SIMPLIFY_RATIO,
    DEFAULT_TEXTURE_MAX_DIM,
    DEFAULT_WEBP_QUALITY,
    optimize_glb,
)
from opr_client import OPRArmy, OPRUnit, OPRWeapon
from pipeline_state import UnitState, UnitStatus


# =============================================================================
# KONSTANTEN
# =============================================================================

MINIATURES_DIR = "assets/miniatures"
GLB_SUBDIR = "glb"
UNITS_JSON_FILENAME = "units.json"
VERSION_STRING = "auto-generated"

# GLB-Optimierung (vor dem Export): Mesh-Decimation + Texture-Resize
OPTIMIZE_GLBS_ON_EXPORT: bool = True
OPTIMIZE_SIMPLIFY_RATIO: float = DEFAULT_SIMPLIFY_RATIO
OPTIMIZE_TEXTURE_MAX_DIM: int = DEFAULT_TEXTURE_MAX_DIM
OPTIMIZE_WEBP_QUALITY: int = DEFAULT_WEBP_QUALITY

EXPORTABLE_STATUSES: frozenset[UnitStatus] = frozenset({
    UnitStatus.GLB_APPROVED,
    UnitStatus.EXPORTED,
})


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class ExportResult:
    """Ergebnis eines Export-Vorgangs."""

    success: bool
    units_json_path: str = ""
    glb_dir: str = ""
    exported_count: int = 0
    errors: list[str] = field(default_factory=list)


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _unit_name_to_key(name: str) -> str:
    """
    Konvertiert einen Unit-Namen in einen Dictionary-Key fuer units.json.

    Regeln:
        - Kleinbuchstaben
        - Leerzeichen -> Unterstrich
        - Bindestriche -> Unterstrich
        - Sonderzeichen entfernen (ausser Unterstrich)
        - Mehrfache Unterstriche zusammenfassen

    Beispiele:
        'Hive Lord'      -> 'hive_lord'
        'Carnivo-Rex'    -> 'carnivo_rex'
        'Psycho-Grunts'  -> 'psycho_grunts'
        'Soul-Snatchers' -> 'soul_snatchers'
    """
    key = name.lower()
    key = key.replace(" ", "_")
    key = key.replace("-", "_")
    key = re.sub(r"[^a-z0-9_]", "", key)
    key = re.sub(r"_+", "_", key)
    key = key.strip("_")
    return key


def _format_equipment_list(weapons: list[OPRWeapon]) -> list[str]:
    """
    Konvertiert OPRWeapon-Objekte in das Equipment-String-Format von units.json.

    Format: '{count}x {name} ({range}, A{attacks}, {rules})'

    Beispiele:
        '1x Shredder Cannon (18", A4, Rending)'
        '2x Heavy Razor Claws (A3, AP(1))'
        '10x Razor Claws (A2)'
    """
    result: list[str] = []

    for weapon in weapons:
        count_str = f"{weapon.count}x"
        parts: list[str] = []

        if weapon.range_value > 0:
            parts.append(f'{weapon.range_value}"')

        parts.append(f"A{weapon.attacks}")

        for rule in weapon.special_rules:
            parts.append(rule)

        inner = ", ".join(parts)
        entry = f"{count_str} {weapon.name} ({inner})"
        result.append(entry)

    return result


def _build_units_dict(army: OPRArmy) -> dict:
    """
    Erstellt das units-Dictionary im units.json-Format.

    Dedupliziert nach Unit-Name (case-insensitive). Nur die erste
    Einheit mit einem bestimmten Namen wird aufgenommen, da die
    GLB-Dateien pro Unit-Typ (nicht pro Instanz) vorliegen.
    """
    units_dict: dict = {}
    seen_names: set[str] = set()

    for unit in army.units:
        lower_name = unit.name.lower()
        if lower_name in seen_names:
            continue
        seen_names.add(lower_name)

        unit_key = _unit_name_to_key(unit.name)
        units_dict[unit_key] = {
            "name": unit.name,
            "size": unit.size,
            "points": unit.cost,
            "qua": f"{unit.quality}+",
            "def": f"{unit.defense}+",
            "equipment": _format_equipment_list(unit.weapons),
            "special_rules": list(unit.special_rules),
            "base_size_mm": unit.base_size_round,
        }

    return units_dict


def _calculate_total_models(army: OPRArmy) -> int:
    """Berechnet die Gesamtzahl aller Modelle (bei voller Einheitenstaerke)."""
    return sum(unit.size for unit in army.units)


# =============================================================================
# EXPORT-FUNKTION
# =============================================================================

def export_army(
    army: OPRArmy,
    unit_states: list[UnitState],
    project_root: Path,
) -> ExportResult:
    """
    Exportiert GLB-Dateien und units.json in das Niemandsland-Projektverzeichnis.

    Nur Einheiten mit Status GLB_APPROVED oder EXPORTED werden exportiert.
    Die Zielstruktur entspricht dem, was opr_army_manager.gd erwartet.

    Args:
        army: Die zu exportierende Armee
        unit_states: Liste aller UnitState-Objekte aus der Pipeline
        project_root: Wurzelverzeichnis des Godot-Projekts

    Returns:
        ExportResult mit Erfolg/Fehler-Informationen
    """
    errors: list[str] = []

    if not army.faction_folder:
        return ExportResult(
            success=False,
            errors=["Kein faction_folder in der Armee gesetzt"],
        )

    # Zielverzeichnisse bestimmen
    target_dir = project_root / MINIATURES_DIR / army.faction_folder
    glb_dir = target_dir / GLB_SUBDIR

    # Verzeichnisse anlegen
    try:
        glb_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return ExportResult(
            success=False,
            errors=[f"Verzeichnis konnte nicht erstellt werden: {exc}"],
        )

    # Exportierbare Units filtern
    exportable: list[UnitState] = [
        us for us in unit_states
        if us.status in EXPORTABLE_STATUSES
    ]

    if not exportable:
        return ExportResult(
            success=False,
            units_json_path="",
            glb_dir=str(glb_dir),
            exported_count=0,
            errors=["Keine genehmigten Einheiten (GLB_APPROVED) gefunden — erst im 3D-Review genehmigen"],
        )

    # GLB-Dateien kopieren mit nummerierter Benennung
    exported_count = 0
    for index, unit_state in enumerate(exportable, start=1):
        source_path = Path(unit_state.glb_path)
        if not source_path.exists():
            errors.append(
                f"GLB-Datei nicht gefunden: {unit_state.glb_path} "
                f"(Einheit: {unit_state.unit_name})"
            )
            continue

        prefix = f"{index:02d}"
        target_filename = f"{prefix}_{unit_state.unit_name}.glb"
        target_path = glb_dir / target_filename

        if OPTIMIZE_GLBS_ON_EXPORT:
            opt = optimize_glb(
                source_path,
                target_path,
                simplify_ratio=OPTIMIZE_SIMPLIFY_RATIO,
                texture_max_dim=OPTIMIZE_TEXTURE_MAX_DIM,
                webp_quality=OPTIMIZE_WEBP_QUALITY,
            )
            if opt.success:
                exported_count += 1
                print(
                    f"  Optimized '{unit_state.unit_name}': "
                    f"{opt.input_bytes/1024/1024:.2f} MB -> "
                    f"{opt.output_bytes/1024/1024:.2f} MB "
                    f"(-{opt.reduction_percent:.0f}%)"
                )
            else:
                errors.append(
                    f"GLB-Optimierung fehlgeschlagen fuer '{unit_state.unit_name}': {opt.error}"
                )
                # Fallback: Original kopieren, damit der Export nicht komplett scheitert
                try:
                    shutil.copy2(source_path, target_path)
                    exported_count += 1
                except OSError as exc:
                    errors.append(
                        f"Fallback-Kopie ebenfalls fehlgeschlagen fuer '{unit_state.unit_name}': {exc}"
                    )
        else:
            try:
                shutil.copy2(source_path, target_path)
                exported_count += 1
            except OSError as exc:
                errors.append(
                    f"GLB-Kopie fehlgeschlagen fuer '{unit_state.unit_name}': {exc}"
                )

    # units.json erzeugen
    units_dict = _build_units_dict(army)

    # Game-System-Prefix fuer den Army-Namen (GF, AoF, etc.)
    game_prefix = _get_game_prefix(army.game_system)
    army_display_name = f"{game_prefix} - {army.faction_name}" if army.faction_name else army.name

    units_json_data = {
        "army": army_display_name,
        "version": VERSION_STRING,
        "units": units_dict,
        "total_units": len(units_dict),
        "total_models_if_full": _calculate_total_models(army),
    }

    units_json_path = target_dir / UNITS_JSON_FILENAME
    try:
        units_json_path.write_text(
            json.dumps(units_json_data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError as exc:
        errors.append(f"units.json konnte nicht geschrieben werden: {exc}")
        return ExportResult(
            success=False,
            units_json_path="",
            glb_dir=str(glb_dir),
            exported_count=exported_count,
            errors=errors,
        )

    success = exported_count > 0 and not errors
    return ExportResult(
        success=success,
        units_json_path=str(units_json_path),
        glb_dir=str(glb_dir),
        exported_count=exported_count,
        errors=errors,
    )


# =============================================================================
# INTERNE HILFSFUNKTIONEN
# =============================================================================

def _get_game_prefix(game_system: str) -> str:
    """
    Ermittelt das Kuerzel fuer das Spielsystem.

    Beispiele:
        'Grimdark Future'              -> 'GF'
        'Grimdark Future: Firefight'   -> 'GFF'
        'Age of Fantasy'               -> 'AoF'
        'Age of Fantasy: Skirmish'     -> 'AoFS'
        'Age of Fantasy: Regiments'    -> 'AoFR'
    """
    prefix_map: dict[str, str] = {
        "Grimdark Future": "GF",
        "Grimdark Future: Firefight": "GFF",
        "Age of Fantasy": "AoF",
        "Age of Fantasy: Skirmish": "AoFS",
        "Age of Fantasy: Regiments": "AoFR",
    }
    return prefix_map.get(game_system, game_system)
