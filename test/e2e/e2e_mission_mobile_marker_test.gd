extends GdUnitTestSuite
## NML-1010 wave D, D10a — the VIP marker (`mobile: true`) moves at round start while the defender
## controls it: a human defender clicks a free point within 12" (the C3 click flow), the AI walks it
## straight toward the target edge (R10a: 12" or until 6" from the edge). No shipped mission has the
## flag yet (D14.4), so the markers are set directly.

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
	_main.solo_ai_slots = {2: true}   # plan 2.2: no implicit NACHTMAHR — this table designates player 2 explicitly
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.terrain_overlay.update_objectives([Vector3.ZERO], [2])
	SoloController.mission_markers = [{"mobile": true, "deploy_edge": 1}]
	SoloController.mission_roles = {"attacker": 1, "defender": 2}


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _click_inch(editor: Control, inch_pos: Vector2) -> void:
	var canvas_pos: Vector2 = editor.grid_container.get_global_transform() * editor._inch_to_screen_pos(inch_pos)
	E2EBoot.motion_canvas(get_viewport(), canvas_pos)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, true)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, false)


func _z_in() -> float:
	return (_main.terrain_overlay.get_objectives()[0] as Vector3).z / 0.0254


func test_vip_walk_point_is_twelve_inches_then_stops_six_from_the_edge() -> void:
	assert_float(SoloController.vip_walk_z(0.0, 1, 48.0)).is_equal_approx(-12.0, 0.001)
	assert_float(SoloController.vip_walk_z(-10.0, 1, 48.0)).is_equal_approx(-18.0, 0.001)
	assert_float(SoloController.vip_walk_z(-18.0, 1, 48.0)).is_equal_approx(-18.0, 0.001)
	assert_float(SoloController.vip_walk_z(0.0, -1, 48.0)).is_equal_approx(12.0, 0.001)


func test_ai_defender_walks_the_marker_and_logs_it() -> void:
	_main.solo_ai_slots = {2: true}
	_main.solo_controller.human_slot = 1
	_main._solo_mobile_marker_round_start()
	assert_float(_z_in()).is_equal_approx(-12.0, 0.01)
	assert_str(str(_main.battle_log.entries().back().get("text", ""))).contains("moves the marker")


func test_a_marker_the_attacker_holds_stays_put() -> void:
	_main.terrain_overlay.update_objectives([Vector3.ZERO], [1])
	_main.solo_ai_slots = {2: true}
	_main._solo_mobile_marker_round_start()
	assert_float(_z_in()).is_equal_approx(0.0, 0.01)


func test_human_defender_click_beyond_twelve_inches_is_refused() -> void:
	SoloController.mission_roles = {"attacker": 2, "defender": 1}
	_main.terrain_overlay.update_objectives([Vector3.ZERO], [1])
	_main.solo_ai_slots = {2: true}
	_main.solo_controller.human_slot = 1
	_main._solo_mobile_marker_round_start()
	await _runner.simulate_frames(2)
	var editor: Control = _main.map_layout_editor
	assert_bool(editor.relic_drop_active).is_true()
	var centre: Vector2 = editor.relic_drop_centre
	_click_inch(editor, centre + Vector2(0, -13))
	assert_bool(editor.relic_drop_active).is_true()
	assert_float(_z_in()).is_equal_approx(0.0, 0.01)
	_click_inch(editor, centre + Vector2(0, -11))
	assert_bool(editor.visible).is_false()
	assert_float(_z_in()).is_equal_approx(-11.0, 0.05)
