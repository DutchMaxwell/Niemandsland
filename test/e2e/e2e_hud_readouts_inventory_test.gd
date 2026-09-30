extends GdUnitTestSuite
## E2E — rows 9, 10 and 11 of the UI inventory (uiprompts step 6b): the multiplayer chat + roster panel,
## the two HUD readouts (the FPS line, the ruler / drag distance) and the contextual control-hints line.
## Pins TODAY's function set before the restyle, each piece raised by the function that raises it in play
## and found by its words: the chat shows its title, a roster row per player ("(you)") and per AI seat
## ("P2: NACHTMAHR"), a line per message with the sender in their player colour, a focusable input that
## sends on Enter, keeps the focus and gives it back on Esc, and it forgets the log when it hides; the FPS
## line reads the frame rate, the object count and the zoom in a colour by frame rate; the distance
## readout shows inches, the capped "used / max — reason" in amber and red, and clears after the drag or
## measurement; the hint line names the hotkeys for the hovered kind after a short dwell, bottom-centre,
## never takes the mouse and hides at once.
## test_the_inventory_check_names_a_removed_control proves the control check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const PLACEHOLDER := "Enter: chat · Esc: back to game"

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

func _chat() -> PanelContainer:
	return _main._chat_panel


func _labels(root: Node) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "Label", true, false):
		if (n as Label).is_visible_in_tree() and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _label(root: Node, fragment: String) -> Label:
	for l: Label in _labels(root):
		if l.text.contains(fragment):
			return l
	return null


func _chat_field() -> LineEdit:
	return _main._chat_input


## Today's chat controls it no longer shows; empty = all there.
func _missing() -> Array:
	var out: Array = []
	if _label(_chat(), "CHAT") == null:
		out.append("title: CHAT")
	if _label(_chat(), " (you)") == null:
		out.append("roster: (you)")
	if _chat_field() == null or not _chat_field().is_visible_in_tree() or _chat_field().placeholder_text != PLACEHOLDER:
		out.append("input: %s" % PLACEHOLDER)
	return out


func _click(c: Control) -> void:
	var vp := _main.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	var under := vp.gui_get_hovered_control()
	assert_bool(under == c or (under != null and c.is_ancestor_of(under))).override_failure_message(
		"'%s' is covered at %s by %s" % [c.name, at, under.get_path() if under != null else "nothing"]).is_true()
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


## Hue band of a colour: "green", "amber" (yellow / orange) or "red".
func _band(c: Color) -> String:
	if c.h >= 0.25 and c.h <= 0.5:
		return "green"
	if c.h >= 0.06 and c.h < 0.25:
		return "amber"
	return "red"


func _hints() -> ControlHintsController:
	return _main.get_node("ControlHintsController") as ControlHintsController


func _hint_panel() -> Control:
	return _hints().find_child("ControlHints", true, false) as Control


# === row 9: chat + roster =====================================================================

func test_the_chat_shows_its_roster_lines_and_input(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	_main._set_chat_visible(true)
	await _runner.simulate_frames(3)
	assert_bool(_chat().is_visible_in_tree()).is_true()
	assert_array(_missing()).override_failure_message("today's chat controls missing: %s" % [_missing()]).is_empty()
	assert_object(_label(_chat(), "P2: NACHTMAHR")).override_failure_message("no roster row for the AI seat").is_not_null()
	var me: int = _main.network_manager.get_my_peer_id()
	_main._add_chat_entry(me, "good game")
	await _runner.simulate_frames(3)
	var name_lbl := _label(_chat(), "%s:" % _main._peer_display_name(me))
	assert_object(name_lbl).is_not_null()
	assert_object(_label(_chat(), "good game")).is_not_null()
	assert_object(name_lbl.get_theme_color(&"font_color")).is_equal(_main._get_player_color(me))


func test_the_input_sends_keeps_focus_and_gives_it_back_on_esc(timeout := 120000) -> void:
	_main._set_chat_visible(true)
	await _runner.simulate_frames(3)
	await _click(_chat_field())
	assert_bool(_chat_field().has_focus()).override_failure_message("a click does not focus the chat input").is_true()
	_chat_field().text = "hello table"
	_chat_field().text_submitted.emit(_chat_field().text)
	await _runner.simulate_frames(3)
	assert_str(_chat_field().text).is_empty()
	assert_bool(_chat_field().has_focus()).override_failure_message("the input lost the focus after sending").is_true()
	assert_object(_label(_chat(), "hello table")).is_not_null()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	_main.get_viewport().push_input(esc)
	await _runner.simulate_frames(2)
	assert_bool(_chat_field().has_focus()).override_failure_message("Esc did not give the focus back to the game").is_false()
	_main._set_chat_visible(false)
	await _runner.simulate_frames(2)
	assert_object(_label(_main._chat_log_vbox, "hello table")).override_failure_message("hiding kept the log").is_null()


# === row 10: the readouts =====================================================================

func test_the_fps_line_reads_rate_objects_and_zoom_in_a_rate_colour(timeout := 120000) -> void:
	await _runner.simulate_frames(10)
	var fps_line: Label = _main.performance_label
	assert_bool(fps_line.is_visible_in_tree()).is_true()
	assert_str(fps_line.text).starts_with("FPS: ")
	assert_str(fps_line.text).contains("| Objects: ")
	assert_str(fps_line.text).contains("| Zoom: ")
	var fps := int(fps_line.text.trim_prefix("FPS: ").get_slice(" ", 0))
	var want := "green" if fps >= 55 else ("amber" if fps >= 30 else "red")
	assert_str(_band(fps_line.get_theme_color(&"font_color"))).override_failure_message("%d fps drawn in %s" % [
		fps, fps_line.get_theme_color(&"font_color")]).is_equal(want)
	assert_float(fps_line.get_global_rect().position.y).is_less(60.0)


func test_the_distance_readout_shows_inches_the_cap_and_clears(timeout := 120000) -> void:
	var label: Label = _main.distance_label
	_main._on_distance_changed(30.4, Vector3.ZERO, Vector3(0.772, 0, 0))
	await _runner.simulate_frames(2)
	assert_str(label.text).is_equal("30.4\"")
	assert_bool(label.is_visible_in_tree()).is_true()
	_main._on_movement_capped(4.0, 6.0, false)
	assert_str(label.text).is_equal("4.0/6.0\"")
	assert_str(_band(label.get_theme_color(&"font_color"))).is_equal("amber")
	_main._on_movement_capped(6.0, 6.0, true, "Fatigued")
	assert_str(label.text).is_equal("6.0/6.0\" — Fatigued")
	assert_str(_band(label.get_theme_color(&"font_color"))).is_equal("red")
	var dry: Color = label.get_theme_color(&"font_color")
	_main._on_drag_ended()
	assert_object(label.get_theme_color(&"font_color")).override_failure_message("the cap colour outlived the drag") \
		.is_not_equal(dry)
	await get_tree().create_timer(1.6).timeout
	assert_str(label.text).is_empty()
	_main._on_measurement_finished(12.0)
	assert_str(label.text).is_equal("12.0\"")
	await get_tree().create_timer(2.8).timeout
	assert_str(label.text).is_empty()


# === row 11: the hint line ====================================================================

func test_the_hint_line_names_the_keys_of_the_hovered_kind(timeout := 120000) -> void:
	var u := E2EBoot.make_unit(_main, 1, "Guards", [Vector3.ZERO])
	var node := (u.models[0] as ModelInstance).node
	node.set_meta("game_unit", u)
	_hints().on_hover_changed(node)
	assert_bool(_hint_panel().visible).override_failure_message("the hint showed without the dwell").is_false()
	await get_tree().create_timer(0.7).timeout
	var panel := _hint_panel()
	assert_bool(panel.is_visible_in_tree()).is_true()
	assert_object(_label(panel, ControlHintsController.HINTS["unit"])).is_not_null()
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size
	assert_float(panel.get_global_rect().get_center().x).is_equal_approx(vp.x * 0.5, 2.0)
	assert_float(panel.get_global_rect().end.y).is_greater(vp.y - 60.0)
	for n: Node in [panel] + panel.find_children("*", "Control", true, false):
		assert_int((n as Control).mouse_filter).override_failure_message("%s takes the mouse" % n.name) \
			.is_equal(Control.MOUSE_FILTER_IGNORE)
	u.unit_properties["regiment_mode"] = true
	_hints().on_hover_changed(node)
	await get_tree().create_timer(0.7).timeout
	assert_object(_label(panel, ControlHintsController.HINTS["regiment"])).is_not_null()
	_hints().on_hover_changed(null)
	assert_bool(panel.visible).override_failure_message("the hint did not hide at once").is_false()


# === the check itself =========================================================================

func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	_main._set_chat_visible(true)
	await _runner.simulate_frames(3)
	assert_array(_missing()).is_empty()
	_chat_field().hide()
	assert_array(_missing()).contains_exactly(["input: %s" % PLACEHOLDER])
