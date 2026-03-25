"""Tests fuer TerrainPromptEngine (modulares Format)."""

import pytest
from pathlib import Path

from terrain_prompt_engine import (
    WallVariant,
    TreeVariant,
    ContainerVariant,
    TerrainTheme,
    TerrainPromptEngine,
    load_terrain_theme,
    scan_terrain_themes,
)


# =============================================================================
# FIXTURES
# =============================================================================

TERRAIN_THEMES_DIR = Path(__file__).parent.parent / "terrain_themes"


@pytest.fixture
def grimdark_theme() -> TerrainTheme:
    """Laedt das grimdark_industrial Theme."""
    yaml_path = TERRAIN_THEMES_DIR / "grimdark_industrial.yaml"
    return load_terrain_theme(yaml_path)


@pytest.fixture
def minimal_theme_data() -> dict:
    """Minimales valides Theme-Dictionary im neuen modularen Format."""
    return {
        "theme_name": "Test Theme",
        "theme_key": "test_theme",
        "aesthetic": {
            "genre": "test genre",
            "style": "test style",
            "inspiration": ["test"],
            "explicitly_avoid": ["nothing"],
        },
        "colors": {
            "primary": "red",
            "secondary": "blue",
            "accent": "green",
        },
        "materials": ["stone", "wood"],
        "battle_map": {
            "prompt": "Top-down test battlefield ground.",
        },
        "base_plates": {
            "ruins": {"prompt": "Ruins floor texture."},
            "forest": {"prompt": "Forest floor texture."},
            "dangerous": {"prompt": "Dangerous floor texture."},
        },
        "walls": [
            {
                "key": "test_wall_3inch",
                "name": "Test Wall (3\")",
                "length_inches": 3,
                "height_inches": 3,
                "prompt": "A test wall segment.",
            },
        ],
        "trees": [
            {
                "key": "test_tree",
                "name": "Test Tree",
                "prompt": "A test tree.",
            },
        ],
        "containers": [
            {
                "key": "test_container",
                "name": "Test Container",
                "prompt": "A test container.",
            },
        ],
    }


@pytest.fixture
def minimal_theme(minimal_theme_data: dict) -> TerrainTheme:
    """TerrainTheme aus minimalem Dictionary."""
    return TerrainTheme.from_dict(minimal_theme_data)


# =============================================================================
# WallVariant TESTS
# =============================================================================

class TestWallVariant:
    """Tests fuer WallVariant Datenklasse."""

    def test_create(self) -> None:
        wall = WallVariant(
            key="test_wall",
            name="Test Wall",
            length_inches=3.0,
            height_inches=3.0,
            prompt="A wall prompt.",
        )
        assert wall.key == "test_wall"
        assert wall.length_inches == 3.0
        assert wall.height_inches == 3.0

    def test_short_wall(self) -> None:
        wall = WallVariant(
            key="short_wall",
            name="Short Wall",
            length_inches=1.0,
            height_inches=1.5,
            prompt="A short wall.",
        )
        assert wall.length_inches == 1.0
        assert wall.height_inches == 1.5


# =============================================================================
# TreeVariant TESTS
# =============================================================================

class TestTreeVariant:
    """Tests fuer TreeVariant Datenklasse."""

    def test_create(self) -> None:
        tree = TreeVariant(key="oak", name="Oak Tree", prompt="An oak tree.")
        assert tree.key == "oak"
        assert tree.name == "Oak Tree"


# =============================================================================
# ContainerVariant TESTS
# =============================================================================

class TestContainerVariant:
    """Tests fuer ContainerVariant Datenklasse."""

    def test_create(self) -> None:
        container = ContainerVariant(
            key="crate", name="Crate", prompt="A crate."
        )
        assert container.key == "crate"
        assert container.name == "Crate"


# =============================================================================
# TerrainTheme TESTS
# =============================================================================

class TestTerrainTheme:
    """Tests fuer TerrainTheme Datenklasse."""

    def test_from_dict(self, minimal_theme: TerrainTheme) -> None:
        assert minimal_theme.theme_name == "Test Theme"
        assert minimal_theme.theme_key == "test_theme"

    def test_from_dict_battle_map(self, minimal_theme: TerrainTheme) -> None:
        assert "test battlefield" in minimal_theme.battle_map_prompt

    def test_from_dict_base_plates(self, minimal_theme: TerrainTheme) -> None:
        assert "ruins" in minimal_theme.base_plate_prompts
        assert "forest" in minimal_theme.base_plate_prompts
        assert "dangerous" in minimal_theme.base_plate_prompts

    def test_from_dict_walls(self, minimal_theme: TerrainTheme) -> None:
        assert len(minimal_theme.walls) == 1
        assert minimal_theme.walls[0].key == "test_wall_3inch"
        assert minimal_theme.walls[0].length_inches == 3

    def test_from_dict_trees(self, minimal_theme: TerrainTheme) -> None:
        assert len(minimal_theme.trees) == 1
        assert minimal_theme.trees[0].key == "test_tree"

    def test_from_dict_containers(self, minimal_theme: TerrainTheme) -> None:
        assert len(minimal_theme.containers) == 1
        assert minimal_theme.containers[0].key == "test_container"

    def test_from_dict_missing_theme_name_raises(self, minimal_theme_data: dict) -> None:
        del minimal_theme_data["theme_name"]
        with pytest.raises(KeyError):
            TerrainTheme.from_dict(minimal_theme_data)

    def test_from_dict_missing_battle_map_raises(self, minimal_theme_data: dict) -> None:
        del minimal_theme_data["battle_map"]
        with pytest.raises(KeyError):
            TerrainTheme.from_dict(minimal_theme_data)

    def test_from_dict_missing_base_plates_raises(self, minimal_theme_data: dict) -> None:
        del minimal_theme_data["base_plates"]
        with pytest.raises(KeyError):
            TerrainTheme.from_dict(minimal_theme_data)

    def test_from_dict_empty_walls_allowed(self, minimal_theme_data: dict) -> None:
        minimal_theme_data["walls"] = []
        theme = TerrainTheme.from_dict(minimal_theme_data)
        assert len(theme.walls) == 0

    def test_from_dict_missing_walls_defaults_empty(self, minimal_theme_data: dict) -> None:
        del minimal_theme_data["walls"]
        theme = TerrainTheme.from_dict(minimal_theme_data)
        assert len(theme.walls) == 0

    def test_from_dict_missing_trees_defaults_empty(self, minimal_theme_data: dict) -> None:
        del minimal_theme_data["trees"]
        theme = TerrainTheme.from_dict(minimal_theme_data)
        assert len(theme.trees) == 0

    def test_from_dict_missing_containers_defaults_empty(self, minimal_theme_data: dict) -> None:
        del minimal_theme_data["containers"]
        theme = TerrainTheme.from_dict(minimal_theme_data)
        assert len(theme.containers) == 0

    def test_materials(self, minimal_theme: TerrainTheme) -> None:
        assert minimal_theme.materials == ["stone", "wood"]

    def test_aesthetic(self, minimal_theme: TerrainTheme) -> None:
        assert minimal_theme.aesthetic["genre"] == "test genre"

    def test_colors(self, minimal_theme: TerrainTheme) -> None:
        assert minimal_theme.colors["primary"] == "red"


# =============================================================================
# load_terrain_theme TESTS
# =============================================================================

class TestLoadTerrainTheme:
    """Tests fuer load_terrain_theme Funktion."""

    def test_load_grimdark(self, grimdark_theme: TerrainTheme) -> None:
        assert grimdark_theme.theme_name == "Grimdark Industrial"
        assert grimdark_theme.theme_key == "grimdark_industrial"

    def test_load_grimdark_has_battle_map(self, grimdark_theme: TerrainTheme) -> None:
        assert len(grimdark_theme.battle_map_prompt) > 10

    def test_load_grimdark_has_base_plates(self, grimdark_theme: TerrainTheme) -> None:
        assert "ruins" in grimdark_theme.base_plate_prompts
        assert "forest" in grimdark_theme.base_plate_prompts
        assert "dangerous" in grimdark_theme.base_plate_prompts

    def test_load_grimdark_has_walls(self, grimdark_theme: TerrainTheme) -> None:
        assert len(grimdark_theme.walls) >= 2

    def test_load_grimdark_has_trees(self, grimdark_theme: TerrainTheme) -> None:
        assert len(grimdark_theme.trees) >= 2

    def test_load_grimdark_has_containers(self, grimdark_theme: TerrainTheme) -> None:
        assert len(grimdark_theme.containers) >= 2

    def test_load_missing_file_raises(self) -> None:
        with pytest.raises(FileNotFoundError):
            load_terrain_theme(Path("/nonexistent/theme.yaml"))

    def test_load_all_themes_valid(self) -> None:
        """Alle 6 Theme-YAMLs muessen ladbar sein."""
        for yaml_file in TERRAIN_THEMES_DIR.glob("*.yaml"):
            theme = load_terrain_theme(yaml_file)
            assert theme.theme_name
            assert theme.theme_key
            assert len(theme.battle_map_prompt) > 0
            assert len(theme.base_plate_prompts) == 3
            assert len(theme.walls) >= 2
            assert len(theme.trees) >= 2
            assert len(theme.containers) >= 2

    def test_wall_variants_have_required_fields(self) -> None:
        """Alle Wand-Varianten in allen Themes muessen gueltige Felder haben."""
        for yaml_file in TERRAIN_THEMES_DIR.glob("*.yaml"):
            theme = load_terrain_theme(yaml_file)
            for wall in theme.walls:
                assert wall.key
                assert wall.name
                assert wall.length_inches > 0
                assert wall.height_inches > 0
                assert len(wall.prompt) > 0


# =============================================================================
# scan_terrain_themes TESTS
# =============================================================================

class TestScanTerrainThemes:
    """Tests fuer scan_terrain_themes Funktion."""

    def test_finds_themes(self) -> None:
        themes = scan_terrain_themes(TERRAIN_THEMES_DIR)
        assert len(themes) >= 6

    def test_returns_theme_keys(self) -> None:
        themes = scan_terrain_themes(TERRAIN_THEMES_DIR)
        assert "grimdark_industrial" in themes
        assert "fantasy_medieval" in themes
        assert "desert_wasteland" in themes

    def test_empty_dir_returns_empty(self, tmp_path: Path) -> None:
        themes = scan_terrain_themes(tmp_path)
        assert themes == []

    def test_nonexistent_dir_returns_empty(self) -> None:
        themes = scan_terrain_themes(Path("/nonexistent/dir"))
        assert themes == []


# =============================================================================
# TerrainPromptEngine TESTS
# =============================================================================

class TestTerrainPromptEngine:
    """Tests fuer TerrainPromptEngine."""

    def test_get_battle_map_prompt(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompt = engine.get_battle_map_prompt()
        assert "industrial wasteland" in prompt.lower()

    def test_get_base_plate_prompts(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_base_plate_prompts()
        assert len(prompts) == 3
        assert "ruins" in prompts
        assert "forest" in prompts
        assert "dangerous" in prompts
        for prompt in prompts.values():
            assert len(prompt) > 10

    def test_get_wall_prompts(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_wall_prompts()
        assert len(prompts) >= 2
        for key, prompt in prompts.items():
            assert len(key) > 0
            assert len(prompt) > 10

    def test_get_tree_prompts(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_tree_prompts()
        assert len(prompts) >= 2
        for key, prompt in prompts.items():
            assert len(key) > 0
            assert len(prompt) > 10

    def test_get_container_prompts(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_container_prompts()
        assert len(prompts) >= 2
        for key, prompt in prompts.items():
            assert len(key) > 0
            assert len(prompt) > 10

    def test_get_all_prompts(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_all_prompts()
        # Should contain: battle_map + 3 base_plates + walls + trees + containers
        assert "battle_map" in prompts
        assert "base_plate_ruins" in prompts
        assert "base_plate_forest" in prompts
        assert "base_plate_dangerous" in prompts
        # Should have wall/tree/container keys too
        wall_keys = [k for k in prompts if k.startswith("wall_")]
        tree_keys = [k for k in prompts if k.startswith("tree_")]
        container_keys = [k for k in prompts if k.startswith("container_")]
        assert len(wall_keys) >= 2
        assert len(tree_keys) >= 2
        assert len(container_keys) >= 2

    def test_get_all_prompts_total_count(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_all_prompts()
        # Walls with variants > 1 expand to multiple keys
        wall_count = sum(
            wall.variants if wall.variants > 1 else 1
            for wall in grimdark_theme.walls
        )
        expected = (
            1  # battle_map
            + 3  # base_plates
            + wall_count
            + len(grimdark_theme.trees)
            + len(grimdark_theme.containers)
        )
        assert len(prompts) == expected

    def test_get_all_prompts_minimal(self, minimal_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(minimal_theme)
        prompts = engine.get_all_prompts()
        assert "battle_map" in prompts
        assert "base_plate_ruins" in prompts
        assert "wall_test_wall_3inch" in prompts
        assert "tree_test_tree" in prompts
        assert "container_test_container" in prompts
        assert len(prompts) == 1 + 3 + 1 + 1 + 1

    def test_wall_prompts_contain_wall_content(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_wall_prompts()
        for prompt in prompts.values():
            assert "wall" in prompt.lower() or "barrier" in prompt.lower()

    def test_tree_prompts_contain_tree_content(self, grimdark_theme: TerrainTheme) -> None:
        engine = TerrainPromptEngine(grimdark_theme)
        prompts = engine.get_tree_prompts()
        for prompt in prompts.values():
            assert "tree" in prompt.lower() or "mushroom" in prompt.lower() or "fungal" in prompt.lower()


# =============================================================================
# TEXTURE_PROMPT + VARIANTS TESTS (S4 Seamless Walls)
# =============================================================================

class TestWallVariantTexturePrompt:
    """Tests fuer WallVariant texture_prompt und variants Felder."""

    def test_texture_prompt_field(self) -> None:
        wall = WallVariant(
            key="textured_wall",
            name="Textured Wall",
            length_inches=3.0,
            height_inches=3.0,
            prompt="A 3D wall prompt.",
            texture_prompt="Seamless flat wall surface texture.",
            variants=1,
        )
        assert wall.texture_prompt == "Seamless flat wall surface texture."

    def test_texture_prompt_defaults_empty(self) -> None:
        wall = WallVariant(
            key="basic_wall",
            name="Basic Wall",
            length_inches=3.0,
            height_inches=3.0,
            prompt="A basic wall.",
        )
        assert wall.texture_prompt == ""

    def test_variants_defaults_one(self) -> None:
        wall = WallVariant(
            key="basic_wall",
            name="Basic Wall",
            length_inches=3.0,
            height_inches=3.0,
            prompt="A basic wall.",
        )
        assert wall.variants == 1

    def test_variants_custom_value(self) -> None:
        wall = WallVariant(
            key="varied_wall",
            name="Varied Wall",
            length_inches=3.0,
            height_inches=3.0,
            prompt="A wall.",
            variants=3,
        )
        assert wall.variants == 3


class TestTerrainThemeTexturePrompt:
    """Tests fuer TerrainTheme Parsing mit texture_prompt."""

    def test_from_dict_reads_texture_prompt(self) -> None:
        data = {
            "theme_name": "Test", "theme_key": "test",
            "aesthetic": {"genre": "t", "style": "t", "inspiration": [], "explicitly_avoid": []},
            "colors": {"primary": "r", "secondary": "b", "accent": "g"},
            "materials": ["stone"],
            "battle_map": {"prompt": "map prompt"},
            "base_plates": {"ruins": {"prompt": "ruins"}},
            "walls": [{
                "key": "w1", "name": "W1",
                "length_inches": 3, "height_inches": 3,
                "prompt": "3D prompt",
                "texture_prompt": "Flat texture prompt",
                "variants": 2,
            }],
        }
        theme = TerrainTheme.from_dict(data)
        assert theme.walls[0].texture_prompt == "Flat texture prompt"
        assert theme.walls[0].variants == 2

    def test_from_dict_missing_texture_prompt_defaults(self) -> None:
        data = {
            "theme_name": "Test", "theme_key": "test",
            "aesthetic": {"genre": "t", "style": "t", "inspiration": [], "explicitly_avoid": []},
            "colors": {"primary": "r", "secondary": "b", "accent": "g"},
            "materials": ["stone"],
            "battle_map": {"prompt": "map prompt"},
            "base_plates": {"ruins": {"prompt": "ruins"}},
            "walls": [{
                "key": "w1", "name": "W1",
                "length_inches": 3, "height_inches": 3,
                "prompt": "3D prompt",
            }],
        }
        theme = TerrainTheme.from_dict(data)
        assert theme.walls[0].texture_prompt == ""
        assert theme.walls[0].variants == 1


class TestPromptEngineTexturePrompt:
    """Tests fuer TerrainPromptEngine mit texture_prompt Bevorzugung."""

    def test_get_wall_prompts_prefers_texture_prompt(self) -> None:
        theme = TerrainTheme(
            theme_name="T", theme_key="t",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="w1", name="W1",
                length_inches=3.0, height_inches=3.0,
                prompt="3D prompt",
                texture_prompt="Texture prompt",
            )],
        )
        engine = TerrainPromptEngine(theme)
        prompts = engine.get_wall_prompts()
        assert prompts["w1"] == "Texture prompt"

    def test_get_wall_prompts_falls_back_to_prompt(self) -> None:
        theme = TerrainTheme(
            theme_name="T", theme_key="t",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="w1", name="W1",
                length_inches=3.0, height_inches=3.0,
                prompt="3D prompt",
            )],
        )
        engine = TerrainPromptEngine(theme)
        prompts = engine.get_wall_prompts()
        assert prompts["w1"] == "3D prompt"

    def test_get_wall_prompts_expands_variants(self) -> None:
        theme = TerrainTheme(
            theme_name="T", theme_key="t",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="w1", name="W1",
                length_inches=3.0, height_inches=3.0,
                prompt="3D prompt",
                texture_prompt="Texture prompt",
                variants=3,
            )],
        )
        engine = TerrainPromptEngine(theme)
        prompts = engine.get_wall_prompts()
        assert "w1_v0" in prompts
        assert "w1_v1" in prompts
        assert "w1_v2" in prompts
        assert len(prompts) == 3

    def test_get_wall_prompts_single_variant_no_suffix(self) -> None:
        theme = TerrainTheme(
            theme_name="T", theme_key="t",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={},
            walls=[WallVariant(
                key="w1", name="W1",
                length_inches=3.0, height_inches=3.0,
                prompt="prompt",
                variants=1,
            )],
        )
        engine = TerrainPromptEngine(theme)
        prompts = engine.get_wall_prompts()
        assert "w1" in prompts
        assert len(prompts) == 1

    def test_get_all_prompts_uses_texture_prompt_and_variants(self) -> None:
        theme = TerrainTheme(
            theme_name="T", theme_key="t",
            aesthetic={}, colors={}, materials=[],
            battle_map_prompt="map",
            base_plate_prompts={"ruins": "r"},
            walls=[WallVariant(
                key="w1", name="W1",
                length_inches=3.0, height_inches=3.0,
                prompt="3D prompt",
                texture_prompt="Texture prompt",
                variants=2,
            )],
        )
        engine = TerrainPromptEngine(theme)
        prompts = engine.get_all_prompts()
        assert "wall_w1_v0" in prompts
        assert "wall_w1_v1" in prompts
        assert prompts["wall_w1_v0"] == "Texture prompt"
