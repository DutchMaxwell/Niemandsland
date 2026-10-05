extends GdUnitTestSuite
## The one-click Ruined Borderland table on the real scenes/main.tscn (5.2b-1): main.apply_table_theme lays the theme
## out as ONE undo step on the table's history; refused on painted grid terrain (D9), on a table of another size
## (D11) and once the game is being played. No model downloads in the test (empty model manifest).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.object_manager.solid_models_library().apply_manifest_text("{}")
	_main.table.setup_table(Vector2(6, 4))
	_main.terrain_overlay.grid_cells.clear()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _live() -> int:
	return ObjectManager.sandbox_pieces(_main.get_tree()).filter(func(n: Node) -> bool:
		return not bool(n.get_meta("deleted", false))).size()


func test_the_theme_lays_out_and_one_undo_takes_it_back() -> void:
	var biome_before: String = _main.table.biome
	assert_bool(_main.apply_table_theme("ruined_borderland")).is_true()
	assert_int(_live()).is_equal(14)
	assert_str(_main.table.biome).is_equal("temperate_grassland")
	_main.undo_manager.undo()
	assert_int(_live()).is_equal(0)
	assert_str(_main.table.biome).is_equal(biome_before)


func test_refused_on_painted_grid_terrain_on_another_size_and_in_play() -> void:
	_main.terrain_overlay.grid_cells[Vector2i(2, 2)] = TerrainRules.TerrainType.RUINS
	assert_bool(_main.apply_table_theme("ruined_borderland")).is_false()   # D9
	_main.terrain_overlay.grid_cells.clear()
	_main.table.setup_table(Vector2(4, 4))
	assert_bool(_main.apply_table_theme("ruined_borderland")).is_false()   # D11
	_main.table.setup_table(Vector2(6, 4))
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	assert_bool(_main.apply_table_theme("ruined_borderland")).is_false()   # in play
	assert_int(_live()).is_equal(0)
