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
