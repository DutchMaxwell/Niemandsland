extends GdUnitTestSuite
## E2E — NML-1033: the F key with an EMPTY selection must fall back to toggling the
## arcs on EVERY regiment (the pre-regression behavior). The selected-only change
## shipped untested and read as "F is broken" at the table: without a selected tray
## the press was a silent no-op. This suite drives the REAL dispatch — a real
## InputEventKey(F) through the viewport into main.gd's real _unhandled_key_input —
## on the real scenes/main.tscn, with a real RegimentTray built by the real manager.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tray_via_real_manager() -> RegimentTray:
	var gu := GameUnit.new()
	gu.unit_id = "e2e_arc_unit"
	gu.unit_properties = {"player_id": 1, "name": "ArcTester", "quality": 4, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	_main.add_child(n)
	m.node = n
	gu.models.append(m)
	var regiment = _main.opr_army_manager.restore_regiment(gu, 1, Vector3.ZERO, 0.0)
	assert_that(regiment).is_not_null()
	return regiment.tray as RegimentTray


func _press_f() -> void:
	_press(KEY_F, false)


func _press(keycode: Key, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.shift_pressed = shift
	ev.pressed = true
	_main.get_viewport().push_input(ev)


## A formed ten-model regiment built by the real manager (frontage 5), its tray selected.
func _selected_ten_model_regiment() -> RegimentTray:
	var gu := GameUnit.new()
	gu.unit_id = "e2e_frontage_unit"
	gu.unit_properties = {"player_id": 1, "name": "FrontageTester", "quality": 4, "defense": 4,
		"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true}
	for i in range(10):
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = gu
		var n := Node3D.new()
		_main.add_child(n)
		m.node = n
		gu.models.append(m)
	var regiment = _main.opr_army_manager.restore_regiment(gu, 5, Vector3.ZERO, 0.0)
	assert_that(regiment).is_not_null()
	var tray := regiment.tray as RegimentTray
	_main.object_manager.select_objects([tray])
	return tray


## Maintainer 23.09.: the frontage cycle moved from Shift+F to B (Shift+F clears the fan now).
func test_b_cycles_the_selected_regiments_frontage_and_shift_f_does_not(timeout := 120000) -> void:
	var tray := _selected_ten_model_regiment()
	await _runner.simulate_frames(1)
	assert_int(tray.frontage).is_equal(5)
	_press(KEY_F, true)
	await _runner.simulate_frames(2)
	assert_int(tray.frontage).override_failure_message("Shift+F still reforms the regiment").is_equal(5)
	_press(KEY_B, false)
	await _runner.simulate_frames(2)
	assert_int(tray.frontage).override_failure_message("B did not cycle the frontage").is_equal(4)


func test_f_with_empty_selection_toggles_all_regiment_arcs(timeout := 120000) -> void:
	var tray := _tray_via_real_manager()
	_main.object_manager.deselect_all()
	await _runner.simulate_frames(1)
	assert_bool(tray.is_arc_visible()).is_false()
	_press_f()
	await _runner.simulate_frames(2)
	# The fallback fired: the unselected tray's arcs are ON — the old toggle-ALL behavior.
	assert_bool(tray.is_arc_visible()).is_true()
	_press_f()
	await _runner.simulate_frames(2)
	assert_bool(tray.is_arc_visible()).is_false()   # and it TOGGLES, not just shows
