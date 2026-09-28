extends GdUnitTestSuite
## E2E — the menu scene shell + route panel, rows 43-44 of the UI inventory (uimenus Step 11a: the main
## menu and its "Play online / Learn to play / Help & feedback" route panel). Every control is found by
## the words the player reads and reached with a REAL click.
##
## The probe below only replaces _transition_to_game() with a flag: several of today's real clicks reach
## it (Continue, Prepare a new table -> Create table, and "Learn the controls" when no lesson is done yet
## sends the player straight into the tutorial) and a real scene swap mid-suite would take the rest of
## the run down with it. Report a problem is deliberately NOT clicked — _on_report_problem_pressed calls
## OS.shell_open() on the real Desktop folder, which would pop a real file manager window on the shared
## machine; it is checked by wiring only, as the click ownership suites already do for network calls.
##
## test_inventory_check_names_a_removed_control proves the presence check can fail.
## test_menu_view_defines_no_private_palette is added WITH the restyle: RED on main (the file still
## defines its own INK/MUTED/GOLD/CYAN), GREEN once row 43-44's palette is re-plumbed to HouseStyle.

const MAIN_ACTIONS := ["Prepare a new table", "Play online", "Load game", "Learn to play"]
const FOOTER := ["Help & feedback", "Credits & licenses", "Quit"]
const ONLINE_ROUTE := ["Create a room", "Join with a code", "Public tables"]
const LEARN_ROUTE := ["Learn the controls", "Trial by Fire · In development"]
const HELP_ROUTE := ["Learn the controls", "Report a problem"]

class MenuTransitionProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _transition_to_game() -> void:
		entered_game = true

var _menu: Control
var _view: Control


func before_test() -> void:
	_menu = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	_menu.set_script(MenuTransitionProbe)
	add_child(_menu)
	await _frames(2)
	_view = _menu.view


func after_test() -> void:
	_menu = null
	_view = null


# === helpers ===================================================================================

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## A real click at the centre of `c`, through the full input pipeline (see e2e_boot.gd's click_canvas).
func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing")
		return
	var vp := c.get_viewport()
	var at := c.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = vp.get_screen_transform() * at
	motion.global_position = motion.position
	vp.push_input(motion)
	var under := vp.gui_get_hovered_control()
	assert_bool(under == c or (under != null and c.is_ancestor_of(under))).override_failure_message(
		"%s is covered at %s by %s" % [c.name, at, under.get_path() if under != null else "nothing"]).is_true()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = vp.get_screen_transform() * at
		ev.global_position = ev.position
		vp.push_input(ev)
	await _frames(3)


func _button(text: String) -> Button:
	for n: Node in _menu.find_children("*", "Button", true, false):
		var b := n as Button
		if b == null or b.is_queued_for_deletion() or not b.is_visible_in_tree():
			continue
		if b.text == text:
			return b
	return null


func _label(text: String) -> Label:
	for n: Node in _menu.find_children("*", "Label", true, false):
		var l := n as Label
		if l == null or l.is_queued_for_deletion() or not l.is_visible_in_tree():
			continue
		if l.text == text:
			return l
	return null


func _missing_controls() -> Array:
	var missing: Array = []
	for t: String in MAIN_ACTIONS + FOOTER:
		if _button(t) == null:
			missing.append("button: %s" % t)
	for t: String in ["TABLETOP FOR ONEPAGERULES", "NIEMANDS", "LAND"]:
		if _label(t) == null:
			missing.append("label: %s" % t)
	return missing


func _dialog_titled(title: String) -> Window:
	for n: Node in _menu.get_children():
		if n is Window and (n as Window).title == title:
			return n as Window
	return null


# === tests ======================================================================================

func test_every_control_of_rows_43_44_is_in_the_menu() -> void:
	assert_array(_missing_controls()).override_failure_message(
		"today's menu controls missing: %s" % str(_missing_controls())).is_empty()
	assert_str(_button("⚙  Settings").text).is_equal("⚙  Settings")


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing_controls()).is_empty()
	var load_btn := _button("Load game")
	var parent := load_btn.get_parent()
	var at := load_btn.get_index()
	parent.remove_child(load_btn)
	var missing := _missing_controls()
	parent.add_child(load_btn)
	parent.move_child(load_btn, at)
	assert_array(missing).contains_exactly(["button: Load game"])


func test_welcome_card_matches_todays_save_lookup() -> void:
	var has_save: bool = _view.resume.visible
	assert_str(_view.welcome_kicker.text).is_equal("WELCOME BACK" if has_save else "WELCOME TO NIEMANDSLAND")
	assert_str(_view.welcome.text).is_equal("Back to the table." if has_save else "Your first table awaits.")
	assert_bool(_button("Continue").is_visible_in_tree()).is_equal(has_save)


func test_settings_button_opens_the_settings_window() -> void:
	await _click(_button("⚙  Settings"))
	assert_object(_menu._settings).is_not_null()
	assert_bool(_menu._settings.visible).is_true()


func test_prepare_a_new_table_opens_the_table_chooser() -> void:
	await _click(_button("Prepare a new table"))
	assert_object(_menu._table_setup).is_not_null()
	assert_bool(_view.visible).is_false()
	_menu._table_setup._on_close()
	assert_bool(_view.visible).is_true()


func test_load_game_opens_the_real_nml_file_dialog() -> void:
	await _click(_button("Load game"))
	assert_object(_menu._load_dialog).is_not_null()
	assert_bool(_menu._load_dialog.visible).is_true()
	assert_int(_menu._load_dialog.file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	assert_str(str(_menu._load_dialog.filters)).contains("nml")


func test_online_route_lists_its_three_actions_and_closes_on_a_pick() -> void:
	await _click(_button("Play online"))
	assert_bool(_view.route_panel.visible).is_true()
	assert_str(_view.route_title.text).is_equal("Meet around the table.")
	for t: String in ONLINE_ROUTE:
		assert_object(_button(t)).override_failure_message("%s is missing from the online route" % t).is_not_null()
	await _click(_button("Public tables"))
	assert_bool(_view.route_panel.visible).override_failure_message("the route did not close on a pick").is_false()
	assert_object(_menu._browse_popup).is_not_null()


func test_learn_route_lists_its_two_actions_and_back_returns_focus() -> void:
	var learn_btn := _button("Learn to play")
	await _click(learn_btn)
	assert_bool(_view.route_panel.visible).is_true()
	assert_str(_view.route_title.text).is_equal("Find your starting point.")
	for t: String in LEARN_ROUTE:
		assert_object(_button(t)).override_failure_message("%s is missing from the learn route" % t).is_not_null()
	await _click(_button("←  Back"))
	assert_bool(_view.route_panel.visible).is_false()
	assert_object(_view.get_viewport().gui_get_focus_owner()).is_same(learn_btn)


func test_help_route_lists_its_two_actions_report_problem_is_wired_not_clicked() -> void:
	await _click(_button("Help & feedback"))
	assert_bool(_view.route_panel.visible).is_true()
	assert_str(_view.route_title.text).is_equal("Help & feedback.")
	for t: String in HELP_ROUTE:
		assert_object(_button(t)).override_failure_message("%s is missing from the help route" % t).is_not_null()
	assert_bool(_menu.report_problem_btn.pressed.is_connected(_menu._on_report_problem_pressed)).is_true()


func test_learn_the_controls_reaches_todays_tutorial_entry() -> void:
	await _click(_button("Learn to play"))
	await _click(_button("Learn the controls"))
	# Today's branch depends on real on-disk tutorial progress: some done -> the chapter picker;
	# none done -> straight into the tutorial (caught by the probe instead of a real scene swap).
	var picker := _dialog_titled("Tutorial")
	assert_bool((picker != null and picker.visible) or _menu.entered_game).override_failure_message(
		"neither the chapter picker opened nor did the tutorial launch").is_true()


func test_trial_by_fire_opens_todays_chapter_list() -> void:
	await _click(_button("Learn to play"))
	await _click(_button("Trial by Fire · In development"))
	var dialog := _dialog_titled("TRIAL BY FIRE")
	assert_object(dialog).is_not_null()
	assert_bool(dialog.visible).is_true()


func test_credits_dialog_keeps_the_legal_notice_verbatim() -> void:
	await _click(_button("Credits & licenses"))
	var dialog := _dialog_titled("Credits & licenses")
	assert_object(dialog).is_not_null()
	var found := false
	for n: Node in dialog.find_children("*", "Label", true, false):
		if (n as Label).text.contains("not affiliated with, endorsed by, or sponsored by OnePageRules"):
			found = true
	assert_bool(found).override_failure_message("the non-affiliation notice changed or is gone").is_true()


func test_quit_asks_first_with_back_focused_and_never_quits() -> void:
	await _click(_button("Quit"))
	var dialog := _dialog_titled("Quit Niemandsland") as ConfirmationDialog
	assert_object(dialog).is_not_null()
	assert_str(dialog.dialog_text).is_equal("Are you sure you want to quit Niemandsland?")
	assert_object(dialog.get_viewport().gui_get_focus_owner()).is_same(dialog.get_cancel_button())
	# A ConfirmationDialog is its own Window: a coordinate click cannot land on it reliably in
	# headless mode (as e2e_hero_morale_prompt_test.gd works around too). Its own "canceled" signal
	# is exactly what pressing Back fires, so trigger the effect there instead of the coordinates.
	dialog.canceled.emit()
	await _frames(2)
	assert_bool(is_instance_valid(_menu._exit_confirm)).is_false()


func test_menu_view_defines_no_private_palette() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu_view.gd")
	for name in ["const INK :=", "const MUTED :=", "const GOLD :=", "const CYAN :="]:
		assert_str(src).override_failure_message(
			"startup_menu_view.gd still defines its own %s instead of using HouseStyle" % name).not_contains(name)
	assert_str(src).contains("HouseStyle.INK")
