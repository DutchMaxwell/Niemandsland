extends GdUnitTestSuite
## The arrival card on a new table (step 49.5): three numbered lines, done / now / pending, a close box.
## Red before the step: there is no res://scripts/hud/arrival_card.gd.

const SCRIPT := "res://scripts/hud/arrival_card.gd"


func _card() -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no arrival card").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var card: Control = auto_free((load(SCRIPT) as GDScript).new())
	add_child(card)
	card.call("set_lines", ["Bring your army", "Pick an opponent", "Deploy and start"])
	await get_tree().process_frame
	return card


func test_one_line_done_makes_the_second_current_and_the_third_pending() -> void:
	var card := await _card()
	if card == null:
		return
	card.call("set_done", 1)
	assert_array([card.call("state", 0), card.call("state", 1), card.call("state", 2)]).is_equal(
		[&"done", &"now", &"next"])
	var texts: Array = card.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["FIRST STEPS", "Your table is ready.", "Bring your army", "Deploy and start"])


func test_a_line_answers_with_its_index() -> void:
	var card := await _card()
	if card == null:
		return
	var pressed: Array = []
	card.connect("line_pressed", func(index: int) -> void: pressed.append(index))
	(card.find_child("Line3", true, false) as Button).pressed.emit()
	assert_array(pressed).is_equal([2])


func test_no_label_is_smaller_than_12_px() -> void:
	var card := await _card()
	if card == null:
		return
	for label: Label in card.find_children("*", "Label", true, false):
		assert_int(label.get_theme_font_size(&"font_size")).override_failure_message(label.text).is_greater_equal(12)
