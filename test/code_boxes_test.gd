extends GdUnitTestSuite
## The invitation code as six boxes (menu step 47.2): ONE text field under a drawing of six boxes, so paste,
## selection and screen input keep working. Red before the step: there is no res://scripts/hud/code_boxes.gd.

const SCRIPT := "res://scripts/hud/code_boxes.gd"


func _boxes() -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no code boxes").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var boxes: Control = auto_free((load(SCRIPT) as GDScript).new())
	add_child(boxes)
	await get_tree().process_frame
	return boxes


func test_typing_reads_as_a_code_and_the_value_has_no_hyphen() -> void:
	var boxes := await _boxes()
	if boxes == null:
		return
	var field := boxes.get("field") as LineEdit
	field.text = "abc123"
	field.text_changed.emit("abc123")
	assert_str(field.text).is_equal("ABC-123")
	assert_str(str(boxes.get("text"))).is_equal("ABC123")
	assert_vector(boxes.get_combined_minimum_size()).is_equal(Vector2(6 * 52 + 5 * 8 + 16, 62))


func test_the_control_is_one_focus_stop_and_enter_submits_the_code() -> void:
	var boxes := await _boxes()
	if boxes == null:
		return
	var stops := boxes.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c.focus_mode != Control.FOCUS_NONE)
	assert_int(stops.size()).is_equal(1)
	var got: Array = []
	boxes.connect("submitted", func(code: String) -> void: got.append(code))
	var field := boxes.get("field") as LineEdit
	field.text = "XYZ-789"
	field.text_submitted.emit(field.text)
	assert_array(got).is_equal(["XYZ789"])
