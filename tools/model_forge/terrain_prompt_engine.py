"""
TerrainPromptEngine — Generiert Bild-Prompts fuer modulares Terrain.

Laedt Terrain-Themes aus YAML-Dateien im neuen modularen Format:
- Battle Map (Tisch-Hintergrundbild)
- Base Plates (tileable Texturen fuer Terrain-Zellen)
- Walls (3D-Wandsegmente fuer Zellenkanten)
- Trees (3D-Baeume fuer FOREST-Zellen)
- Containers (3D-Objekte direkt auf Battle Map)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


# =============================================================================
# DATA CLASSES
# =============================================================================

@dataclass
class WallVariant:
    """Eine Wand-Variante fuer Zellenkanten."""

    key: str
    name: str
    length_inches: float  # 3.0 oder 1.0
    height_inches: float
    prompt: str
    texture_prompt: str = ""  # Flat texture prompt (bevorzugt ueber prompt fuer BoxMesh walls)
    variants: int = 1  # Anzahl Textur-Varianten (>1 erzeugt {key}_v0, {key}_v1, ...)


@dataclass
class TreeVariant:
    """Eine Baum-Variante fuer FOREST-Zellen."""

    key: str
    name: str
    prompt: str


@dataclass
class ContainerVariant:
    """Eine Container-Variante fuer freie Platzierung."""

    key: str
    name: str
    prompt: str


@dataclass
class TerrainTheme:
    """Komplettes Terrain-Theme mit allen modularen Asset-Definitionen."""

    theme_name: str
    theme_key: str
    aesthetic: dict[str, Any]
    colors: dict[str, str]
    materials: list[str]
    battle_map_prompt: str
    base_plate_prompts: dict[str, str]  # terrain_type -> prompt
    walls: list[WallVariant] = field(default_factory=list)
    trees: list[TreeVariant] = field(default_factory=list)
    containers: list[ContainerVariant] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> TerrainTheme:
        """Erzeugt TerrainTheme aus Dictionary (YAML-Daten)."""
        # Pflichtfelder
        battle_map_data: dict[str, str] = data["battle_map"]
        base_plates_data: dict[str, dict[str, str]] = data["base_plates"]

        base_plate_prompts: dict[str, str] = {
            terrain_type: plate_data["prompt"]
            for terrain_type, plate_data in base_plates_data.items()
        }

        # Walls (optional)
        walls: list[WallVariant] = []
        for wall_data in data.get("walls", []):
            walls.append(WallVariant(
                key=wall_data["key"],
                name=wall_data["name"],
                length_inches=float(wall_data["length_inches"]),
                height_inches=float(wall_data["height_inches"]),
                prompt=wall_data.get("prompt", ""),
                texture_prompt=wall_data.get("texture_prompt", ""),
                variants=int(wall_data.get("variants", 1)),
            ))

        # Trees (optional)
        trees: list[TreeVariant] = []
        for tree_data in data.get("trees", []):
            trees.append(TreeVariant(
                key=tree_data["key"],
                name=tree_data["name"],
                prompt=tree_data["prompt"],
            ))

        # Containers (optional)
        containers: list[ContainerVariant] = []
        for container_data in data.get("containers", []):
            containers.append(ContainerVariant(
                key=container_data["key"],
                name=container_data["name"],
                prompt=container_data["prompt"],
            ))

        return cls(
            theme_name=data["theme_name"],
            theme_key=data["theme_key"],
            aesthetic=data["aesthetic"],
            colors=data["colors"],
            materials=data["materials"],
            battle_map_prompt=battle_map_data["prompt"],
            base_plate_prompts=base_plate_prompts,
            walls=walls,
            trees=trees,
            containers=containers,
        )


# =============================================================================
# LOADING
# =============================================================================

def load_terrain_theme(yaml_path: Path) -> TerrainTheme:
    """Laedt ein Terrain-Theme aus einer YAML-Datei.

    Args:
        yaml_path: Pfad zur YAML-Datei.

    Returns:
        Fertig geparste TerrainTheme-Instanz.

    Raises:
        FileNotFoundError: Wenn die Datei nicht existiert.
        KeyError: Wenn Pflichtfelder fehlen.
    """
    if not yaml_path.exists():
        msg = f"Terrain theme not found: {yaml_path}"
        raise FileNotFoundError(msg)

    with open(yaml_path, encoding="utf-8") as f:
        data: dict[str, Any] = yaml.safe_load(f)

    return TerrainTheme.from_dict(data)


def scan_terrain_themes(themes_dir: Path) -> list[str]:
    """Scannt ein Verzeichnis nach verfuegbaren Terrain-Themes.

    Args:
        themes_dir: Verzeichnis mit YAML-Dateien.

    Returns:
        Liste von theme_keys (sortiert).
    """
    if not themes_dir.exists():
        return []

    keys: list[str] = []
    for yaml_file in sorted(themes_dir.glob("*.yaml")):
        try:
            theme = load_terrain_theme(yaml_file)
            keys.append(theme.theme_key)
        except (KeyError, ValueError, yaml.YAMLError):
            continue

    return keys


# =============================================================================
# PROMPT ENGINE
# =============================================================================

class TerrainPromptEngine:
    """Generiert Bild-Prompts fuer alle Asset-Typen eines Terrain-Themes."""

    def __init__(self, theme: TerrainTheme) -> None:
        self._theme: TerrainTheme = theme

    def get_battle_map_prompt(self) -> str:
        """Gibt den Battle-Map-Prompt zurueck."""
        return self._theme.battle_map_prompt

    def get_base_plate_prompts(self) -> dict[str, str]:
        """Gibt alle Base-Plate-Prompts zurueck (terrain_type -> prompt)."""
        return dict(self._theme.base_plate_prompts)

    def get_wall_prompts(self) -> dict[str, str]:
        """Gibt alle Wall-Prompts zurueck (key -> prompt).

        Bevorzugt texture_prompt ueber prompt.
        Bei variants > 1 werden Keys zu {key}_v0, {key}_v1, ... expandiert.
        """
        prompts: dict[str, str] = {}
        for wall in self._theme.walls:
            effective_prompt = wall.texture_prompt if wall.texture_prompt else wall.prompt
            if wall.variants > 1:
                for i in range(wall.variants):
                    prompts[f"{wall.key}_v{i}"] = effective_prompt
            else:
                prompts[wall.key] = effective_prompt
        return prompts

    def get_tree_prompts(self) -> dict[str, str]:
        """Gibt alle Tree-Prompts zurueck (key -> prompt)."""
        return {tree.key: tree.prompt for tree in self._theme.trees}

    def get_container_prompts(self) -> dict[str, str]:
        """Gibt alle Container-Prompts zurueck (key -> prompt)."""
        return {c.key: c.prompt for c in self._theme.containers}

    def get_all_prompts(self) -> dict[str, str]:
        """Gibt alle Prompts mit prefixed Keys zurueck.

        Keys:
            battle_map, base_plate_{type}, wall_{key}, tree_{key}, container_{key}
        """
        prompts: dict[str, str] = {}

        # Battle Map
        prompts["battle_map"] = self._theme.battle_map_prompt

        # Base Plates
        for terrain_type, prompt in self._theme.base_plate_prompts.items():
            prompts[f"base_plate_{terrain_type}"] = prompt

        # Walls (texture_prompt bevorzugt, variants expandiert)
        for wall in self._theme.walls:
            effective_prompt = wall.texture_prompt if wall.texture_prompt else wall.prompt
            if wall.variants > 1:
                for i in range(wall.variants):
                    prompts[f"wall_{wall.key}_v{i}"] = effective_prompt
            else:
                prompts[f"wall_{wall.key}"] = effective_prompt

        # Trees
        for tree in self._theme.trees:
            prompts[f"tree_{tree.key}"] = tree.prompt

        # Containers
        for container in self._theme.containers:
            prompts[f"container_{container.key}"] = container.prompt

        return prompts
