extends GdUnitTestSuite
## Free shelf pieces count for the rules in EVERY game on the real scenes/main.tscn, not only once a Solo AI
## controller exists. The overlay's sandbox_shapes_provider used to be wired in main._ensure_solo_controller() alone,
## so in a human-vs-human, multiplayer or tutorial game a free forest gave no cover or difficulty, a free ruin blocked
## no sight, and the sight fan / LOS checks ignored them (measured 03.10. on main 3b3077cc: three free pieces on the
## table, every point inside them read NONE).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const FOREST_AT := Vector3(0.30, 0.0, 0.10)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_free_forest_counts_in_a_game_without_a_solo_ai() -> void:
	assert_object(_main.solo_controller).is_null()   # a human game: no AI controller was ever built
	_main.terrain_overlay.grid_cells.clear()          # nothing painted under the piece: only the free OBB can answer
	_main.object_manager.spawn_sandbox_terrain("forest_small", ObjectManager.SandboxPropKind.FOREST, FOREST_AT, false, 7201)
	await _runner.simulate_frames(2)
	assert_int(_main.terrain_overlay.get_terrain_at_world_position(FOREST_AT)).is_equal(TerrainRules.TerrainType.FOREST)
	var areas: Array = (_main.terrain_overlay.los_volumes() as Array).filter(
		func(v: Dictionary) -> bool: return not bool(v.get("solid", true)))
	assert_int(areas.size()).is_equal(1)   # the forest's area sight hull (see in/out, not through)


## Delete hides a free piece (undoable, "deleted" meta) instead of freeing it. The rules must then ignore it: a
## deleted solid that still blocked sight and movement would be an invisible wall (found 05.10. while planning the
## theme's replace step).
func test_a_deleted_free_piece_stops_counting_for_the_rules() -> void:
	_main.terrain_overlay.grid_cells.clear()
	var solid: Node3D = _main.object_manager.spawn_sandbox_terrain("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER,
		FOREST_AT, false, 7202)
	await _runner.simulate_frames(2)
	assert_int(_main.terrain_overlay.get_terrain_at_world_position(FOREST_AT)).is_equal(TerrainRules.TerrainType.CONTAINER)
	_main.radial_menu_controller.delete_objects([solid])   # the Delete-key path
	await _runner.simulate_frames(2)
	assert_bool(solid.visible).is_false()
	assert_int(_main.terrain_overlay.get_terrain_at_world_position(FOREST_AT)).is_equal(TerrainRules.TerrainType.NONE)
	assert_int((_main.terrain_overlay.los_volumes() as Array).size()).is_equal(0)
	assert_float(_main.object_manager._surface_y_under(FOREST_AT)).is_less(0.005)   # a model set down here stands on the table
