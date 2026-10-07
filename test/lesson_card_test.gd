extends GdUnitTestSuite

const Card := preload("res://scripts/hud/lesson_card.gd")


func _card() -> LessonCard:
	var card: LessonCard = auto_free(Card.new())
	add_child(card)
	return card


func _button(card: LessonCard, path: String) -> Button:
	var button := card.get_node_or_null(path) as Button
	assert_object(button).is_not_null()
	return button


func test_button_inventory_and_house_style() -> void:
	var card := _card()
	assert_object(card.theme).is_same(HouseStyle.theme())
	assert_str(String(card.theme_type_variation)).is_equal(String(HouseStyle.PANEL_VARIANT))
	for entry in [
		["Content/ContinueButton", "Continue"], ["Content/SkipButton", "Skip step"],
		["Content/LeaveButton", "Leave lesson"], ["Content/ChapterListButton", "Chapter list"],
		["Content/StayButton", "Stay on the table"], ["Content/ActionButton", ""],
	]:
		var button := _button(card, entry[0])
		if button != null:
			assert_str(button.text).is_equal(entry[1])
	assert_float(card.anchor_left).is_equal_approx(0.5, 0.001)
	assert_float(card.offset_top).is_equal_approx(72.0, 0.001)
	assert_bool(card.get_node("Content/StepText").autowrap_mode != TextServer.AUTOWRAP_OFF).is_true()
	assert_float(card.get_node("Content/StepText").custom_minimum_size.x).is_equal(380.0)


func test_step_and_complete_states() -> void:
	var card := _card()
	card.chapter_title = "First Steps"
	card.show_step(1, 6, {"text": "Read this.", "rule": "p.5",
		"all": [{"check": "counter_grew", "args": {"key": "continue"}}]})
	assert_bool(_button(card, "Content/ContinueButton").visible).is_true()
	assert_str(card.get_node("Content/Progress").text).is_equal("Step 2 of 6")
	assert_str(card.get_node("Content/Rule").text).is_equal("Rulebook p.5")
	card.show_step(2, 6, {"text": "Move.", "rule": "", "all": [{"check": "unit_moved"}]})
	assert_bool(_button(card, "Content/ContinueButton").visible).is_false()
	assert_bool(card.get_node("Content/Rule").visible).is_false()
	card.show_complete("First Steps")
	assert_bool(_button(card, "Content/SkipButton").visible).is_false()
	assert_bool(_button(card, "Content/ContinueButton").visible).is_false()
	assert_bool(_button(card, "Content/ChapterListButton").visible).is_true()
	assert_bool(_button(card, "Content/StayButton").visible).is_true()
	assert_str(card.get_node("Content/StepText").text).is_equal("Chapter complete ✓")
	var font: Font = card.get_node("Content/StepText").get_theme_font(&"font")
	assert_bool(font.has_char("✓".unicode_at(0))).is_true()


func test_each_action_emits_its_signal() -> void:
	var card := _card()
	var events: Array[String] = []
	card.continue_pressed.connect(func() -> void: events.append("continue"))
	card.skip_pressed.connect(func() -> void: events.append("skip"))
	card.leave_pressed.connect(func() -> void: events.append("leave"))
	card.stay_pressed.connect(func() -> void: events.append("stay"))
	card.show_step(0, 1, {"text": "Read", "rule": "", "all": [
		{"check": "counter_grew", "args": {"key": "continue"}}]})
	_button(card, "Content/ContinueButton").pressed.emit()
	_button(card, "Content/SkipButton").pressed.emit()
	_button(card, "Content/LeaveButton").pressed.emit()
	card.show_complete("First Steps")
	_button(card, "Content/ChapterListButton").pressed.emit()
	_button(card, "Content/StayButton").pressed.emit()
	assert_array(events).is_equal(["continue", "skip", "leave", "leave", "stay"])


func test_action_button_shows_only_on_a_step_with_an_action() -> void:
	var card := _card()
	card.show_step(1, 4, {"text": "Import an army.", "rule": "",
		"all": [{"check": "at_least", "args": {"key": "units_p1", "n": 1}}],
		"action": {"label": "Use the practice army",
			"fixture": "res://assets/tutorial/tutorial_army_p1.json"}})
	var button := card.get_node_or_null("Content/ActionButton") as Button
	assert_object(button).is_not_null()
	if button == null:
		return
	assert_bool(button.visible).is_true()
	assert_str(button.text).is_equal("Use the practice army")
	card.show_step(2, 4, {"text": "Deploy.", "rule": "",
		"all": [{"check": "flag", "args": {"key": "p1_all_in_zone"}}]})
	assert_bool(button.visible).is_false()


func test_action_button_emits_its_fixture() -> void:
	var card := _card()
	var got: Array[String] = []
	card.action_pressed.connect(func(fixture: String) -> void: got.append(fixture))
	card.show_step(0, 1, {"text": "t", "rule": "",
		"all": [{"check": "flag", "args": {"key": "x"}}],
		"action": {"label": "L", "fixture": "res://f.json"}})
	var button := card.get_node_or_null("Content/ActionButton") as Button
	assert_object(button).is_not_null()
	if button == null:
		return
	button.pressed.emit()
	assert_array(got).is_equal(["res://f.json"])
