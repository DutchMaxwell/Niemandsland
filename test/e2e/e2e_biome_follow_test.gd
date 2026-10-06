extends GdUnitTestSuite
## S8.5 (lead D19 = a, 06.10.): every free piece that has a biome form — ruins and woods — follows when the table's
## biome changes, in place: same network id, spot and floors, the new biome's wall panels and trees. Loading a saved
## table changes nothing (the load sets the biome before the pieces arrive). Solids keep their id (they tint, S8.2).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SAVE := "user://e2e_biome_follow.nml"

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
	_main.table.set_biome("temperate_grassland")


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _ids() -> Dictionary:
	var out := {}
	for n in ObjectManager.sandbox_pieces(_main.get_tree()):
		out[int(n.get_meta("network_id"))] = [str(n.get_meta("prop_id")), n.global_position]
	return out


func test_ruins_and_woods_follow_a_biome_change_but_not_a_load() -> void:
	var om: ObjectManager = _main.object_manager
	om.spawn_sandbox_terrain("desert_ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector3(0.3, 0, 0.1), false, 7901)
	om.spawn_sandbox_terrain("desert_forest_small", ObjectManager.SandboxPropKind.FOREST, Vector3(-0.3, 0, 0.1), false, 7902)
	om.spawn_sandbox_terrain("longhouse_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector3(0.0, 0, -0.2), false, 7903)
	await _runner.simulate_frames(2)
	assert_int(_main.save_manager.save_game(SAVE)).is_equal(OK)
	assert_int(await _main.save_manager.load_game(SAVE)).is_equal(OK)
	await _runner.simulate_frames(4)
	var loaded := _ids()
	assert_str(loaded[7901][0]).override_failure_message("a load re-skinned the ruin").is_equal("desert_ruin_small_1f")
	_main.table.set_biome("frozen_tundra")
	await _runner.simulate_frames(2)
	var now := _ids()
	assert_str(now[7901][0]).override_failure_message("the ruin did not follow").is_equal("tundra_ruin_small_1f")
	assert_str(now[7902][0]).override_failure_message("the wood did not follow").is_equal("tundra_forest_small")
	assert_str(now[7903][0]).is_equal("longhouse_6x3")
	for id: int in [7901, 7902, 7903]:
		assert_vector(now[id][1]).is_equal_approx(loaded[id][1], Vector3.ONE * 1e-5)   # in place
	_main.table.set_biome("temperate_grassland")
	await _runner.simulate_frames(2)
	assert_str(_ids()[7902][0]).is_equal("forest_small")
