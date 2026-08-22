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
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	_main.get_viewport().push_input(ev)


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
