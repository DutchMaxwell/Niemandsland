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
const HELP_ROUTE := ["Learn the controls", "Report a problem"]

class MenuTransitionProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _init() -> void:
		set("online_hub_lists", false)   # the hub must not ask the production relay from a test
	func _transition_to_game() -> void:
		entered_game = true

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
	_menu.setup_lists = false   # no CDN request for NACHTMAHR's lists
	await _frames(2)
	_view = _menu.view


func after_test() -> void:
	for flag: String in _saved_flags:
		ProjectSettings.set_setting(flag, _saved_flags[flag])   # null erases a flag that was not there before
	_menu = null
	_view = null


# === helpers =====================================================================



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


## A route closes with a motion; the panel is hidden when route_closed fires (at once with Reduce Motion).
func _route_gone() -> void:
	if _view.route_panel.visible:
		await _view.route_closed


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


# === tests ========================================================================



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


## Load game opens the save list; the engine's file dialog only behind "Browse files…" (red on main: the click
## showed the file dialog at once).
func test_load_game_shows_no_file_dialog_until_browse_files_is_pressed() -> void:
	await _click(_button("Load game"))
	assert_int(_menu.find_children("*", "FileDialog", true, false).size()).is_equal(0)
	var browser: Variant = _menu.get("_save_browser")
	assert_object(browser).override_failure_message("no save list").is_not_null()
	if browser == null:
		return
	await _click(browser.browse_button)
	var dialog: FileDialog = browser.file_dialog
	assert_bool(dialog.visible).is_true()
	assert_int(dialog.file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	assert_str(str(dialog.filters)).contains("nml")
	dialog.hide()


## "Play online" opens the online hub in place of the list: no route panel, no window in the tree (red on main:
## the online route, then one of three windows).
func test_play_online_opens_a_page_and_no_window() -> void:
	var online := _button("Play online")
	await _click(online)
	assert_bool(_view.route_panel.visible).override_failure_message("a route panel opened").is_false()
	assert_bool(_view.get("page_open") is OnlineHub).override_failure_message("no online hub").is_true()
	var windows := _menu.find_children("*", "Window", true, false).filter(func(w: Window) -> bool: return w.visible)
	assert_array(windows).is_empty()
	if _view.get("page_open") is OnlineHub:
		await _click((_view.get("page_open") as OnlineHub).back)
	assert_object(_view.get_viewport().gui_get_focus_owner()).is_same(online)


## "Learn to play" opens the lesson page in place of the list, not a route panel; its way back returns the focus
## (red on main: the click opened the learn route).
func test_learn_to_play_opens_a_page_not_a_route_panel() -> void:
	var learn_btn := _button("Learn to play")
	await _click(learn_btn)
	assert_bool(_view.route_panel.visible).override_failure_message("a route panel opened").is_false()
	var page: Variant = _view.get("page_open")
	assert_bool(page is LearnPage).override_failure_message("no lesson page").is_true()
	if not page is LearnPage:
		return
	assert_bool((_view.get("_scroll") as Control).visible).is_false()
	await _click((page as LearnPage).back)
	assert_bool((_view.get("_scroll") as Control).visible).is_true()
	assert_object(_view.get_viewport().gui_get_focus_owner()).is_same(learn_btn)


func test_help_route_lists_its_two_actions_report_problem_is_wired_not_clicked() -> void:
	await _click(_button("Help & feedback"))
	assert_bool(_view.route_panel.visible).is_true()
	assert_str(_view.route_title.text).is_equal("Help & feedback.")
	for t: String in HELP_ROUTE:
		assert_object(_button(t)).override_failure_message("%s is missing from the help route" % t).is_not_null()
	assert_bool(_menu.report_problem_btn.pressed.is_connected(_menu._on_report_problem_pressed)).is_true()


func test_learn_the_controls_in_help_opens_the_lesson_page() -> void:
	await _click(_button("Help & feedback"))
	await _click(_button("Learn the controls"))
	await _route_gone()
	assert_bool(_view.get("page_open") is LearnPage).override_failure_message("no lesson page").is_true()


func test_credits_dialog_keeps_the_legal_notice_verbatim() -> void:
	await _click(_button("Credits & licenses"))
	var dialog := _dialog_titled("Credits & licenses")
	assert_object(dialog).is_not_null()
	var found := false
	for n: Node in dialog.find_children("*", "Label", true, false):
		if (n as Label).text.contains("not affiliated with, endorsed by, or sponsored by OnePageRules"):
			found = true
	assert_bool(found).override_failure_message("the non-affiliation notice changed or is gone").is_true()


## The five licence lines are a table: the name left, the licence right, 36 px rows (sheet 08; red on main: five lines
## of one text label).
func test_credits_licences_are_rows_of_a_table() -> void:
	await _click(_button("Credits & licenses"))
	var dialog := _dialog_titled("Credits & licenses")
	assert_object(dialog).is_not_null()
	var rows := dialog.find_child("LicenceRows", true, false)
	assert_object(rows).override_failure_message("no licence table").is_not_null()
	if rows == null:
		return
	var pairs: Array = []
	for row: Node in rows.get_children():
		if row is HBoxContainer:
			assert_float((row as Control).custom_minimum_size.y).is_equal(36.0)
			pairs.append([(row.get_child(0) as Label).text, (row.get_child(1) as Label).text])
	assert_array(pairs).is_equal([["Game code", "MIT License"],
		["3D miniatures & terrain", "generated project assets, CC-BY-SA 4.0"],
		["Fonts", "SIL Open Font License"], ["UI icons", "Phosphor Icons (MIT)"], ["Engine", "Godot Engine (MIT)"]])


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
	var banned := [0x2261, 0x2699, 0x2295, 0x25A1, 0x203A]
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


## Inter carries the whole weight axis: row titles stand at 500, the main action at 600, the headline at 500.
## RED on main: there is no weighted font.
func test_titles_and_the_main_action_use_inter_weights() -> void:
	var house: GDScript = load("res://scripts/hud/house_style.gd")
	assert_bool(house.has_method("font")).override_failure_message("no HouseStyle.font").is_true()
	if not house.has_method("font"):
		return
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	for weight: int in [500, 600]:
		var font: FontVariation = house.call("font", weight)
		assert_object(font).is_not_null()
		assert_int(int(font.variation_opentype.get(tag, 0))).is_equal(weight)
		assert_object(house.call("font", weight)).override_failure_message("not cached").is_same(font)
	assert_object(house.call("font", 500)).is_not_same(house.call("font", 600))
	assert_object(_view.buttons.OnlineBtn.title_font()).is_same(house.call("font", 500))
	_view.set_save({"name": "x", "modified_unix": 1727000000})
	assert_object(_view.buttons.ContinueBtn.title_font()).is_same(house.call("font", 600))
	assert_object(_view.welcome.get_theme_font("font")).is_same(house.call("font", 500))


## Settings was a 13 px link in the top right corner, the least findable control of the menu. RED on main: its
## parent is the masthead.
func test_settings_is_the_fifth_row_of_the_list_after_learn() -> void:
	_view.set_save({"name": "x", "modified_unix": 1727000000})   # with a save Learn is the fourth row
	var settings: Control = _view.buttons.SettingsBtn
	assert_str(String(settings.get_parent().name)).is_equal("MenuButtons")
	assert_int(settings.get_index()).is_equal(4)
	assert_object(_view.buttons.LearnBtn.get_parent().get_child(3)).is_same(_view.buttons.LearnBtn)
	var order: Array = _view.main_buttons().map(func(b: Control) -> String: return String(b.name))
	assert_int(order.find("SettingsBtn")).is_equal(order.find("LearnBtn") + 1)


## A first launch points at Learn: second in the list, lit at rest and tagged "NEW HERE?"; with a save it is back in
## fourth place and plain; the main buttons follow the shown order (red on main: always fourth, never tagged).
func test_first_launch_points_at_learn() -> void:
	_view.set_save({})
	var rows: Control = _view.buttons.LearnBtn.get_parent()
	assert_int(_view.buttons.LearnBtn.get_index()).override_failure_message("Learn is not second").is_equal(1)
	assert_bool(_view.buttons.LearnBtn.get("highlighted")).is_true()
	assert_str(str(_view.buttons.LearnBtn.get("tag"))).is_equal("NEW HERE?")
	var order: Array = _view.main_buttons().map(func(b: Control) -> String: return String(b.name))
	assert_int(order.find("LearnBtn")).is_equal(order.find("StartBattleBtn") + 1)
	_view.set_save({"name": "x", "modified_unix": 1727000000})
	assert_int(_view.buttons.LearnBtn.get_index()).is_equal(3)
	assert_bool(_view.buttons.LearnBtn.get("highlighted")).is_false()
	assert_str(str(_view.buttons.LearnBtn.get("tag"))).is_empty()
	assert_int(rows.get_child_count()).is_equal(5)
	assert_str(_view.buttons.StartBattleBtn.description).is_equal(
		"Choose a game system, a biome and a size")


## The menu arrives, once per start: every row ends at alpha 1 on its resting place. RED on main: no arrival.
func test_menu_arrives_once_and_every_row_rests_at_alpha_one() -> void:
	assert_bool(_view.has_method("play_arrival")).override_failure_message("the menu has no arrival").is_true()
	if not _view.has_method("play_arrival"):
		return
	var before_motion: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = false
	var rows: Array = _view.find_child("MenuButtons", true, false).get_children()
	var rest: Array = rows.map(func(row: Control) -> float: return row.position.y)
	_view.call("play_arrival")
	assert_float(rows[0].modulate.a).override_failure_message("the first row was not hidden at the start").is_equal(0.0)
	assert_float(rows[0].position.y).is_greater(rest[0])
	await _view.arrived
	for i in rows.size():
		assert_float(rows[i].modulate.a).is_equal(1.0)
		assert_float(rows[i].position.y).is_equal(rest[i])
	assert_float(_view.get("_masthead").modulate.a).is_equal(1.0)
	_view.call("play_arrival")
	assert_float(rows[0].modulate.a).override_failure_message("the arrival played a second time").is_equal(1.0)


## A sub-menu panel moves (motion table): it fades and slides in, and it is still on screen the moment after
## Close until its out motion has run. RED on main: it appeared and vanished at once.
func test_route_panel_fades_and_slides_in_and_out() -> void:
	var before_motion: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = false
	_view.show_route("help")
	assert_float(_view.route_panel.modulate.a).override_failure_message("the panel opened at once").is_less(1.0)
	await get_tree().create_timer(0.5).timeout
	assert_float(_view.route_panel.modulate.a).is_equal(1.0)
	_view.close_route()
	assert_bool(_view.route_panel.visible).override_failure_message("the panel vanished at once").is_true()
	if _view.route_panel.visible:
		await _view.route_closed
	assert_bool(_view.route_panel.visible).is_false()
	assert_float(_view.route_panel.modulate.a).is_equal(1.0)
	GraphicsSettings.reduce_motion = before_motion


func test_route_panel_is_instant_with_reduce_motion() -> void:
	var before_motion: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = true
	_view.show_route("help")
	assert_float(_view.route_panel.modulate.a).is_equal(1.0)
	var closed := [false]
	_view.route_closed.connect(func() -> void: closed[0] = true)
	_view.close_route()
	assert_bool(_view.route_panel.visible).is_false()
	assert_bool(closed[0]).is_true()
	GraphicsSettings.reduce_motion = before_motion


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


## The save list (step 48.1) lists every save of a folder, newest first, without reading the files (red on main:
## no such method). Three saves a second apart, one upper-case extension, one file that is not a save.
func test_list_saves_lists_every_save_newest_first_without_the_facts() -> void:
	var manager: GDScript = load("res://scripts/save_manager.gd")
	assert_bool(manager.has_method("list_saves")).override_failure_message("no list_saves").is_true()
	if not manager.has_method("list_saves"):
		return
	var dir := "user://list_saves_fixture"
	DirAccess.make_dir_recursive_absolute(dir)
	for file: String in ["oldest.nml", "middle.NML", "newest.nml"]:
		FileAccess.open(dir.path_join(file), FileAccess.WRITE).store_string(
			FileAccess.get_file_as_string(CARD_FIXTURES.path_join("save_with_facts.nml")))
		await get_tree().create_timer(1.1).timeout
	FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE).store_string("not a save")
	var saves: Array = manager.call("list_saves", dir)
	var names: Array = saves.map(func(info: Dictionary) -> String: return str(info.get("name", "")))
	assert_array(names).is_equal(["newest", "middle", "oldest"])
	assert_bool((saves[0] as Dictionary).has("system")).is_false()
	assert_int(int((saves[0] as Dictionary).get("modified_unix", 0))).is_greater(0)
	assert_array(manager.call("list_saves", "user://no_such_save_folder")).is_empty()
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


## The bundled Source Code Pro is a variable font whose default instance is ExtraLight: every mono line of the
## first screen asks for weight 400 (red on main: the plain font, thin and dim).
func test_mono_lines_carry_weight_400() -> void:
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	var lines: Array = [_view.version, _view.status] + (_view.get("save_facts") as Array)
	assert_int(lines.size()).is_equal(4)
	for line: Label in lines:
		var font := line.get_theme_font("font") as FontVariation
		assert_object(font).override_failure_message("a mono line has the plain font").is_not_null()
		if font != null:
			assert_int(int(font.variation_opentype.get(tag, 0))).is_equal(400)


## The kickers are eyebrows (tracked, the welcome one in the accent), the version reads in capitals and the rule under
## the wordmark is the signature: 28 px of gold, then the accent fading out, 2 px high (red on main: a 1 px grey rule).
func test_kickers_are_eyebrows_and_the_rule_is_the_signature() -> void:
	assert_object(_view.welcome_kicker.get_theme_font("font")).is_same(HouseStyle.eyebrow_font())
	assert_that(_view.welcome_kicker.get_theme_color("font_color")).is_equal(HouseStyle.ACCENT)
	assert_bool(_view.version.uppercase).is_true()
	var rule := _view.find_child("SignatureRule", true, false) as Control
	assert_object(rule).override_failure_message("no signature rule under the wordmark").is_not_null()
	if rule != null:
		assert_that(rule.get_combined_minimum_size()).is_equal(Vector2(470, HouseStyle.RULE_H))
		assert_that((rule.get_child(0) as ColorRect).color).is_equal(HouseStyle.GOLD)


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


## The Continue card is tighter (kicker, name and lines 4 px apart, 18 px of padding), dates the save as "22 Sep 2024"
## and draws two gold corner brackets (sheet 01; red on main: 12 px gaps, 20 px padding, "2024-09-22", no corners).
func test_continue_card_is_tight_dated_in_words_and_has_corner_brackets() -> void:
	_view.set_save({"name": "plain", "modified_unix": 1727000000})
	assert_str(_view.save_date.text).is_equal("Saved on 22 Sep 2024")
	var panel := _view.resume.get_theme_stylebox("panel") as StyleBoxFlat
	assert_float(panel.content_margin_left).is_equal(18.0)
	var column: Control = _view.save_date.get_parent()
	assert_int(column.get_theme_constant("separation")).is_equal(4)
	assert_int(_view.resume.get_signal_connection_list("draw").size()).override_failure_message(
		"the card draws no corner brackets").is_greater(0)


func test_continue_card_shows_the_biome_picture_when_the_biome_is_known() -> void:
	var picture: Variant = _view.get("save_picture")
	assert_bool(picture is TextureRect).override_failure_message("the card has no picture").is_true()
	if picture is not TextureRect:
		return
	_view.set_save(SaveManager.latest_save_info(CARD_FIXTURES))
	assert_bool(picture.visible).is_true()
	assert_object(picture.texture).is_not_null()
	assert_vector(picture.custom_minimum_size).is_equal(Vector2(150, 112))
	_view.set_save({"name": "odd", "modified_unix": 1727000000, "biome": "no_such_biome"})
	assert_bool(picture.visible).is_false()


func _cap_text(parent: Node) -> String:
	for n: Node in parent.find_children("*", "Label", true, false):
		var label := n as Label
		if label.theme_type_variation == HouseStyle.KEYCAP and label.is_visible_in_tree():
			return label.text
	return ""


## The main action says its key and so does Quit; a footer link's focus is a 2 px accent ring.
## RED on main: no key caps and a 1 px gold focus line.
## The rows end in a drawn chevron (no text glyph), Continue in none; the key cap on a gold row is the dark ink at 16 %
## in mono 14 px (the view's floor); the footer links carry an 18 px icon (sheet 01; red on main: a "›" glyph, a plain cap, no icons).
func test_rows_end_in_a_chevron_caps_sit_on_gold_and_footer_links_have_icons() -> void:
	_view.set_save({})
	for id: String in ["StartBattleBtn", "OnlineBtn", "LoadBattleBtn", "LearnBtn", "SettingsBtn"]:
		assert_object(_view.buttons[id].get("end_mark")).override_failure_message("%s has no drawn end mark" % id).is_not_null()
	assert_object(_view.buttons.ContinueBtn.get("end_mark")).override_failure_message("Continue draws an end mark").is_null()
	assert_str(FileAccess.get_file_as_string("res://scripts/startup_menu_view.gd")).override_failure_message(
		"the view still draws the text glyph").not_contains("GLYPH_GO")
	var cap: Label = _view.buttons.StartBattleBtn.get("key_cap")
	assert_object(cap).is_not_null()
	if cap != null:
		var box := cap.get_theme_stylebox("normal") as StyleBoxFlat
		assert_float(box.bg_color.a).is_equal_approx(0.16, 0.001)
		assert_float(box.border_color.a).is_equal_approx(0.35, 0.001)
		assert_object(cap.get_theme_color("font_color")).is_equal(HouseStyle.ON_GOLD)
		assert_int(cap.get_theme_font_size("font_size")).is_equal(14)
	for id: String in ["HelpBtn", "CreditsBtn", "ExitGameBtn"]:
		var link := _view.buttons[id] as Button
		assert_object(link.icon).override_failure_message("%s has no icon" % id).is_not_null()
		assert_int(link.get_theme_constant("icon_max_width")).is_equal(18)


func test_main_action_and_quit_show_key_caps_and_links_focus_with_a_ring() -> void:
	_view.set_save({})
	assert_str(_cap_text(_view.buttons.StartBattleBtn)).override_failure_message(
		"the first-run main action has no Enter key cap").is_equal("Enter")
	_view.set_save({"name": "x", "modified_unix": 1727000000})
	assert_str(_cap_text(_view.buttons.ContinueBtn)).override_failure_message(
		"Continue has no Enter key cap").is_equal("Enter")
	assert_str(_cap_text(_view.buttons.StartBattleBtn)).override_failure_message(
		"a row that is not the main action shows the Enter cap").is_equal("")
	assert_str(_cap_text(_view.buttons.ExitGameBtn.get_parent())).override_failure_message(
		"Quit has no Esc key cap").is_equal("Esc")
	var ring := _view.buttons.HelpBtn.get_theme_stylebox("focus") as StyleBoxFlat
	assert_int(ring.border_width_left).is_equal(2)
	assert_object(ring.border_color).is_equal(HouseStyle.ACCENT)
