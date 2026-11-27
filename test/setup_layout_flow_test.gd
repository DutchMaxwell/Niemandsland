extends GdUnitTestSuite
## Step 04 in the table setup (step 65.7): the menu's setup shows the row "04 Lay out the table", which opens the
## page of the four ways; Create table from there hands the layout to the table. The table's own direct chooser
## keeps today's page. Red before the step: no row, no flag.

const KEY := "niemandsland/pending_table_layout"

var _prev: Variant


func before_test() -> void:
	_prev = ProjectSettings.get_setting(KEY, null)


func after_test() -> void:
	ProjectSettings.set_setting(KEY, _prev)


func _dialog(with_step: bool) -> TableSizeDialog:
	var dialog: TableSizeDialog = auto_free(TableSizeDialog.new())
	dialog.set("layout_step", with_step)
	add_child(dialog)
	return dialog


func test_the_menus_setup_has_the_row_and_the_direct_chooser_does_not() -> void:
	assert_object(_dialog(true).find_child("LayoutRow", true, false)).override_failure_message("no row 04").is_not_null()
	assert_object(_dialog(false).find_child("LayoutRow", true, false)).is_null()


func test_the_row_opens_the_four_ways_and_create_hands_the_layout_over() -> void:
	var dialog := _dialog(true)
	var row := dialog.find_child("LayoutRow", true, false) as Button
	if row == null:
		fail("no row 04")
		return
	row.pressed.emit()
	await get_tree().process_frame
	var way := dialog.find_child("Way_generated", true, false) as Button
	assert_bool(way != null and way.is_visible_in_tree()).override_failure_message("no way cards").is_true()
	var biome: Button = dialog._biome_buttons.values()[0]
	assert_bool(biome.is_visible_in_tree()).override_failure_message("the biome cards still show").is_false()
	way.pressed.emit()
	var chosen: Array = []
	dialog.size_chosen.connect(func(feet: Vector2) -> void: chosen.append(feet))
	(dialog.find_child("CreateTable", true, false) as Button).pressed.emit()
	assert_int(chosen.size()).is_equal(1)
	dialog.get("layout").call("commit")   # what the menu does on size_chosen
	assert_str(str((ProjectSettings.get_setting(KEY, {}) as Dictionary).get("path", ""))).is_not_empty()


## Spec 97 (step 97.8): the row of state one reads "05   Lay out the table" (red before: "04").
func test_the_layout_row_is_step_05() -> void:
	var row := _dialog(true).find_child("LayoutRow", true, false) as Button
	var texts: Array = row.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["05   Lay out the table"])
