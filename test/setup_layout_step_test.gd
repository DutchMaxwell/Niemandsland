extends GdUnitTestSuite
## Step 04's page (step 65.5): the folded rows of steps 01-03 and the heading.
## Red before the step: there is no res://scripts/setup_layout_step.gd.

const SCRIPT := "res://scripts/setup_layout_step.gd"

var _layout: SetupLayout


func _step(size_feet: Vector2) -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no step 04 page").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	_layout = auto_free(SetupLayout.new())
	add_child(_layout)
	_layout.set_table(size_feet, "gf")
	var step: Control = auto_free((load(SCRIPT) as GDScript).new())
	step.size = Vector2(1920, 1080)
	add_child(step)
	step.call("setup", _layout, ["Grimdark Future", "Urban ruins", "72 × 48 in"])
	return step


func _way(step: Control, way: String) -> Button:
	return step.find_child("Way_" + way, true, false) as Button


func test_change_on_a_folded_row_asks_for_that_step() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var asked: Array = []
	step.connect("change_requested", func(index: int) -> void: asked.append(index))
	(step.find_child("Change2", true, false) as Button).pressed.emit()
	assert_array(asked).is_equal([2])


func test_the_folded_rows_show_the_values_of_steps_01_to_03() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var texts: Array = step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["01", "Game system", "Grimdark Future", "72 × 48 in", "Lay out the table"])


## Step 65.5b: the four ways as cards (red before: no cards).
func test_four_ways_and_the_default_is_chosen() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	for way: String in ["empty", "generated", "theme", "file"]:
		assert_object(_way(step, way)).override_failure_message(way).is_not_null()
	if _way(step, "empty") == null:
		return
	assert_bool(bool(_way(step, SetupLayout.DEFAULT_WAY).get_meta("chosen", false))).is_true()
	assert_bool(_way(step, "theme").disabled).is_false()


func test_the_ready_made_table_is_off_on_4_by_4_and_a_press_chooses_a_way() -> void:
	var step := _step(Vector2(4, 4))
	if step == null or _way(step, "theme") == null:
		fail("no way cards")
		return
	assert_bool(_way(step, "theme").disabled).is_true()
	_way(step, "generated").pressed.emit()
	assert_str(_layout.label()).is_equal("Auto-generated")
	assert_bool(bool(_way(step, "generated").get_meta("chosen", false))).is_true()
	assert_bool(bool(_way(step, "empty").get_meta("chosen", false))).is_false()
