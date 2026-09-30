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


func _picker_missing(d: Window) -> Array:
	var missing: Array = []
	var track := TutorialFlow.build_tool_track()
	if _button(d, "RESUME") == null and _button(d, "ALL CHAPTERS DONE") == null:
		missing.append("button: RESUME")
	for lesson: Dictionary in track:
		if _button(d, "•  %s" % lesson.get("id", "")) == null and _button(d, "✓  %s" % lesson.get("id", "")) == null:
			missing.append("button: lesson %s" % lesson.get("id", ""))
	if _button(d, "RESET TUTORIAL PROGRESS") == null:
		missing.append("button: RESET TUTORIAL PROGRESS")
	if d.get_ok_button().text != "Close":
		missing.append("button: Close")
	return missing


func test_tutorial_picker_has_resume_every_lesson_reset_and_close() -> void:
	var d := await _open_picker()
	assert_object(d).is_not_null()
	assert_array(_picker_missing(d)).override_failure_message("picker controls missing: %s" % str(_picker_missing(d))).is_empty()
	assert_bool(_button(d, "RESET TUTORIAL PROGRESS").disabled).is_false()


func test_tutorial_picker_resume_and_lesson_buttons_launch_the_tutorial() -> void:
	var mode: Variant = ProjectSettings.get_setting("niemandsland/tutorial_mode", false)
	var lesson: Variant = ProjectSettings.get_setting("niemandsland/tutorial_lesson", "")
	var d := await _open_picker()
	_button(d, "RESUME").pressed.emit()
	await _frames(2)
	var launched: bool = _menu.entered_game
	var picked: Window = await _open_picker()
	var first_id: String = String(TutorialFlow.build_tool_track()[0].get("id", ""))
	_button(picked, "•  %s" % first_id).pressed.emit()
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
		if b != d.get_ok_button():
			rows.append(b)
	assert_int(rows.size()).is_equal(chapters.size())
	for i in chapters.size():
		var c: Dictionary = chapters[i]
		assert_bool(rows[i].text.contains(String(c.get("title", "")).to_upper())).override_failure_message("chapter %s row lost its title" % c.get("id", "")).is_true()
		assert_bool(rows[i].disabled).is_equal(not Spielschule.is_available(c))
		var goal := String(c.get("goal", ""))
		var seen := false
		for l: Node in d.find_children("*", "Label", true, false):
			if (l as Label).text.strip_edges() == goal:
				seen = true
		assert_bool(seen).override_failure_message("chapter %s lost its goal line" % c.get("id", "")).is_true()


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
		if b != d.get_ok_button():
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
	var quit := _dialog_titled("Quit Niemandsland") as ConfirmationDialog
	assert_object(quit).is_not_null()
	assert_str(quit.ok_button_text).is_equal("Quit")
	assert_str(quit.cancel_button_text).is_equal("Back")
	assert_str(quit.dialog_text).is_equal("Are you sure you want to quit Niemandsland?")
	assert_object(quit.get_viewport().gui_get_focus_owner()).is_same(quit.get_cancel_button())
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
	assert_bool(texts.has("Installed: 0.3.13.1    →    Latest: 0.3.14.0")).is_true()
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


func _wears_house_chrome(d: AcceptDialog) -> bool:
	return d.theme == HouseStyle.theme() and d.get_ok_button().theme_type_variation == HouseStyle.PRIMARY


func test_dialogs_wear_the_house_chrome() -> void:
	var picker := await _open_picker()
	assert_bool(_wears_house_chrome(picker)).override_failure_message("tutorial picker is not in the house style").is_true()
	assert_str(String(_button(picker, "RESUME").theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_str(String(_button(picker, "RESET TUTORIAL PROGRESS").theme_type_variation)).is_equal(String(HouseStyle.DANGER_BUTTON))
	var trial := await _open_trial()
	assert_bool(_wears_house_chrome(trial)).override_failure_message("Trial by Fire is not in the house style").is_true()
	for b in _buttons(trial):
		if b != trial.get_ok_button():
			assert_str(String(b.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	_menu._on_credits_pressed()
	_menu._on_exit_pressed()
	await _frames(2)
	assert_bool(_wears_house_chrome(_dialog_titled("Credits & licenses"))).override_failure_message("credits is not in the house style").is_true()
	var quit := _dialog_titled("Quit Niemandsland") as ConfirmationDialog
	assert_bool(_wears_house_chrome(quit)).override_failure_message("quit is not in the house style").is_true()
	assert_str(String(quit.get_cancel_button().theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_bool(_wears_house_chrome(_update_prompt("notes"))).override_failure_message("update prompt is not in the house style").is_true()


func test_dialogs_define_no_colour_literals() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu.gd")
	var mine := src.substr(src.find("func _show_tutorial_picker"), src.find("func _launch_scenario") - src.find("func _show_tutorial_picker"))
	assert_str(mine).not_contains("HudTokens.TEXT_MUTED")
	assert_str(mine).not_contains("HudTokens.DANGER")


func test_inventory_check_names_a_removed_control() -> void:
	var d := await _open_picker()
	assert_array(_picker_missing(d)).is_empty()
	var reset := _button(d, "RESET TUTORIAL PROGRESS")
	reset.get_parent().remove_child(reset)
	var missing := _picker_missing(d)
	d.add_child(reset)
	assert_array(missing).contains_exactly(["button: RESET TUTORIAL PROGRESS"])
