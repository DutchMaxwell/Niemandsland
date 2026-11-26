extends GdUnitTestSuite
## E2E — the menu scene's default-themed dialogs, rows 46-49 of the UI inventory (uimenus step 11, part 2):
## tutorial picker, Trial by Fire list, report / credits / quit messages, update prompt. Every control of
## today's dialogs is found by its text and does what it does today. The dialogs are their own Windows, so
## (as e2e_hero_morale_prompt_test.gd does) their buttons are pressed by signal, not by coordinates.
## Not pressed for real: RESET TUTORIAL PROGRESS (wipes the developer's real progress file) and Report a
## problem (OS.shell_open on the Desktop) — both are found and checked by presence only.
## test_inventory_check_names_a_removed_control proves the presence check can fail; the chrome tests are
## added WITH the restyle (red on main).

class MenuTransitionProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _transition_to_game() -> void:
		entered_game = true

var _menu: Control


func before_test() -> void:
	_menu = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	_menu.set_script(MenuTransitionProbe)
	add_child(_menu)
	await _frames(2)


func after_test() -> void:
	_menu = null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _dialog_titled(title: String) -> Window:
	for n: Node in _menu.get_children():
		if n is Window and (n as Window).title == title and not n.is_queued_for_deletion():
			return n as Window
	return null


func _buttons(d: Node) -> Array[Button]:
	var out: Array[Button] = []
	for n: Node in d.find_children("*", "Button", true, false):
		out.append(n as Button)
	return out


func _button(d: Node, prefix: String) -> Button:
	for b in _buttons(d):
		if b.text.begins_with(prefix):
			return b
	return null


func _open_picker() -> Window:
	var track := TutorialFlow.build_tool_track()
	_menu._show_tutorial_picker(TutorialProgress.new(), track)
	await _frames(2)
	return _dialog_titled("Tutorial")


func _open_trial() -> Window:
	_menu._on_spielschule_pressed()
	await _frames(2)
	return _dialog_titled("TRIAL BY FIRE")


func _update_prompt(notes: String) -> UpdatePrompt:
	var p := UpdatePrompt.new()
	p.setup("0.3.13.1", "0.3.14.0", "https://example.invalid/r.zip", notes)
	_menu.add_child(p)
	p.popup_centered()
	return p


## The picker's top button: "Start", "Continue with lesson n" or the all-done line.
func _resume_button(d: Node) -> Button:
	for prefix: String in ["Start", "Continue with lesson", "All lessons done"]:
		var b := _button(d, prefix)
		if b != null:
			return b
	return null


func _picker_missing(d: Window) -> Array:
	var missing: Array = []
	var track := TutorialFlow.build_tool_track()
	if _resume_button(d) == null:
		missing.append("button: RESUME")
	for position in track.size():
		var lesson: Dictionary = track[position]
		if _button(d, "%02d  %s" % [position + 1, lesson.get("title", "")]) == null:
			missing.append("button: lesson %s" % lesson.get("id", ""))
	if _button(d, "Reset tutorial progress") == null:
		missing.append("button: RESET TUTORIAL PROGRESS")
	if d.get_ok_button().text != "Close":
		missing.append("button: Close")
	return missing


func test_tutorial_picker_has_resume_every_lesson_reset_and_close() -> void:
	var d := await _open_picker()
	assert_object(d).is_not_null()
	assert_array(_picker_missing(d)).override_failure_message("picker controls missing: %s" % str(_picker_missing(d))).is_empty()
	assert_bool(_button(d, "Reset tutorial progress").disabled).is_false()


func test_tutorial_picker_resume_and_lesson_buttons_launch_the_tutorial() -> void:
	var mode: Variant = ProjectSettings.get_setting("niemandsland/tutorial_mode", false)
	var lesson: Variant = ProjectSettings.get_setting("niemandsland/tutorial_lesson", "")
	var d := await _open_picker()
	_resume_button(d).pressed.emit()
	await _frames(2)
	var launched: bool = _menu.entered_game
	var picked: Window = await _open_picker()
	var first_id: String = String(TutorialFlow.build_tool_track()[0].get("id", ""))
	_button(picked, "01  ").pressed.emit()
	await _frames(2)
	var armed: Variant = ProjectSettings.get_setting("niemandsland/tutorial_lesson", "")
	ProjectSettings.set_setting("niemandsland/tutorial_mode", mode)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson", lesson)
	assert_bool(launched).override_failure_message("RESUME did not launch the tutorial").is_true()
	assert_str(str(armed)).is_equal(first_id)
	assert_bool(not is_instance_valid(d) or d.is_queued_for_deletion()).is_true()


func test_tutorial_picker_close_frees_the_dialog() -> void:
	var d := await _open_picker()
	d.confirmed.emit()
	await _frames(2)
	assert_bool(not is_instance_valid(d) or d.is_queued_for_deletion()).is_true()


func test_trial_by_fire_lists_every_chapter_with_goal_and_availability() -> void:
	var d := await _open_trial()
	assert_object(d).is_not_null()
	assert_str(d.get_ok_button().text).is_equal("Close")
	var chapters := Spielschule.chapters()
	var rows: Array[Button] = []
	for b in _buttons(d):
		if b != d.get_ok_button() and b.name != "CloseButton":
			rows.append(b)
	assert_int(rows.size()).is_equal(chapters.size())
	for i in chapters.size():
		var c: Dictionary = chapters[i]
		assert_bool(rows[i].text.contains(String(c.get("title", "")))).override_failure_message("chapter %s row lost its title" % c.get("id", "")).is_true()
		assert_bool(rows[i].disabled).is_equal(not Spielschule.is_available(c))
		var goal := String(c.get("goal", ""))
		var seen := false
		for l: Node in d.find_children("*", "Label", true, false):
			if (l as Label).text.strip_edges() == goal:
				seen = true
		assert_bool(seen).override_failure_message("chapter %s lost its goal line" % c.get("id", "")).is_true()


## The labels wrapped at one letter and the window grew to a whole list tall: its Close button stood far below
## the screen (red on main: bottom edge 2,519 in a 1,080 px window).
func test_trial_by_fire_window_fits_inside_the_viewport() -> void:
	var d := await _open_trial()
	assert_object(d).is_not_null()
	var viewport_h := int(get_tree().root.get_visible_rect().size.y)
	var bottom := d.position.y + d.size.y
	assert_int(bottom).override_failure_message("window bottom edge %s in a %s px viewport" % [bottom, viewport_h]).is_less_equal(viewport_h)
	var close_bottom: float = d.get_ok_button().get_global_rect().end.y
	assert_float(close_bottom).override_failure_message("Close button bottom %s is outside its window (%s px tall)" % [close_bottom, d.size.y]).is_less_equal(float(d.size.y))


func test_trial_by_fire_playable_row_launches_its_scenario() -> void:
	var keys := ["niemandsland/scenario_mode", "niemandsland/scenario_path", "niemandsland/scenario_chapter"]
	var before := {}
	for k in keys:
		before[k] = ProjectSettings.get_setting(k, null)
	var d := await _open_trial()
	var chapters := Spielschule.chapters()
	var idx := -1
	for i in chapters.size():
		if Spielschule.is_available(chapters[i]):
			idx = i
			break
	if idx < 0:
		return
	var rows: Array[Button] = []
	for b in _buttons(d):
		if b != d.get_ok_button() and b.name != "CloseButton":
			rows.append(b)
	rows[idx].pressed.emit()
	await _frames(2)
	var chapter: Variant = ProjectSettings.get_setting("niemandsland/scenario_chapter", "")
	for k in keys:
		ProjectSettings.set_setting(k, before[k])
	assert_str(str(chapter)).is_equal(String(chapters[idx].get("id", "")))
	assert_bool(_menu.entered_game).is_true()


func test_credits_and_quit_dialogs_keep_their_words() -> void:
	_menu._on_credits_pressed()
	_menu._on_exit_pressed()
	await _frames(2)
	var credits := _dialog_titled("Credits & licenses")
	assert_object(credits).is_not_null()
	var quit: PromptCard = _menu.get("_exit_card")
	assert_object(quit).override_failure_message("Quit opens no prompt card").is_not_null()
	if quit == null:
		return
	assert_str(quit.title).is_equal("Quit Niemandsland")
	assert_str(quit.ok_button.text).is_equal("Quit")
	assert_str(quit.cancel_button.text).is_equal("Back")
	var words: Array[String] = []
	for l: Node in quit.find_children("*", "Label", true, false):
		words.append((l as Label).text)
	assert_bool(words.has("Are you sure you want to quit Niemandsland?")).is_true()
	assert_object(quit.get_viewport().gui_get_focus_owner()).is_same(quit.cancel_button)
	quit.cancel_button.pressed.emit()   # never press Quit: it ends the test run
	assert_bool(credits.get_ok_button() != null).is_true()


func test_update_prompt_keeps_its_headline_versions_notes_skip_and_buttons() -> void:
	var p := _update_prompt("- fixed a thing\n- added a thing")
	await _frames(2)
	assert_str(p.title).is_equal("Update available")
	assert_str(p.ok_button_text).is_equal("Update & Restart")
	assert_str(p.get_cancel_button().text).is_equal("Later")
	var texts: Array[String] = []
	for l: Node in p.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_bool(texts.has("A newer version of Niemandsland is available.")).is_true()
	assert_bool("".join(texts).contains("INSTALLED 0.3.13.1  →  LATEST 0.3.14.0")).override_failure_message(
		"versions line: %s" % str(texts)).is_true()
	assert_int(p.find_children("*", "RichTextLabel", true, false).size()).is_equal(1)
	var skip := _button(p, "Skip this version")
	if skip == null:
		for c: Node in p.find_children("*", "CheckBox", true, false):
			skip = c as Button
	assert_object(skip).is_not_null()
	assert_bool(p.is_skip_checked()).is_false()
	skip.button_pressed = true
	assert_bool(p.is_skip_checked()).is_true()
	var empty := _update_prompt("  ")
	assert_int(empty.find_children("*", "RichTextLabel", true, false).size()).is_equal(0)


## The update prompt as the mockup draws it (sheet 08): 560 px wide and as high as its content, the versions in one mono
## card, the notes in a 132 px card that scrolls, Later and Update & Restart as two 44 px buttons in one row of the content
## that answer like the dialog's own (hidden) buttons (red on main: the dialog's buttons, an 800 px window).
func test_update_prompt_has_its_actions_in_the_content_row() -> void:
	var p := _update_prompt("- fixed a thing\n- added a thing")
	await _frames(3)
	var later := _button(p, "Later")
	var update := _button(p, "Update & Restart")
	assert_object(later).is_not_null()
	assert_object(update).is_not_null()
	if later == null or update == null:
		return
	assert_bool(p.get_ok_button().visible).override_failure_message("the dialog's own button row is shown").is_false()
	assert_float(later.size.y).is_equal(float(HouseStyle.MENU_H_ACTION))
	assert_float(later.size.x).is_equal_approx(update.size.x, 1.0)
	assert_bool(later.global_position.x < update.global_position.x).is_true()
	assert_int(p.size.x).is_equal(560)
	assert_int(p.size.y).override_failure_message("window is %d px high" % p.size.y).is_less(600)
	var answers: Array[String] = []
	p.confirmed.connect(func() -> void: answers.append("update"))
	p.canceled.connect(func() -> void: answers.append("later"))
	update.pressed.emit()
	later.pressed.emit()
	assert_array(answers).is_equal(["update", "later"])


func _wears_house_chrome(d: AcceptDialog) -> bool:
	return d.theme == HouseStyle.menu_theme() and d.get_ok_button().theme_type_variation == HouseStyle.PRIMARY


## One title: the window has no frame of its own, its title stands as the first row of its content.
func _has_one_title(d: AcceptDialog) -> bool:
	if not d.borderless:
		return false
	for n: Node in d.find_children("*", "Label", true, false):
		if (n as Label).text == d.title.to_upper():
			return true
	return false


func test_dialogs_wear_the_house_chrome() -> void:
	var picker := await _open_picker()
	assert_bool(_wears_house_chrome(picker)).override_failure_message("tutorial picker is not in the house style").is_true()
	assert_bool(_has_one_title(picker)).override_failure_message("tutorial picker has no header title").is_true()
	assert_str(String(_resume_button(picker).theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button(picker, "Reset tutorial progress").theme_type_variation)).is_equal(String(HouseStyle.DANGER_BUTTON))
	var trial := await _open_trial()
	assert_bool(_wears_house_chrome(trial)).override_failure_message("Trial by Fire is not in the house style").is_true()
	assert_bool(_has_one_title(trial)).override_failure_message("Trial by Fire has no header title").is_true()
	for b in _buttons(trial):
		if b != trial.get_ok_button() and b.name != "CloseButton":
			assert_str(String(b.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	_menu._on_credits_pressed()
	_menu._on_exit_pressed()
	await _frames(2)
	assert_bool(_wears_house_chrome(_dialog_titled("Credits & licenses"))).override_failure_message("credits is not in the house style").is_true()
	assert_bool(_has_one_title(_dialog_titled("Credits & licenses"))).override_failure_message("credits has no header title").is_true()
	var quit: PromptCard = _menu._exit_card
	assert_str(String(quit.ok_button.theme_type_variation)).override_failure_message("quit is not in the house style").is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(quit.cancel_button.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_bool(_wears_house_chrome(_update_prompt("notes"))).override_failure_message("update prompt is not in the house style").is_true()
	assert_bool(_has_one_title(_update_prompt("notes"))).override_failure_message("update prompt has no header title").is_true()


## The dialog ignores a script minimum size for its buttons: only the theme constant reaches them (red on
## main: 19 px tall). The credits window stands for every window that is still an AcceptDialog (Quit is a
## prompt card now).
func test_dialog_buttons_stand_at_action_height() -> void:
	_menu._on_credits_pressed()
	await _frames(2)
	var credits := _dialog_titled("Credits & licenses") as AcceptDialog
	assert_object(credits).is_not_null()
	var ok := credits.get_ok_button().size
	assert_float(ok.y).override_failure_message("OK button is %s px tall" % ok.y).is_greater_equal(float(HouseStyle.H_ACTION))
	assert_float(ok.x).override_failure_message("OK button is %s px wide" % ok.x).is_greater_equal(120.0)


## The menu's windows are drawn at the menu's type scale (sheet 08): 18 px text, 16 px actions 44 px high; the table's
## windows keep 14 / 15 / 40 (red on main: one scale for both).
func test_menu_windows_stand_at_the_menus_type_scale() -> void:
	_menu._on_credits_pressed()
	_menu._on_exit_pressed()
	await _frames(3)
	var quit: PromptCard = _menu._exit_card
	var text: Label = null
	for l: Node in quit.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("Are you sure"):
			text = l as Label
	assert_object(text).is_not_null()
	if text == null:
		return
	assert_int(text.get_theme_font_size(&"font_size")).override_failure_message("quit text is %d px" % text.get_theme_font_size(&"font_size")).is_equal(HouseStyle.MENU_FONT_BODY)
	assert_int(quit.ok_button.get_theme_font_size(&"font_size")).is_equal(HouseStyle.MENU_FONT_ACTION)
	assert_float(quit.ok_button.size.y).is_greater_equal(float(HouseStyle.MENU_H_ACTION))
	var credits := _dialog_titled("Credits & licenses") as AcceptDialog
	assert_object(credits.theme).is_same(HouseStyle.menu_theme())
	var at_table := AcceptDialog.new()
	MenuDialog.style(at_table, false, true)
	assert_object(at_table.theme).is_same(HouseStyle.theme())
	at_table.free()
	quit.cancel_button.pressed.emit()   # never press Quit: it ends the test run


func test_dialogs_define_no_colour_literals() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu.gd")
	var mine := src.substr(src.find("func _show_tutorial_picker"), src.find("func _launch_scenario") - src.find("func _show_tutorial_picker"))
	assert_str(mine).not_contains("HudTokens.TEXT_MUTED")
	assert_str(mine).not_contains("HudTokens.DANGER")


func test_inventory_check_names_a_removed_control() -> void:
	var d := await _open_picker()
	assert_array(_picker_missing(d)).is_empty()
	var reset := _button(d, "Reset tutorial progress")
	reset.get_parent().remove_child(reset)
	var missing := _picker_missing(d)
	d.add_child(reset)
	assert_array(missing).contains_exactly(["button: RESET TUTORIAL PROGRESS"])


func _scrim() -> ColorRect:
	for n: Node in _menu.get_children():
		if n is ColorRect and n.name == "DialogScrim" and not n.is_queued_for_deletion():
			return n as ColorRect
	return null


## A menu window dims the menu behind it while it is open and the scrim goes with it. RED on main: no scrim.
func test_menu_windows_dim_the_menu_while_open() -> void:
	_menu._on_credits_pressed()
	await _frames(2)
	var scrim := _scrim()
	assert_object(scrim).override_failure_message("no scrim behind the credits window").is_not_null()
	if scrim == null:
		return
	assert_bool(scrim.visible).is_true()
	await get_tree().create_timer(0.45).timeout  # the scrim fades in
	assert_bool(scrim.color.is_equal_approx(HouseStyle.SCRIM)).is_true()
	var credits := _dialog_titled("Credits & licenses") as AcceptDialog
	credits.confirmed.emit()
	credits.hide()
	await _frames(3)
	assert_object(_scrim()).override_failure_message("the scrim outlived the window").is_null()


## The credits text was cut mid-line in a 420 x 240 box. RED on main: 420 x 240.
func test_credits_box_is_large_enough_to_read_and_inside_the_window() -> void:
	_menu._on_credits_pressed()
	await _frames(2)
	var credits := _dialog_titled("Credits & licenses") as AcceptDialog
	assert_object(credits).is_not_null()
	var boxes := credits.find_children("*", "ScrollContainer", true, false)
	assert_int(boxes.size()).is_equal(1)
	var scroll := boxes[0] as ScrollContainer
	assert_float(scroll.size.x).override_failure_message("the credits box is %s px wide" % scroll.size.x).is_greater_equal(520.0)
	assert_float(scroll.size.y).override_failure_message("the credits box is %s px tall" % scroll.size.y).is_greater_equal(420.0)
	assert_bool(scroll.follow_focus).is_true()
	assert_float(float(credits.size.y)).is_less(_menu.get_viewport().get_visible_rect().size.y)



## Lessons have numbers, not working codes (D7): a row reads "01  Camera & table", the resume button "Start" or "Continue
## with lesson n"; no visible text of the picker or the Trial by Fire list matches a code like T-01, S-01 or W3 (red on
## main: "T-01 · CAMERA & TABLE", "RESUME - NEXT: T-01").
func test_lessons_show_numbers_not_working_codes() -> void:
	var regex := RegEx.create_from_string("[ST]-\\d\\d|W\\d")
	for d: Window in [await _open_picker(), await _open_trial()]:
		for b in _buttons(d):
			assert_bool(regex.search(b.text) != null).override_failure_message("%s shows %s" % [d.title, b.text]).is_false()
		for l: Node in d.find_children("*", "Label", true, false):
			assert_bool(regex.search((l as Label).text) != null).override_failure_message("%s shows %s" % [d.title, (l as Label).text]).is_false()
	var picker := await _open_picker()
	assert_str(_resume_button(picker).text).is_equal("Start")
