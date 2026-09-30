extends GdUnitTestSuite
## E2E — the tutorial's two dialogs, row 52 of the UI inventory (uimenus step 12): "Welcome to the tutorial"
## (two self-assessment CheckButtons, START, Esc / cancel asks again next time) and "Skip the basics?"
## (SKIP THE BASICS / PLAY EVERYTHING, offered only to simulator veterans). The director is a probe: the
## lesson start is a counter and the progress file is never written. Answers land in the in-memory progress.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

class ProgressStub extends TutorialProgress:
	func save_to_disk() -> Error:
		return OK

class DirectorProbe extends "res://scripts/tutorial_director.gd":
	var started := 0
	func _start_from_progress() -> void:
		started += 1

var _dir: Node
var _progress: TutorialProgress


func before_test() -> void:
	_progress = ProgressStub.new()
	_dir = DirectorProbe.new()
	_dir.progress = _progress
	add_child(_dir)
	_dir._show_assessment()
	await get_tree().process_frame


func after_test() -> void:
	_dir.queue_free()


func _checks() -> Array[CheckButton]:
	var out: Array[CheckButton] = []
	for n: Node in _dir._assessment_dialog.find_children("*", "CheckButton", true, false):
		out.append(n as CheckButton)
	return out


func _missing() -> Array:
	var missing: Array = []
	var d: ConfirmationDialog = _dir._assessment_dialog
	if d.ok_button_text != "START":
		missing.append("button: START")
	var texts: Array[String] = []
	for c in _checks():
		texts.append(c.text)
	for t: String in ["I know the OnePageRules basics", "I have used a tabletop simulator before"]:
		if not texts.has(t):
			missing.append("check: %s" % t)
	var intro := false
	for l: Node in d.find_children("*", "Label", true, false):
		if (l as Label).text == "Two quick questions so the tutorial fits you:":
			intro = true
	if not intro:
		missing.append("label: intro")
	return missing


func _skip_dialog() -> ConfirmationDialog:
	for n: Node in _dir.get_children():
		if n is ConfirmationDialog and (n as ConfirmationDialog).title == "Skip the basics?" and not n.is_queued_for_deletion():
			return n as ConfirmationDialog
	return null


func test_assessment_has_title_intro_both_questions_and_start() -> void:
	assert_str(_dir._assessment_dialog.title).is_equal("Welcome to the tutorial")
	assert_array(_missing()).override_failure_message("assessment controls missing: %s" % str(_missing())).is_empty()
	for c in _checks():
		assert_bool(c.button_pressed).is_false()


func test_start_records_both_answers_and_starts_when_no_skip_is_offered() -> void:
	_checks()[0].button_pressed = true
	_dir._assessment_dialog.confirmed.emit()
	await get_tree().process_frame
	assert_bool(_progress.assessment_answered()).is_true()
	assert_int(_dir.started).is_equal(1)
	assert_object(_skip_dialog()).override_failure_message("no skip offer without simulator experience").is_null()


func test_simulator_veteran_gets_the_skip_offer_and_skip_the_basics_marks_them_done() -> void:
	_checks()[1].button_pressed = true
	_dir._assessment_dialog.confirmed.emit()
	await get_tree().process_frame
	var d := _skip_dialog()
	assert_object(d).is_not_null()
	assert_str(d.ok_button_text).is_equal("SKIP THE BASICS")
	assert_str(d.cancel_button_text).is_equal("PLAY EVERYTHING")
	assert_str(d.dialog_text).contains("Skip the camera and select/move basics")
	assert_int(_dir.started).is_equal(0)
	d.confirmed.emit()
	assert_int(_dir.started).is_equal(1)
	for id in TutorialProgress.skip_offer_lessons(true):
		assert_bool(_progress.is_lesson_completed(id)).override_failure_message("%s was not marked done" % id).is_true()


func test_play_everything_starts_without_marking_anything() -> void:
	_checks()[1].button_pressed = true
	_dir._assessment_dialog.confirmed.emit()
	await get_tree().process_frame
	_skip_dialog().canceled.emit()
	assert_int(_dir.started).is_equal(1)
	for id in TutorialProgress.skip_offer_lessons(true):
		assert_bool(_progress.is_lesson_completed(id)).is_false()


func test_cancelling_the_assessment_starts_but_asks_again_next_time() -> void:
	_dir._assessment_dialog.canceled.emit()
	assert_int(_dir.started).is_equal(1)
	assert_bool(_progress.assessment_answered()).is_false()


func test_both_dialogs_wear_the_house_chrome_and_the_checks_stay_toggles() -> void:
	var d: ConfirmationDialog = _dir._assessment_dialog
	assert_object(d.theme).is_same(HouseStyle.theme())
	assert_str(String(d.get_ok_button().theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	for c in _checks():
		assert_str(String(c.theme_type_variation)).override_failure_message("a question became a button line").is_equal("")
	_checks()[1].button_pressed = true
	d.confirmed.emit()
	await get_tree().process_frame
	var skip := _skip_dialog()
	assert_object(skip.theme).is_same(HouseStyle.theme())
	assert_str(String(skip.get_ok_button().theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(skip.get_cancel_button().theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_bool(FileAccess.get_file_as_string("res://scripts/tutorial_director.gd").contains("HudTokens.SECTION_SEP")).is_false()


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing()).is_empty()
	var check := _checks()[0]
	var parent := check.get_parent()
	parent.remove_child(check)
	var missing := _missing()
	parent.add_child(check)
	assert_array(missing).contains_exactly(["check: I know the OnePageRules basics"])
