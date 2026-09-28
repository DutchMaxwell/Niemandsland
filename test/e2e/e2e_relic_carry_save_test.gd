extends GdUnitTestSuite
## NML-1010 C4: the load-completed seam rebinds carried markers to restored units.

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
	_main.terrain_overlay.update_objectives([Vector3.ZERO])
	SoloController.mission_reset("end", {}, [{"carry": true, "carried_by": "carrier"}])


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_carried_marker_follows_restored_carrier_and_hides() -> void:
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3(0.2, 0, -0.1)])
	carrier.unit_id = "carrier"
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	var wire: Dictionary = JSON.parse_string(JSON.stringify(_main.save_manager._serialize_game_state()))
	SoloController.mission_reset("end", {})
	_main.save_manager._deserialize_game_state(wire)
	_main._on_load_completed(0)
	assert_str(str(SoloController.mission_markers[0].get("carried_by", ""))).is_equal("carrier")
	var pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(pos.x).is_equal_approx(0.2, 0.0001)
	assert_float(pos.z).is_equal_approx(-0.1, 0.0001)
	assert_bool(_main.terrain_overlay.objective_meshes[0].visible).is_false()
