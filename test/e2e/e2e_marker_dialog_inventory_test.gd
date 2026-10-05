extends GdUnitTestSuite
## E2E — the Tokens (marker) dialog, row 18 of the UI inventory (uiprompts step 7b). Opened the way the radial
## menu opens it (the controller's "add_marker" action, for a model and for a whole unit), then every control
## of TODAY's dialog is found and used for real: the name field, the colour dropdown, the Counter box with
## its START value and the effect field make a new token that Add puts on the target and into the shared
## library; an active counter steps with − / + and × takes a token off; a saved token applies with one click
## (its tooltip carries the effect); its edit button loads it into the form (Add becomes Save, the type is
## locked) and Save renames it everywhere; Close and Esc close; a click beside the panel stays off the table.
## The edit buttons are found by their tooltips (their glyph is not in the UI font).
## test_the_inventory_check_names_a_removed_control proves the control check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const NAME_HINT := "Token name (e.g. Havoc)..."
const EFFECT_HINT := "Effect/description (shown on hover, optional)..."

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


# === helpers ==================================================================================

func _rmc() -> RadialMenuController:
	return _main.radial_menu_controller


func _dialog() -> MarkerDialog:
	return _rmc().marker_dialog


func _squad() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Guards", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	for m in u.models:
		(m as ModelInstance).node.set_meta("model_instance", m)
	return u


func _open_for(u: GameUnit, model: ModelInstance = null) -> void:
	var ctx := {"game_unit": u}
	if model != null:
		ctx["model_instance"] = model
	_rmc()._on_action_selected("add_marker", ctx)
	await _runner.simulate_frames(3)


func _visible(type: String) -> Array:
	var out: Array = []
	for n: Node in _dialog().find_children("*", type, true, false):
		if (n as Control).is_visible_in_tree() and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _button(text: String) -> Button:
	for b: Button in _visible("Button"):
		if b.text == text and not (b is OptionButton) and not (b is CheckBox):
			return b
	return null


func _tip_button(tip: String) -> Button:
	for b: Button in _visible("Button"):
		if b.tooltip_text == tip:
			return b
	return null


func _line_edit(hint: String) -> LineEdit:
	for e: LineEdit in _visible("LineEdit"):
		if e.placeholder_text == hint:
			return e
	return null


func _labels_text() -> String:
	var t := ""
	for l: Label in _visible("Label"):
		t += l.text + "\n"
	return t


## The active row of `token`: [its label, its − / + (or nulls), its ×].
func _active_row(token: String) -> Array:
	for l: Label in _visible("Label"):
		if l.text == token or l.text.begins_with(token + ": "):
			var row := l.get_parent()
			var btns: Array = []
			for c in row.get_children():
				if c is Button:
					btns.append(c)
			return [l] + btns
	return []


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


## Today's form controls the dialog no longer shows; empty = all there.
func _missing() -> Array:
	var out: Array = []
	if _line_edit(NAME_HINT) == null:
		out.append("field: %s" % NAME_HINT)
	if _line_edit(EFFECT_HINT) == null:
		out.append("field: %s" % EFFECT_HINT)
	if _visible("OptionButton").is_empty():
		out.append("dropdown: colour")
	if _visible("CheckBox").is_empty():
		out.append("check: Counter")
	if _visible("SpinBox").is_empty():
		out.append("spin: START")
	for t: String in ["Add", "Close"]:
		if _button(t) == null:
			out.append("button: %s" % t)
	return out


# === the controls =============================================================================

## A new counter token: name, colour, Counter + START, effect → Add puts it on the model and in the library;
## − / + step it (never below 0), × takes it off.
func test_a_new_counter_token_is_added_stepped_and_removed(timeout := 120000) -> void:
	var u := _squad()
	var m := u.models[0] as ModelInstance
	await _open_for(u, m)
	assert_bool(_dialog().visible).is_true()
	assert_array(_missing()).override_failure_message("today's token controls missing: %s" % [_missing()]).is_empty()
	if not _missing().is_empty():
		return   # the check above names what is gone; the steps below need every control
	assert_str(_labels_text().to_upper()).contains("MARKERS")
	assert_str(_labels_text()).contains("Tokens: %s" % m.get_display_name())
	var colours := _visible("OptionButton")[0] as OptionButton
	assert_int(colours.item_count).is_equal(6)
	_line_edit(NAME_HINT).text = "Havoc"
	colours.select(2)
	(_visible("CheckBox")[0] as CheckBox).button_pressed = true
	(_visible("SpinBox")[0] as SpinBox).value = 2
	_line_edit(EFFECT_HINT).text = "Re-roll one die."
	await _click(_button("Add"))
	assert_bool(m.markers.has("Havoc")).is_true()
	assert_int(m.get_marker_value("Havoc")).is_equal(2)
	assert_bool(_rmc().token_library.has("Havoc")).is_true()
	assert_str(_rmc().token_library.get_effect("Havoc")).is_equal("Re-roll one die.")
	var row := _active_row("Havoc")
	assert_str((row[0] as Label).text).is_equal("Havoc: 2")
	await _click(row[2])   # +
	assert_int(m.get_marker_value("Havoc")).is_equal(3)
	row = _active_row("Havoc")
	for _i in 4:
		await _click(row[1])   # −
		row = _active_row("Havoc")
	assert_int(m.get_marker_value("Havoc")).override_failure_message("a counter went below 0").is_equal(0)
	await _click(row[3])   # ×
	assert_bool(m.markers.has("Havoc")).is_false()
	assert_array(_active_row("Havoc")).is_empty()


## A saved token applies with one click (tooltip = its effect), to every model of a unit.
func test_a_saved_token_applies_to_the_whole_unit(timeout := 120000) -> void:
	var u := _squad()
	_rmc().token_library.define("Blessed", Color.GREEN, false, "+1 to hit.")
	await _open_for(u)
	assert_str(_labels_text()).contains("Tokens: Guards")
	var apply := _button("Blessed")
	assert_object(apply).is_not_null()
	assert_str(apply.tooltip_text).is_equal("+1 to hit.")
	await _click(apply)
	for m in u.models:
		assert_bool((m as ModelInstance).markers.has("Blessed")).is_true()


## Edit loads a saved token into the form (Add becomes Save, the type is locked); Save renames it.
func test_edit_loads_a_token_and_save_renames_it(timeout := 120000) -> void:
	var u := _squad()
	var m := u.models[0] as ModelInstance
	_rmc().token_library.define("Stunned", Color.RED, false, "No moving.")
	await _open_for(u, m)
	await _click(_button("Stunned"))
	await _click(_tip_button("Edit 'Stunned' (name/color/effect) for all instances"))
	assert_str(_line_edit(NAME_HINT).text).is_equal("Stunned")
	assert_str(_line_edit(EFFECT_HINT).text).is_equal("No moving.")
	assert_bool((_visible("CheckBox")[0] as CheckBox).disabled).is_true()
	assert_object(_button("Save")).override_failure_message("Add did not become Save").is_not_null()
	_line_edit(NAME_HINT).text = "Dazed"
	await _click(_button("Save"))
	assert_bool(_rmc().token_library.has("Dazed")).is_true()
	assert_bool(_rmc().token_library.has("Stunned")).is_false()
	assert_bool(m.markers.has("Dazed")).override_failure_message("the rename missed the model").is_true()
	assert_object(_button("Add")).override_failure_message("Save did not turn back into Add").is_not_null()


## Close and Esc close; a click beside the panel neither closes nor reaches the table.
func test_close_esc_and_the_backdrop(timeout := 120000) -> void:
	var u := _squad()
	await _open_for(u)
	var panel := _dialog().find_child("Panel", true, false) as Control
	var vp := _main.get_viewport()
	var beside := panel.get_global_rect().position - Vector2(40, 40)
	E2EBoot.motion_canvas(vp, beside)
	assert_object(vp.gui_get_hovered_control()).override_failure_message("the backdrop does not own the click") \
		.is_not_null()
	E2EBoot.click_canvas(vp, beside, true)
	E2EBoot.click_canvas(vp, beside, false)
	await _runner.simulate_frames(3)
	assert_bool(_dialog().visible).is_true()
	await _click(_button("Close"))
	assert_bool(_dialog().visible).is_false()
	await _open_for(u)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	vp.push_input(esc)
	await _runner.simulate_frames(2)
	assert_bool(_dialog().visible).override_failure_message("Esc did not close the dialog").is_false()


# === the house look (restyle) =================================================================

## The dialog in the house frame: house theme, scrim, house panel, eyebrow title, section captions, Add gold,
## Close / the dropdown / the Counter line / the row buttons ghost buttons, the saved tokens in their own
## token colour (the one ink they may set), no box or size of their own, every glyph in its font.
func test_the_dialog_wears_the_house_style(timeout := 120000) -> void:
	var u := _squad()
	var m := u.models[0] as ModelInstance
	_rmc().token_library.define("Blessed", Color.GREEN, false, "+1 to hit.")
	await _open_for(u, m)
	await _click(_button("Blessed"))
	var d := _dialog()
	assert_object(d.theme).is_same(HouseStyle.theme())
	assert_object((d.find_child("Background", true, false) as ColorRect).color).is_equal(HouseStyle.SCRIM)
	assert_str(String((d.find_child("Panel", true, false) as Control).theme_type_variation)) \
		.is_equal(String(HouseStyle.PANEL_VARIANT))
	assert_int(d.find_children("*", "HudFrame", true, false).size()).override_failure_message("brackets").is_equal(0)
	var roles := {"MARKERS": HouseStyle.EYEBROW, "ACTIVE": HouseStyle.CAPTION, "NEW / EDIT TOKEN": HouseStyle.CAPTION,
		"START": HouseStyle.CAPTION, "Blessed": HouseStyle.BODY}
	for l: Label in _visible("Label"):
		if roles.has(l.text):
			assert_str(String(l.theme_type_variation)).override_failure_message("'%s' has the wrong role" % l.text) \
				.is_equal(String(roles[l.text]))
			roles.erase(l.text)
	assert_array(roles.keys()).override_failure_message("labels not found: %s" % [roles.keys()]).is_empty()
	assert_str(String(_button("Add").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	for b: Button in [_button("Close"), _visible("OptionButton")[0], _visible("CheckBox")[0], _active_row("Blessed")[1],
			_tip_button("Edit 'Blessed' (name/color/effect) for all instances")]:
		assert_str(String(b.theme_type_variation)).override_failure_message("'%s' is not a house button" % b.text) \
			.is_equal(String(HouseStyle.BUTTON))
	var own: Array = []
	var lacking: Array = []
	for n: Node in [d] + d.find_children("*", "Control", true, false):
		if n != d and not n.get_parent().get_children().has(n):
			continue
		var c := n as Control
		if c.has_theme_stylebox_override(&"panel") or c.has_theme_font_override(&"font") \
				or c.has_theme_font_size_override(&"font_size"):
			own.append(c.name)
		elif c.has_theme_color_override(&"font_color") and not (c is Button and _rmc().token_library.has(c.text)):
			own.append("%s ink" % c.name)
		if (c is Label or c is Button) and c.is_visible_in_tree():
			var text: String = c.text
			for i in text.length():
				if text[i] != " " and not c.get_theme_font(&"font").has_char(text.unicode_at(i)):
					lacking.append("U+%04X in '%s'" % [text.unicode_at(i), text])
	assert_array(own).override_failure_message("dresses itself: %s" % [own]).is_empty()
	assert_array(lacking).override_failure_message("its font lacks %s" % [lacking]).is_empty()


# === the check itself =========================================================================

func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	await _open_for(_squad())
	assert_array(_missing()).is_empty()
	var spins := _visible("SpinBox")
	if spins.is_empty():
		fail("no START spin box to remove")
		return
	(spins[0] as Control).hide()
	assert_array(_missing()).contains_exactly(["spin: START"])
