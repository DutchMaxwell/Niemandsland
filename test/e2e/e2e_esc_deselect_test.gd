extends GdUnitTestSuite
## Maintainer test 7, 26.10.2026: Esc with something selected must DESELECT first; the ☰ game menu
## opens only on the NEXT Esc. The bug was that main's Esc fallback (_unhandled_input) never looked at
## the selection: it called _on_hamburger_pressed() straight away, so a selection was kept and the menu
## opened instead. Real key events go through the real viewport (like e2e_esc_menu_test.gd).

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A key down and up, pushed through the table's viewport the way the engine delivers it.
func _key(code: Key) -> void:
	var vp := _main.get_viewport()
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		vp.push_input(ev)
	await _runner.simulate_frames(2)


## The menu is open once its column shows (the fade-in starts at once; the fade-out hides it after 0.15 s).
func _menu_open() -> bool:
	await get_tree().create_timer(0.3).timeout
	return (_main.left_panel_scroll as Control).visible


## A selectable two-model unit, selected in the ObjectManager (seeding like e2e_f_key_sight_fan_test.gd).
func _select_a_unit() -> void:
	var u := E2EBoot.make_unit(_main, 1, "Selectables", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	var nodes: Array = []
	for m in u.models:
		var n := (m as ModelInstance).node
		n.add_to_group("miniature")
		n.add_to_group("selectable")
		n.set_meta("model_instance", m)
		nodes.append(n)
	_main.object_manager.select_objects(nodes)
	assert_int(_main.object_manager.get_selected_objects().size()).is_greater(0)


func test_a_esc_with_a_selection_deselects_and_leaves_the_menu_shut(timeout := 120000) -> void:
	_select_a_unit()
	assert_bool(await _menu_open()).is_false()
	await _key(KEY_ESCAPE)
	# RED before the fix: the selection is kept and the menu opens instead.
	assert_array(_main.object_manager.get_selected_objects()) \
		.override_failure_message("Esc did not deselect the unit - maintainer test 7") \
		.is_empty()
	assert_bool(await _menu_open()) \
		.override_failure_message("Esc opened the game menu while a selection was live") \
		.is_false()


func test_b_a_second_esc_opens_the_menu(timeout := 120000) -> void:
	_select_a_unit()
	await _key(KEY_ESCAPE)   # deselects
	await _key(KEY_ESCAPE)   # now the menu
	assert_bool(await _menu_open()) \
		.override_failure_message("a second Esc did not open the menu") \
		.is_true()


func test_c_with_the_menu_open_esc_closes_it_and_keeps_the_selection(timeout := 120000) -> void:
	await _key(KEY_ESCAPE)   # nothing selected: opens the menu
	assert_bool(await _menu_open()).is_true()
	_select_a_unit()
	await _key(KEY_ESCAPE)   # the open menu closes first; the selection stays
	assert_bool(await _menu_open()) \
		.override_failure_message("Esc did not close the open game menu") \
		.is_false()
	assert_int(_main.object_manager.get_selected_objects().size()).is_greater(0)
