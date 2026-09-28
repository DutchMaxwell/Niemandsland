extends GdUnitTestSuite
## NML-1010 C3a: the deterministic drop uses the carrier's base edge.

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
	_main._ensure_solo_controller()
	_main.terrain_overlay.update_objectives([Vector3.ZERO])
	SoloController.mission_markers = [{"carry": true, "carried_by": "carrier"}]


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_drop_lands_one_inch_from_base_edge_toward_nearest_opponent() -> void:
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3.ZERO])
	carrier.unit_id = "carrier"
	var opponent := E2EBoot.make_unit(_main, 2, "Opponent", [Vector3(0.5, 0, 0)])
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	_main.opr_army_manager.game_units[opponent.unit_id] = opponent
	var radius := SoloController.model_base_radius_m(carrier.models[0] as ModelInstance)
	_main._solo_drop_carried(carrier, "shaken")
	var pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(pos.x).is_equal_approx(radius + 0.0254, 0.0001)
	assert_float(pos.z).is_equal_approx(0.0, 0.0001)
	assert_str(str(_main.battle_log.entries().back().get("text", ""))).contains("placed by P2")
