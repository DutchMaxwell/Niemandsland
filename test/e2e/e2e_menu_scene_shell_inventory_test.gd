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

const MAIN_ACTIONS := ["Prepare a new table", "Play online", "Load game", "Learn to play", "Settings"]
const FOOTER := ["Help & feedback", "Credits & licenses", "Quit"]
const ONLINE_ROUTE := ["Create a room", "Join with a code", "Public tables"]
const LEARN_ROUTE := ["Learn the controls", "Trial by Fire · In development"]
const HELP_ROUTE := ["Learn the controls", "Report a problem"]

class MenuTransitionProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _transition_to_game() -> void:
		entered_game = true
	# The room browser opens with a relay request; a test must not reach the production relay.
	func _refresh_browse_list() -> void:
		_set_browse_status("Loading rooms…")

## The runtime-only flags the menu arms for main.gd (never persisted). On a machine without tutorial progress the
## "Learn the controls" click launches the tutorial and arms tutorial_mode; left armed, the next suite that boots
## main.tscn loads the tutorial board and crashes mid-boot (CI shard 3, 05.10.). Saved before, restored after.
const MENU_FLAGS := ["niemandsland/tutorial_mode", "niemandsland/tutorial_lesson", "niemandsland/pending_load_path",
	"niemandsland/pending_table_setup", "niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/open_game_school", "niemandsland/pending_internet_lobby",
	"niemandsland/internet_is_host", "niemandsland/internet_relay_url", "niemandsland/internet_room_code",
	"niemandsland/player_name"]

var _menu: Control
var _view: Control
var _saved_flags := {}


func before_test() -> void:
	for flag: String in MENU_FLAGS:
		_saved_flags[flag] = ProjectSettings.get_setting(flag) if ProjectSettings.has_setting(flag) else null
	_menu = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	_menu.set_script(MenuTransitionProbe)
	add_child(_menu)
	await _frames(2)
	_view = _menu.view


func after_test() -> void:
	for flag: String in _saved_flags:
		ProjectSettings.set_setting(flag, _saved_flags[flag])   # null erases a flag that was not there before
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
	assert_str(_button("Settings").text).is_equal("Settings")


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
	assert_bool(_view.buttons.ContinueBtn.is_visible_in_tree()).is_equal(has_save)


func test_settings_button_opens_the_settings_window() -> void:
	await _click(_button("Settings"))
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
	await _click(_button(HouseStyle.GLYPH_BACK + "  Back"))
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
	var card: PromptCard = _menu.get("_exit_card")
	assert_object(card).override_failure_message("Quit opens no prompt card").is_not_null()
	if card == null:
		return
	assert_str(card.title).is_equal("Quit Niemandsland")
	assert_bool(_card_has_text(card, "Are you sure you want to quit Niemandsland?")).is_true()
	assert_object(card.get_viewport().gui_get_focus_owner()).is_same(card.cancel_button)
	# The card lives in the menu's own viewport, so Back takes a real click; Quit is never pressed here.
	await _click(card.cancel_button)
	await get_tree().create_timer(0.45).timeout  # the card fades out first
	assert_bool(is_instance_valid(_menu._exit_card)).is_false()


func _card_has_text(card: PromptCard, text: String) -> bool:
	for n: Node in card.find_children("*", "Label", true, false):
		if (n as Label).text == text:
			return true
	return false


func test_menu_view_defines_no_private_palette() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu_view.gd")
	for name in ["const INK :=", "const MUTED :=", "const GOLD :=", "const CYAN :="]:
		assert_str(src).override_failure_message(
			"startup_menu_view.gd still defines its own %s instead of using HouseStyle" % name).not_contains(name)
	assert_str(src).contains("HouseStyle.INK")


## The platform guideline asks 18 px body text at 1080p; the menu's small labels were 10 px. RED on main (10),
## GREEN once no label or button of the view asks for less than 14.
func test_menu_view_text_is_at_least_14_px() -> void:
	var smallest := 1000
	for type_name: String in ["Label", "Button"]:
		for n: Node in _view.find_children("*", type_name, true, false):
			smallest = mini(smallest, (n as Control).get_theme_font_size("font_size"))
	assert_int(smallest).override_failure_message(
		"the smallest text of the menu view asks for %d px" % smallest).is_greater_equal(14)


## Inter has no U+2261, U+2699, U+2295 (they come from a fallback font, or not at all) and U+25A1 is a stand-in.
## The rows draw icons now. RED on main: the rows carry "⊕", "□", "≡" as text and Settings carries the gear.
func test_menu_view_uses_no_text_glyph_icons() -> void:
	var banned := [0x2261, 0x2699, 0x2295, 0x25A1]
	var found: Array[String] = []
	for n: Node in _view.find_children("*", "Control", true, false):
		var texts: Array[String] = []
		if n is Label or n is Button:
			texts.append(n.get("text"))
		var glyph: Variant = n.get("glyph")
		if glyph is String:
			texts.append(glyph)
		for t: String in texts:
			for code: int in banned:
				if t.contains(String.chr(code)):
					found.append("%s: U+%04X" % [n.name, code])
	assert_array(found).override_failure_message("text glyphs still in the view: %s" % str(found)).is_empty()
	for id: String in ["StartBattleBtn", "OnlineBtn", "LoadBattleBtn", "LearnBtn"]:
		assert_object(_view.buttons[id].get("row_icon")).override_failure_message("%s has no icon" % id).is_not_null()


## Settings was a 13 px link in the top right corner, the least findable control of the menu. RED on main: its
## parent is the masthead.
func test_settings_is_the_fifth_row_of_the_list_after_learn() -> void:
	var settings: Control = _view.buttons.SettingsBtn
	assert_str(String(settings.get_parent().name)).is_equal("MenuButtons")
	assert_int(settings.get_index()).is_equal(4)
	assert_object(_view.buttons.LearnBtn.get_parent().get_child(3)).is_same(_view.buttons.LearnBtn)
	var order: Array = _view.main_buttons().map(func(b: Control) -> String: return String(b.name))
	assert_int(order.find("SettingsBtn")).is_equal(order.find("LearnBtn") + 1)


const CARD_FIXTURES := "res://test/fixtures/continue_card"


## The Continue card named only the save and its date. RED on main: the lookup has no facts.
func test_latest_save_info_carries_the_facts_of_the_save() -> void:
	var info := SaveManager.latest_save_info(CARD_FIXTURES)
	assert_str(str(info.get("name", ""))).is_equal("save_with_facts")
	assert_str(str(info.get("system", ""))).is_equal("gf")
	assert_int(int(info.get("round", 0))).is_equal(3)
	assert_str(str(info.get("biome", ""))).is_equal("temperate_grassland")
	assert_array(info.get("size_feet", [])).is_equal([6.0, 4.0])


func test_save_facts_are_left_out_of_a_file_that_is_too_large_or_broken() -> void:
	var manager: GDScript = load("res://scripts/save_manager.gd")
	assert_bool(manager.has_method("save_facts")).override_failure_message("no save_facts").is_true()
	if not manager.has_method("save_facts"):
		return
	var path := CARD_FIXTURES.path_join("save_with_facts.nml")
	assert_dict(manager.call("save_facts", path, 10)).is_empty()
	var broken := "user://broken_continue_card.nml"
	FileAccess.open(broken, FileAccess.WRITE).store_string("{ not json")
	assert_dict(manager.call("save_facts", broken)).is_empty()
	DirAccess.remove_absolute(broken)


func test_continue_card_shows_two_mono_lines_with_the_facts() -> void:
	var lines: Variant = _view.get("save_facts")
	assert_bool(lines is Array).override_failure_message("the card has no fact lines").is_true()
	if lines is not Array:
		return
	_view.set_save(SaveManager.latest_save_info(CARD_FIXTURES))
	assert_str(lines[0].text).is_equal("GRIMDARK FUTURE · ROUND 3")
	assert_str(lines[1].text).is_equal("GRASSLAND · 6 x 4 FT")
	_view.set_save({"name": "plain", "modified_unix": 1727000000})
	assert_bool(lines[0].visible).is_false()
	assert_bool(lines[1].visible).is_false()
