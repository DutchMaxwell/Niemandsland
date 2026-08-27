extends GdUnitTestSuite
## NML-1083 — F shows the selected unit's sight+range fan again.
##
## The binding lives in object_manager.gd (_unhandled_input, "F: sight+range fan for the selected
## unit"), but main.gd's regiment-arc handler sits in _unhandled_key_input — which Godot dispatches
## BEFORE the whole _unhandled_input group. It called set_input_as_handled() unconditionally, so the
## fan never saw the key: F was dead for every loose (Grimdark Future) unit on the table.
##
## This suite pushes a REAL key event through the real viewport of the real main.tscn, so it measures
## the dispatch ORDER, not a helper's return value — the only way this class of bug shows up at all.

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
	_main._solo_batch = false   # the fan is skipped headless-batch (see _solo_show_fan_for_unit)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One press of F through the viewport — the same route a real keystroke takes.
func _press_f() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	_main.get_viewport().push_input(ev)


## A selectable two-model unit with one 24" weapon, selected in the ObjectManager.
func _selected_unit_with_a_gun() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Fanners", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 1
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	var nodes: Array = []
	for m in u.models:
		var n := (m as ModelInstance).node
		n.add_to_group("miniature")
		n.add_to_group("selectable")
		n.set_meta("model_instance", m)   # what the F callable reads to find the unit
		nodes.append(n)
	_main.object_manager.select_objects(nodes)
	assert_int(_main.object_manager.get_selected_objects().size()).is_equal(2)
	return u


func test_f_toggles_the_sight_and_range_fan_of_the_selected_unit() -> void:
	var u := _selected_unit_with_a_gun()
	assert_object(_main._sight_fan_unit).is_null()
	_press_f()
	await _runner.simulate_frames(2)
	# RED before the fix: main's arc handler ate the key, so this stays null.
	assert_object(_main._sight_fan_unit) \
		.override_failure_message("F did not reach the sight+range fan — main.gd swallowed the key") \
		.is_equal(u)
	# Same key again clears it (the fan is a toggle).
	_press_f()
	await _runner.simulate_frames(2)
	assert_object(_main._sight_fan_unit).is_null()


## NML-1033 must survive: with NOTHING selected, F still toggles every regiment's arc wedges — main
## keeps the key in that case, so the two bindings cannot fight over it.
func test_f_with_an_empty_selection_still_toggles_all_regiment_arcs() -> void:
	_main.object_manager.select_objects([])
	var before: bool = _main.opr_army_manager._regiment_arcs_visible
	_press_f()
	await _runner.simulate_frames(2)
	assert_bool(_main.opr_army_manager._regiment_arcs_visible).is_equal(not before)
	assert_object(_main._sight_fan_unit).is_null()
