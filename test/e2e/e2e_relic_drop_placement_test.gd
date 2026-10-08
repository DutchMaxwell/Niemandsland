extends GdUnitTestSuite
## NML-1010 wave C step C3: opponent places a dropped relic within 1" of the carrier's base.

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
	_main.terrain_overlay.update_objectives([Vector3.ZERO])
	SoloController.mission_markers = [{"carry": true, "carried_by": "carrier"}]


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _units(carrier_side: int) -> Array:
	var carrier := E2EBoot.make_unit(_main, carrier_side, "Carrier", [Vector3.ZERO])
	carrier.unit_id = "carrier"
	var opponent := E2EBoot.make_unit(_main, 3 - carrier_side, "Opponent", [Vector3(0.5, 0, 0)])
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	_main.opr_army_manager.game_units[opponent.unit_id] = opponent
	return [carrier, opponent]


func _click_inch(editor: Control, inch_pos: Vector2) -> void:
	var canvas_pos: Vector2 = editor.grid_container.get_global_transform() * editor._inch_to_screen_pos(inch_pos)
	E2EBoot.motion_canvas(get_viewport(), canvas_pos)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, true)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, false)


func test_ai_opponent_drop_lands_one_inch_from_base_edge() -> void:
	var pair := _units(1)
	var carrier := pair[0] as GameUnit
	var radius := SoloController.model_base_radius_m(carrier.models[0] as ModelInstance)
	_main._solo_drop_carried(carrier, "shaken")
	var pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(pos.x).is_equal_approx(radius + 0.0254, 0.0001)
	assert_float(pos.z).is_equal_approx(0.0, 0.0001)


func test_human_opponent_receives_placement_prompt() -> void:
	var pair := _units(2)
	_main._solo_drop_carried(pair[0] as GameUnit, "shaken")
	await _runner.simulate_frames(2)  # the newly shown Map Tool must lay out its grid before a click
	assert_bool(_main.map_layout_editor.visible).is_true()
	if not _main.map_layout_editor.visible:
		return
	assert_bool(_main.map_layout_editor.relic_drop_active).is_true()
	var editor: Control = _main.map_layout_editor
	var centre: Vector2 = editor.relic_drop_centre
	var radius: float = editor.relic_drop_radius_in
	var default_pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	_click_inch(editor, centre + Vector2(radius + 1.5, 0))
	assert_bool(editor.relic_drop_active).is_true()
	assert_float((_main.terrain_overlay.get_objectives()[0] as Vector3).x).is_equal_approx(default_pos.x, 0.0001)
	_click_inch(editor, centre + Vector2(radius + 0.7, 0))
	assert_bool(editor.visible).is_false()
	var chosen: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(chosen.x).is_equal_approx((radius + 0.7) * 0.0254, 0.0001)
	assert_str(str(_main.battle_log.entries().back().get("text", ""))).contains("placed by P1")


func test_skip_keeps_the_deterministic_point() -> void:
	var pair := _units(2)
	_main._solo_drop_carried(pair[0] as GameUnit, "destroyed")
	await _runner.simulate_frames(2)
	var default_pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	var close: Button = _main.map_layout_editor.close_button
	var at: Vector2 = close.get_global_rect().get_center()
	E2EBoot.motion_canvas(_main.get_viewport(), at)
	E2EBoot.click_canvas(_main.get_viewport(), at, true)
	E2EBoot.click_canvas(_main.get_viewport(), at, false)
	assert_bool(_main.map_layout_editor.visible).is_false()
	assert_float((_main.terrain_overlay.get_objectives()[0] as Vector3).x).is_equal_approx(default_pos.x, 0.0001)
	assert_str(str(_main.battle_log.entries().back().get("text", ""))).contains("placed by P1")


func test_timeout_keeps_the_deterministic_point() -> void:
	var pair := _units(2)
	_main._solo_drop_carried(pair[0] as GameUnit, "shaken")
	var default_pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	_main._solo_relic_drop_timeout(_main._solo_relic_drop_gen)
	assert_bool(_main.map_layout_editor.visible).is_false()
	assert_float((_main.terrain_overlay.get_objectives()[0] as Vector3).x).is_equal_approx(default_pos.x, 0.0001)
