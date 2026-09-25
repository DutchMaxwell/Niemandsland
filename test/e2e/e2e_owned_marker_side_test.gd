extends GdUnitTestSuite

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
	_main.terrain_overlay.set_deployment_colors_flipped(false)
	_main._solo_deploy_fsm = {"phase": "side", "winner_is_ai": false,
		"w": 1.8, "d": 1.2, "depth": 0.3048, "objectives": [], "seed": 17}


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _owners() -> Array:
	var result := []
	for marker in SoloController.mission_markers:
		result.append(int((marker as Dictionary).get("owned_by", 0)))
	return result


func _log_text() -> String:
	var lines: PackedStringArray = []
	for entry in _main.battle_log.entries():
		lines.append(str((entry as Dictionary).get("text", "")))
	return "\n".join(lines)


func test_sabotage_swap_gives_each_side_its_own_edge_marker(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_mission_id = "sabotage"
	_main._solo_apply_mission_if_chosen()
	var positions: Array = _main.terrain_overlay.get_objectives()
	assert_bool((positions[0] as Vector3).z < 0.0).is_true()
	assert_bool((positions[1] as Vector3).z > 0.0).is_true()
	await _main._solo_deploy_pick_side(true)
	# Marker order is -Z then +Z. After swap P1/human is on +Z.
	assert_array(_owners()).is_equal([2, 1])
	assert_str(_log_text()).contains("P2 owns the -Z marker; P1 owns the +Z marker")


func test_demolition_human_in_slot_two_owns_negative_edge(timeout := 120000) -> void:
	_main.solo_ai_slots = {1: true}
	_main._ensure_solo_controller()
	_main._solo_mission_id = "demolition"
	_main._solo_apply_mission_if_chosen()
	await _main._solo_deploy_begin_side(false)   # AI/P1 takes +Z; human/P2 takes -Z
	assert_array(_owners()).is_equal([2, 1])
