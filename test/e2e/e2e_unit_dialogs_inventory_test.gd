extends GdUnitTestSuite
## E2E — the unit dialogs, rows 16, 17 and 19 of the UI inventory (uiprompts step 7a): Wounds, Caster points and
## Model info (row 19: the lead decided 30.09. to restyle it and keep today's function — name + node type).
## Each dialog is opened the way the radial menu opens it (the controller's action pipe), then every control
## of TODAY's dialog is found and clicked for real: − / + step within the bounds (disabled at them), HEAL
## FULL / KILL / RESET do what they do and every change is emitted for the network sync, the spell list
## names each spell with its cost and effect, CLOSE and Esc close, − / + keys step, the dim backdrop keeps a
## click beside the panel off the table. The − / + buttons are found by their node names (their glyph is
## the kind of thing a restyle swaps); every word is checked as the player reads it.
## test_the_inventory_check_names_a_removed_control proves the control check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _spy: Node = null


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_spy = null
	_main = null
	_runner = null


# === helpers ==================================================================================

func _rmc() -> RadialMenuController:
	return _main.radial_menu_controller


## A lone Tough(3) caster hero (orcs, AoF) with one session spell on its army.
func _hero() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Warboss", [Vector3.ZERO])
	u.unit_properties["special_rules"] = ["Caster(1)", "Tough(3)"]
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "orcs"
	_main.opr_army_manager.game_units[u.unit_id] = u
	var m := u.models[0] as ModelInstance
	m.node.set_meta("model_instance", m)
	m.wounds_max = 3
	m.wounds_current = 3
	u.casts_per_round = 1
	u.casts_current = 2
	_main.opr_army_manager._session_spells[1] = [{"name": "Bolt", "threshold": 1, "effect": "Deal 2 hits."}]
	return u


func _controls(d: Node, type: String) -> Array:
	var out: Array = []
	for n: Node in d.find_children("*", type, true, false):
		if (n as Control).is_visible_in_tree() and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _button(d: Node, text: String) -> Button:
	for b: Button in _controls(d, "Button"):
		if b.text == text or b.name == text:
			return b
	return null


## Everything the dialog says (plain labels and the spell list's parsed text).
func _text(d: Node) -> String:
	var t := ""
	for l: Label in _controls(d, "Label"):
		t += l.text + "\n"
	for r: RichTextLabel in _controls(d, "RichTextLabel"):
		t += r.get_parsed_text() + "\n"
	return t


## Today's controls the dialog no longer shows; empty = all there.
func _missing(d: Node, buttons: Array) -> Array:
	var out: Array = []
	for t: Variant in buttons:
		var b := _button(d, str(t))
		if b == null:
			out.append("button: %s" % t)
	return out


func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing")
		return
	var vp := _main.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	var under := vp.gui_get_hovered_control()
	assert_bool(under == c or (under != null and c.is_ancestor_of(under))).override_failure_message(
		"'%s' is covered at %s by %s" % [c.name, at, under.get_path() if under != null else "nothing"]).is_true()
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


func _key(code: Key) -> void:
	var vp := _main.get_viewport()
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		vp.push_input(ev)
	await _runner.simulate_frames(2)


## Counts left presses that reach the table's unhandled stage (added last under /root, consumes nothing).
func _arm_spy() -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar presses := 0\nfunc _unhandled_input(e: InputEvent) -> void:\n" \
		+ "\tif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:\n\t\tpresses += 1\n"
	s.reload()
	_spy = Node.new()
	_spy.set_script(s)
	get_tree().root.add_child(_spy)
	return _spy


## A real click beside the dialog's panel: it must neither close the dialog nor reach the table.
func _click_beside(d: Control) -> void:
	var panel := d.find_child("Panel", true, false) as Control
	var spy := _arm_spy()
	var vp := _main.get_viewport()
	var at := panel.get_global_rect().position - Vector2(40, 40)
	E2EBoot.motion_canvas(vp, at)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)
	assert_bool(d.visible).override_failure_message("a click beside the panel closed the dialog").is_true()
	assert_int(spy.get("presses")).override_failure_message("a click beside the panel reached the table").is_equal(0)


# === row 16: Wounds ===========================================================================

func test_wounds_step_heal_kill_and_close(timeout := 120000) -> void:
	var u := _hero()
	var m := u.models[0] as ModelInstance
	var sent: Array = []
	_rmc().wounds_dialog.wounds_changed.connect(func(_mi: ModelInstance, w: int) -> void: sent.append(w))
	_rmc()._on_action_selected("wounds", {"model_instance": m, "game_unit": u})
	await _runner.simulate_frames(3)
	var d: Control = _rmc().wounds_dialog
	assert_bool(d.visible).is_true()
	assert_array(_missing(d, ["MinusButton", "PlusButton", "HEAL FULL", "KILL", "CLOSE"])).override_failure_message(
		"today's wounds controls missing: %s" % [_missing(d, ["MinusButton", "PlusButton", "HEAL FULL", "KILL", "CLOSE"])]) \
		.is_empty()
	assert_str(_text(d).to_upper()).contains("WOUNDS")
	assert_str(_text(d)).contains("Warboss - %s" % m.get_display_name())
	assert_str(_text(d)).contains("3 / 3")
	assert_bool(_button(d, "PlusButton").disabled).is_true()
	await _click(_button(d, "MinusButton"))
	assert_str(_text(d)).contains("2 / 3")
	await _click(_button(d, "HEAL FULL"))
	assert_int(m.wounds_current).is_equal(3)
	await _click(_button(d, "KILL"))
	assert_bool(m.is_alive).is_false()
	assert_str(_text(d)).contains("0 / 3")
	assert_bool(_button(d, "MinusButton").disabled).is_true()
	await _click(_button(d, "PlusButton"))
	assert_bool(m.is_alive).is_true()
	await _key(KEY_EQUAL)
	assert_int(m.wounds_current).is_equal(2)
	await _key(KEY_MINUS)
	assert_int(m.wounds_current).is_equal(1)
	assert_array(sent).is_equal([2, 3, 0, 1, 2, 1])
	await _click_beside(d)
	await _key(KEY_ESCAPE)
	assert_bool(d.visible).override_failure_message("Esc did not close the dialog").is_false()
	_rmc()._on_action_selected("wounds", {"model_instance": m, "game_unit": u})
	await _runner.simulate_frames(3)
	await _click(_button(d, "CLOSE"))
	assert_bool(d.visible).is_false()


# === row 17: Caster points ====================================================================

func test_caster_points_step_reset_list_spells_and_close(timeout := 120000) -> void:
	var u := _hero()
	var sent: Array = []
	_rmc().casts_dialog.casts_changed.connect(func(_gu: GameUnit, c: int) -> void: sent.append(c))
	_rmc()._on_action_selected("casts", {"game_unit": u})
	await _runner.simulate_frames(3)
	var d: Control = _rmc().casts_dialog
	assert_bool(d.visible).is_true()
	assert_array(_missing(d, ["MinusButton", "PlusButton", "RESET TO PER-ROUND", "CLOSE"])).override_failure_message(
		"today's casts controls missing: %s" % [_missing(d, ["MinusButton", "PlusButton", "RESET TO PER-ROUND", "CLOSE"])]) \
		.is_empty()
	assert_str(_text(d)).contains("WARBOSS - CASTER POINTS")
	assert_str(_text(d)).contains("2 / %d" % GameUnit.CASTER_POINTS_CAP)
	assert_str(_text(d)).contains("+1 PER ROUND")
	assert_str(_text(d)).contains("SPELLS")
	assert_str(_text(d)).contains("Bolt (1)")
	assert_str(_text(d)).contains("Deal 2 hits.")
	await _click(_button(d, "PlusButton"))
	assert_int(u.casts_current).is_equal(3)
	await _click(_button(d, "MinusButton"))
	await _click(_button(d, "MinusButton"))
	await _click(_button(d, "MinusButton"))
	assert_int(u.casts_current).is_equal(0)
	assert_bool(_button(d, "MinusButton").disabled).is_true()
	await _click(_button(d, "RESET TO PER-ROUND"))
	assert_int(u.casts_current).is_equal(1)
	await _key(KEY_EQUAL)
	assert_int(u.casts_current).is_equal(2)
	assert_array(sent).is_equal([3, 2, 1, 0, 1, 2])
	await _click_beside(d)
	await _click(_button(d, "CLOSE"))
	assert_bool(d.visible).is_false()
	_rmc()._on_action_selected("casts", {"game_unit": u})
	await _runner.simulate_frames(3)
	await _key(KEY_ESCAPE)
	assert_bool(d.visible).override_failure_message("Esc did not close the dialog").is_false()


# === row 19: Model info (generic object) ======================================================

func test_model_info_names_a_generic_object_and_closes(timeout := 120000) -> void:
	var obj := Node3D.new()
	obj.name = "RuinedTower"
	_main.add_child(obj)
	_rmc()._on_action_selected("info", {"object": obj})
	await _runner.simulate_frames(3)
	var d: Control = _rmc().model_info_popup
	assert_bool(d.visible).is_true()
	assert_array(_missing(d, ["CLOSE"])).is_empty()
	assert_str(_text(d).to_upper()).contains("MODEL INFO")
	assert_str(_text(d)).contains("RuinedTower")
	assert_str(_text(d)).contains("Type: Node3D")
	await _click_beside(d)
	await _click(_button(d, "CLOSE"))
	assert_bool(d.visible).is_false()
	_rmc()._on_action_selected("info", {"object": obj})
	await _runner.simulate_frames(3)
	await _key(KEY_ESCAPE)
	assert_bool(d.visible).override_failure_message("Esc did not close the popup").is_false()


# === the check itself =========================================================================

func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	var u := _hero()
	_rmc()._on_action_selected("wounds", {"model_instance": u.models[0], "game_unit": u})
	await _runner.simulate_frames(3)
	var d: Control = _rmc().wounds_dialog
	assert_array(_missing(d, ["HEAL FULL", "KILL"])).is_empty()
	var kill := _button(d, "KILL")
	if kill == null:
		fail("no KILL button to remove")
		return
	kill.hide()
	assert_array(_missing(d, ["HEAL FULL", "KILL"])).contains_exactly(["button: KILL"])
