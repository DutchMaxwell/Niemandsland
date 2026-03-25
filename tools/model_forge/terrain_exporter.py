"""
Terrain Exporter — Exportiert modulare Terrain-Assets fuer OpenTTS
===================================================================

Erzeugt die Verzeichnisstruktur fuer Terrain-Themes:
    assets/terrain/{theme_key}/
        terrain.json
        battle_map.png
        base_plates/
            ruins.png
            forest.png
            dangerous.png
        walls/
            {wall_key}.glb
        trees/
            {tree_key}.glb
        containers/
            {container_key}.glb

Das terrain.json wird von terrain_library.gd / terrain_overlay.gd geladen.
"""

from __future__ import annotations

import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from pipeline_state import UnitState, UnitStatus
from terrain_prompt_engine import TerrainTheme


# =============================================================================
# KONSTANTEN
# =============================================================================

TERRAIN_DIR = "assets/terrain"
TERRAIN_JSON_FILENAME = "terrain.json"
VERSION_STRING = "auto-generated"

EXPORTABLE_STATUSES: frozenset[UnitStatus] = frozenset({
    UnitStatus.GLB_READY,
    UnitStatus.EXPORTED,
    UnitStatus.IMAGE_APPROVED,
})


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class TerrainExportResult:
    """Ergebnis eines Terrain-Export-Vorgangs."""

    success: bool
    terrain_json_path: str = ""
    exported_count: int = 0
    errors: list[str] = field(default_factory=list)


# =============================================================================
# EXPORT-FUNKTION
# =============================================================================

def export_terrain(
    theme: TerrainTheme,
    unit_states: list[UnitState],
    project_root: Path,
) -> TerrainExportResult:
    """
    Exportiert modulare Terrain-Assets in das OpenTTS-Projektverzeichnis.

    Erkennt Asset-Typen anhand des unit_key Prefix:
    - battle_map -> battle_map.png (Image)
    - base_plate_{type} -> base_plates/{type}.png (Image)
    - wall_{key} -> walls/{key}.glb (GLB)
    - tree_{key} -> trees/{key}.glb (GLB)
    - container_{key} -> containers/{key}.glb (GLB)

    Args:
        theme: Das Terrain-Theme mit Asset-Definitionen.
        unit_states: Liste aller UnitState-Objekte aus der Pipeline.
        project_root: Wurzelverzeichnis des Godot-Projekts.

    Returns:
        TerrainExportResult mit Erfolg/Fehler-Informationen.
    """
    errors: list[str] = []

    # Zielverzeichnisse bestimmen
    target_dir = project_root / TERRAIN_DIR / theme.theme_key

    # Unterverzeichnisse anlegen
    subdirs = ["base_plates", "walls", "trees", "containers"]
    try:
        for subdir in subdirs:
            (target_dir / subdir).mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return TerrainExportResult(
            success=False,
            errors=[f"Verzeichnis konnte nicht erstellt werden: {exc}"],
        )

    # Exportierbare Units filtern
    exportable: list[UnitState] = [
        us for us in unit_states
        if us.status in EXPORTABLE_STATUSES
    ]

    if not exportable:
        return TerrainExportResult(
            success=False,
            exported_count=0,
            errors=["Keine exportierbaren Terrain-Assets gefunden"],
        )

    # Assets exportieren
    exported_count = 0
    battle_map_path: str = ""
    base_plates_paths: dict[str, str] = {}
    wall_entries: list[dict] = []
    tree_entries: list[dict] = []
    container_entries: list[dict] = []

    # Index fuer Theme-Lookup
    wall_lookup = {w.key: w for w in theme.walls}
    tree_lookup = {t.key: t for t in theme.trees}
    container_lookup = {c.key: c for c in theme.containers}

    for unit_state in exportable:
        key = unit_state.unit_key

        if key == "battle_map":
            result = _copy_image(unit_state, target_dir / "battle_map.png", errors)
            if result:
                battle_map_path = "battle_map.png"
                exported_count += 1

        elif key.startswith("base_plate_"):
            terrain_type = key[len("base_plate_"):]
            dest = target_dir / "base_plates" / f"{terrain_type}.png"
            result = _copy_image(unit_state, dest, errors)
            if result:
                base_plates_paths[terrain_type] = f"base_plates/{terrain_type}.png"
                exported_count += 1

        elif key.startswith("wall_"):
            wall_key = key[len("wall_"):]
            # Determine base wall key (strip _vN variant suffix for lookup)
            base_wall_key = wall_key
            for wk in wall_lookup:
                if wall_key.startswith(wk):
                    base_wall_key = wk
                    break
            wall_def = wall_lookup.get(base_wall_key)

            # Texture-based wall: export as PNG if wall has texture_prompt
            if wall_def and wall_def.texture_prompt:
                dest = target_dir / "walls" / f"{wall_key}.png"
                result = _copy_image(unit_state, dest, errors)
                if result:
                    wall_entries.append({
                        "key": wall_key,
                        "name": wall_def.name,
                        "length_inches": wall_def.length_inches,
                        "height_inches": wall_def.height_inches,
                        "texture": f"walls/{wall_key}.png",
                    })
                    exported_count += 1
            else:
                # GLB-based wall (legacy/fallback)
                dest = target_dir / "walls" / f"{wall_key}.glb"
                result = _copy_glb(unit_state, dest, errors)
                if result:
                    wall_entries.append({
                        "key": wall_key,
                        "name": wall_def.name if wall_def else unit_state.unit_name,
                        "length_inches": wall_def.length_inches if wall_def else 3.0,
                        "height_inches": wall_def.height_inches if wall_def else 3.0,
                        "glb": f"walls/{wall_key}.glb",
                    })
                    exported_count += 1

        elif key.startswith("tree_"):
            tree_key = key[len("tree_"):]
            dest = target_dir / "trees" / f"{tree_key}.glb"
            result = _copy_glb(unit_state, dest, errors)
            if result:
                tree_def = tree_lookup.get(tree_key)
                tree_entries.append({
                    "key": tree_key,
                    "name": tree_def.name if tree_def else unit_state.unit_name,
                    "glb": f"trees/{tree_key}.glb",
                })
                exported_count += 1

        elif key.startswith("container_"):
            container_key = key[len("container_"):]
            dest = target_dir / "containers" / f"{container_key}.glb"
            result = _copy_glb(unit_state, dest, errors)
            if result:
                container_def = container_lookup.get(container_key)
                container_entries.append({
                    "key": container_key,
                    "name": container_def.name if container_def else unit_state.unit_name,
                    "glb": f"containers/{container_key}.glb",
                })
                exported_count += 1

    # terrain.json erzeugen
    terrain_json_data = {
        "theme": theme.theme_name,
        "theme_key": theme.theme_key,
        "version": VERSION_STRING,
        "battle_map": battle_map_path,
        "base_plates": base_plates_paths,
        "walls": wall_entries,
        "trees": tree_entries,
        "containers": container_entries,
    }

    terrain_json_path = target_dir / TERRAIN_JSON_FILENAME
    try:
        terrain_json_path.write_text(
            json.dumps(terrain_json_data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError as exc:
        errors.append(f"terrain.json konnte nicht geschrieben werden: {exc}")
        return TerrainExportResult(
            success=False,
            exported_count=exported_count,
            errors=errors,
        )

    success = exported_count > 0 and not errors
    return TerrainExportResult(
        success=success,
        terrain_json_path=str(terrain_json_path),
        exported_count=exported_count,
        errors=errors,
    )


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _copy_image(unit_state: UnitState, dest: Path, errors: list[str]) -> bool:
    """Kopiert ein Bild-Asset an den Zielpfad."""
    source = Path(unit_state.image_path) if unit_state.image_path else None
    if source is None or not source.exists():
        errors.append(
            f"Bild-Datei nicht gefunden: {unit_state.image_path} "
            f"(Asset: {unit_state.unit_name})"
        )
        return False

    try:
        shutil.copy2(source, dest)
        return True
    except OSError as exc:
        errors.append(
            f"Bild-Kopie fehlgeschlagen fuer '{unit_state.unit_name}': {exc}"
        )
        return False


def _copy_glb(unit_state: UnitState, dest: Path, errors: list[str]) -> bool:
    """Kopiert eine GLB-Datei an den Zielpfad."""
    source = Path(unit_state.glb_path) if unit_state.glb_path else None
    if source is None or not source.exists():
        errors.append(
            f"GLB-Datei nicht gefunden: {unit_state.glb_path} "
            f"(Asset: {unit_state.unit_name})"
        )
        return False

    try:
        shutil.copy2(source, dest)
        return True
    except OSError as exc:
        errors.append(
            f"GLB-Kopie fehlgeschlagen fuer '{unit_state.unit_name}': {exc}"
        )
        return False
