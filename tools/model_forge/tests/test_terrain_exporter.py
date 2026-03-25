"""Tests fuer Terrain Exporter (modulares Format)."""

import json

import pytest
from pathlib import Path

from pipeline_state import UnitState, UnitStatus
from terrain_prompt_engine import TerrainTheme, load_terrain_theme
from terrain_exporter import export_terrain, TerrainExportResult


# =============================================================================
# FIXTURES
# =============================================================================

TERRAIN_THEMES_DIR = Path(__file__).parent.parent / "terrain_themes"


@pytest.fixture
def grimdark_theme() -> TerrainTheme:
    """Laedt das grimdark_industrial Theme."""
    return load_terrain_theme(TERRAIN_THEMES_DIR / "grimdark_industrial.yaml")


@pytest.fixture
def full_unit_states(tmp_path: Path, grimdark_theme: TerrainTheme) -> list[UnitState]:
    """UnitStates fuer alle Asset-Typen mit GLB_READY/IMAGE_GENERATED Status."""
    states: list[UnitState] = []

    # Battle Map (Image)
    img_path = tmp_path / "battle_map.png"
    img_path.write_bytes(b"fake-png-data")
    states.append(UnitState(
        unit_key="battle_map",
        unit_name="Battle Map",
        status=UnitStatus.IMAGE_APPROVED,
        image_path=str(img_path),
    ))

    # Base Plates (Images)
    for terrain_type in ("ruins", "forest", "dangerous"):
        img_path = tmp_path / f"base_plate_{terrain_type}.png"
        img_path.write_bytes(b"fake-png-data")
        states.append(UnitState(
            unit_key=f"base_plate_{terrain_type}",
            unit_name=f"Base Plate {terrain_type.title()}",
            status=UnitStatus.IMAGE_APPROVED,
            image_path=str(img_path),
        ))

    # Walls (PNG if texture_prompt exists, GLB otherwise)
    for wall in grimdark_theme.walls:
        if wall.texture_prompt:
            # Texture-based walls: expand variants
            variant_count = wall.variants if wall.variants > 1 else 1
            for vi in range(variant_count):
                vkey = f"{wall.key}_v{vi}" if variant_count > 1 else wall.key
                img_path = tmp_path / f"wall_{vkey}.png"
                img_path.write_bytes(b"fake-png-data")
                states.append(UnitState(
                    unit_key=f"wall_{vkey}",
                    unit_name=wall.name,
                    status=UnitStatus.IMAGE_APPROVED,
                    image_path=str(img_path),
                ))
        else:
            glb_path = tmp_path / f"wall_{wall.key}.glb"
            glb_path.write_bytes(b"fake-glb-data")
            states.append(UnitState(
                unit_key=f"wall_{wall.key}",
                unit_name=wall.name,
                status=UnitStatus.GLB_READY,
                glb_path=str(glb_path),
            ))

    # Trees (GLBs)
    for tree in grimdark_theme.trees:
        glb_path = tmp_path / f"tree_{tree.key}.glb"
        glb_path.write_bytes(b"fake-glb-data")
        states.append(UnitState(
            unit_key=f"tree_{tree.key}",
            unit_name=tree.name,
            status=UnitStatus.GLB_READY,
            glb_path=str(glb_path),
        ))

    # Containers (GLBs)
    for container in grimdark_theme.containers:
        glb_path = tmp_path / f"container_{container.key}.glb"
        glb_path.write_bytes(b"fake-glb-data")
        states.append(UnitState(
            unit_key=f"container_{container.key}",
            unit_name=container.name,
            status=UnitStatus.GLB_READY,
            glb_path=str(glb_path),
        ))

    return states


@pytest.fixture
def glb_only_states(tmp_path: Path) -> list[UnitState]:
    """Nur GLB-States (Waende) fuer einfache Tests."""
    states: list[UnitState] = []
    for key, name in [
        ("wall_test_wall_3inch", "Test Wall 3 inch"),
        ("tree_test_tree", "Test Tree"),
        ("container_test_box", "Test Box"),
    ]:
        glb_path = tmp_path / f"{key}.glb"
        glb_path.write_bytes(b"fake-glb-data")
        states.append(UnitState(
            unit_key=key,
            unit_name=name,
            status=UnitStatus.GLB_READY,
            glb_path=str(glb_path),
        ))
    return states


# =============================================================================
# TESTS: Verzeichnisstruktur
# =============================================================================

class TestExportTerrainDirectoryStructure:
    """Prueft ob die korrekte Verzeichnisstruktur erstellt wird."""

    def test_creates_theme_directory(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        theme_dir = project_root / "assets" / "terrain" / "grimdark_industrial"
        assert theme_dir.exists()

    def test_creates_subdirectories(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        base = project_root / "assets" / "terrain" / "grimdark_industrial"
        assert (base / "base_plates").exists()
        assert (base / "walls").exists()
        assert (base / "trees").exists()
        assert (base / "containers").exists()


# =============================================================================
# TESTS: Datei-Kopie
# =============================================================================

class TestExportTerrainFileCopy:
    """Prueft ob Dateien korrekt kopiert werden."""

    def test_copies_battle_map(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        battle_map = project_root / "assets" / "terrain" / "grimdark_industrial" / "battle_map.png"
        assert battle_map.exists()

    def test_copies_base_plates(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        base = project_root / "assets" / "terrain" / "grimdark_industrial" / "base_plates"
        assert (base / "ruins.png").exists()
        assert (base / "forest.png").exists()
        assert (base / "dangerous.png").exists()

    def test_copies_wall_assets(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        walls_dir = project_root / "assets" / "terrain" / "grimdark_industrial" / "walls"
        # Walls with texture_prompt are exported as PNG (with variants), GLB otherwise
        png_files = sorted(walls_dir.glob("*.png"))
        glb_files = sorted(walls_dir.glob("*.glb"))
        expected_pngs = sum(
            w.variants if w.texture_prompt and w.variants > 1 else (1 if w.texture_prompt else 0)
            for w in grimdark_theme.walls
        )
        expected_glbs = sum(1 for w in grimdark_theme.walls if not w.texture_prompt)
        assert len(png_files) == expected_pngs
        assert len(glb_files) == expected_glbs

    def test_copies_tree_glbs(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        trees_dir = project_root / "assets" / "terrain" / "grimdark_industrial" / "trees"
        glb_files = sorted(trees_dir.glob("*.glb"))
        assert len(glb_files) == len(grimdark_theme.trees)

    def test_copies_container_glbs(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        containers_dir = project_root / "assets" / "terrain" / "grimdark_industrial" / "containers"
        glb_files = sorted(containers_dir.glob("*.glb"))
        assert len(glb_files) == len(grimdark_theme.containers)

    def test_wall_naming_by_key(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        walls_dir = project_root / "assets" / "terrain" / "grimdark_industrial" / "walls"
        first_wall = grimdark_theme.walls[0]
        if first_wall.texture_prompt and first_wall.variants > 1:
            assert (walls_dir / f"{first_wall.key}_v0.png").exists()
        elif first_wall.texture_prompt:
            assert (walls_dir / f"{first_wall.key}.png").exists()
        else:
            assert (walls_dir / f"{first_wall.key}.glb").exists()

    def test_skips_non_ready_units(
        self, grimdark_theme: TerrainTheme, tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        states = [UnitState(
            unit_key="wall_test",
            unit_name="Test",
            status=UnitStatus.PENDING,
        )]
        result = export_terrain(grimdark_theme, states, project_root)

        assert result.success is False
        assert result.exported_count == 0


# =============================================================================
# TESTS: terrain.json
# =============================================================================

class TestExportTerrainJson:
    """Prueft ob terrain.json korrekt erzeugt wird."""

    def test_creates_terrain_json(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        result = export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        assert json_path.exists()
        assert result.terrain_json_path == str(json_path)

    def test_terrain_json_has_theme_info(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert data["theme"] == "Grimdark Industrial"
        assert data["theme_key"] == "grimdark_industrial"

    def test_terrain_json_has_battle_map(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert data["battle_map"] == "battle_map.png"

    def test_terrain_json_has_base_plates(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert data["base_plates"]["ruins"] == "base_plates/ruins.png"
        assert data["base_plates"]["forest"] == "base_plates/forest.png"
        assert data["base_plates"]["dangerous"] == "base_plates/dangerous.png"

    def test_terrain_json_has_walls(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert len(data["walls"]) >= 2
        wall = data["walls"][0]
        assert "key" in wall
        assert "name" in wall
        assert "length_inches" in wall
        assert "height_inches" in wall
        # Walls have either "texture" (PNG) or "glb" field
        assert "texture" in wall or "glb" in wall

    def test_terrain_json_has_trees(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert len(data["trees"]) >= 2
        tree = data["trees"][0]
        assert "key" in tree
        assert "name" in tree
        assert "glb" in tree

    def test_terrain_json_has_containers(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        export_terrain(grimdark_theme, full_unit_states, project_root)

        json_path = project_root / "assets" / "terrain" / "grimdark_industrial" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert len(data["containers"]) >= 2
        container = data["containers"][0]
        assert "key" in container
        assert "name" in container
        assert "glb" in container


# =============================================================================
# TESTS: ExportResult
# =============================================================================

class TestTerrainExportResult:
    """Prueft ExportResult-Felder."""

    def test_success_result(
        self, grimdark_theme: TerrainTheme, full_unit_states: list[UnitState], tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        result = export_terrain(grimdark_theme, full_unit_states, project_root)

        assert result.success is True
        assert result.exported_count > 0
        assert result.errors == []

    def test_no_ready_units(
        self, grimdark_theme: TerrainTheme, tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        empty_states: list[UnitState] = [
            UnitState(unit_key="x", unit_name="X", status=UnitStatus.PENDING),
        ]
        result = export_terrain(grimdark_theme, empty_states, project_root)

        assert result.success is False
        assert result.exported_count == 0

    def test_missing_file_error(
        self, grimdark_theme: TerrainTheme, tmp_path: Path,
    ) -> None:
        project_root = tmp_path / "project"
        project_root.mkdir()

        states = [UnitState(
            unit_key="wall_test",
            unit_name="Test",
            status=UnitStatus.GLB_READY,
            glb_path="/nonexistent/file.glb",
        )]
        result = export_terrain(grimdark_theme, states, project_root)

        assert len(result.errors) > 0
        assert "nicht gefunden" in result.errors[0]


# =============================================================================
# TESTS: Walls als PNG (Texture-basiert, S4 Seamless Walls)
# =============================================================================

class TestExportTerrainWallTextures:
    """Prueft ob Walls mit texture_prompt als PNG statt GLB exportiert werden."""

    def test_wall_image_exported_as_png(
        self, tmp_path: Path,
    ) -> None:
        """Walls mit IMAGE_APPROVED Status werden als PNG exportiert."""
        from terrain_prompt_engine import WallVariant

        theme = TerrainTheme(
            theme_name="Test Theme", theme_key="test_theme",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="textured_wall", name="Textured Wall",
                length_inches=3.0, height_inches=3.0,
                prompt="3D prompt",
                texture_prompt="Flat texture prompt",
                variants=1,
            )],
        )

        img_path = tmp_path / "wall_textured_wall.png"
        img_path.write_bytes(b"fake-png-data")
        states = [UnitState(
            unit_key="wall_textured_wall",
            unit_name="Textured Wall",
            status=UnitStatus.IMAGE_APPROVED,
            image_path=str(img_path),
        )]

        project_root = tmp_path / "project"
        project_root.mkdir()

        result = export_terrain(theme, states, project_root)
        assert result.success is True
        assert result.exported_count == 1

        wall_png = project_root / "assets" / "terrain" / "test_theme" / "walls" / "textured_wall.png"
        assert wall_png.exists()

    def test_wall_texture_entry_in_terrain_json(
        self, tmp_path: Path,
    ) -> None:
        """terrain.json hat 'texture' statt 'glb' fuer Texture-Walls."""
        from terrain_prompt_engine import WallVariant

        theme = TerrainTheme(
            theme_name="Test Theme", theme_key="test_theme",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="textured_wall", name="Textured Wall",
                length_inches=3.0, height_inches=3.0,
                prompt="3D prompt",
                texture_prompt="Flat texture prompt",
            )],
        )

        img_path = tmp_path / "wall_textured_wall.png"
        img_path.write_bytes(b"fake-png-data")
        states = [UnitState(
            unit_key="wall_textured_wall",
            unit_name="Textured Wall",
            status=UnitStatus.IMAGE_APPROVED,
            image_path=str(img_path),
        )]

        project_root = tmp_path / "project"
        project_root.mkdir()
        export_terrain(theme, states, project_root)

        json_path = project_root / "assets" / "terrain" / "test_theme" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert len(data["walls"]) == 1
        wall = data["walls"][0]
        assert wall["key"] == "textured_wall"
        assert "texture" in wall
        assert wall["texture"] == "walls/textured_wall.png"

    def test_wall_glb_still_works_as_fallback(self, tmp_path: Path) -> None:
        """Walls ohne texture_prompt werden weiterhin als GLB exportiert."""
        from terrain_prompt_engine import WallVariant

        # Theme mit Wall OHNE texture_prompt (nur prompt fuer TRELLIS)
        theme = TerrainTheme(
            theme_name="GLB Theme", theme_key="glb_theme",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="legacy_wall", name="Legacy Wall",
                length_inches=3.0, height_inches=3.0,
                prompt="A 3D wall for TRELLIS.",
            )],
        )

        glb_path = tmp_path / "wall_legacy_wall.glb"
        glb_path.write_bytes(b"fake-glb-data")
        states = [UnitState(
            unit_key="wall_legacy_wall",
            unit_name="Legacy Wall",
            status=UnitStatus.GLB_READY,
            glb_path=str(glb_path),
        )]

        project_root = tmp_path / "project"
        project_root.mkdir()
        result = export_terrain(theme, states, project_root)

        assert result.success is True
        json_path = project_root / "assets" / "terrain" / "glb_theme" / "terrain.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))
        wall = data["walls"][0]
        assert "glb" in wall
        assert wall["glb"] == "walls/legacy_wall.glb"
