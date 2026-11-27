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


## Spec 97 (step 97.10): step 04 "Who is at the table?" in the setup - its row in state one, the who page, Esc back,
## row 04 of the layout page to the who page, Create table from all three states; the direct chooser has none of it.
const MANIFEST := {"alien_hives": {"name": "Alien Hives", "lists": [{"points": 3000, "file": "alien_hives_3000.json"}]}}


func _visible(dialog: Node, node_name: String) -> bool:
	var node := dialog.find_child(node_name, true, false) as Control
	return node != null and node.is_visible_in_tree() and not node.is_queued_for_deletion()


func _esc(dialog: TableSizeDialog) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	dialog._unhandled_key_input(key)


func test_the_opponent_row_names_the_choice_and_opens_the_who_page() -> void:
	var dialog := _dialog(true)
	var row := dialog.find_child("OpponentRow", true, false) as Button
	assert_object(row).override_failure_message("no row 04").is_not_null()
	if row == null:
		return
	var texts: Array = row.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["04   Who is at the table?", "Two players, one screen"])
	dialog.opponent.set_manifest(MANIFEST)
	assert_array(row.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)).contains(
		["NACHTMAHR · Alien Hives · 3000"])
	row.pressed.emit()
	await get_tree().process_frame
	assert_bool(_visible(dialog, "Who_solo")).override_failure_message("no who page").is_true()
	_esc(dialog)
	await get_tree().process_frame
	assert_bool(_visible(dialog, "Who_solo")).is_false()
	assert_bool(_visible(dialog, "OpponentRow")).override_failure_message("Esc did not return").is_true()


func test_row_04_of_the_layout_page_opens_the_who_page_and_back() -> void:
	var dialog := _dialog(true)
	if dialog.find_child("OpponentRow", true, false) == null:
		fail("no row 04")
		return
	(dialog.find_child("LayoutRow", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	(dialog.find_child("Change4", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_bool(_visible(dialog, "Who_solo")).is_true()
	assert_bool(_visible(dialog, "Way_generated")).is_false()
	(dialog.find_child("LayoutRow", true, false) as Button).pressed.emit()   # the who page's row 05
	await get_tree().process_frame
	assert_bool(_visible(dialog, "Way_generated")).is_true()


func test_create_works_from_every_state() -> void:
	for state: String in ["", "who", "layout"]:
		var dialog := _dialog(true)
		if dialog.find_child("OpponentRow", true, false) == null:
			fail("no row 04")
			return
		var chosen: Array = []
		dialog.size_chosen.connect(func(feet: Vector2) -> void: chosen.append(feet))
		if not state.is_empty():
			dialog._show_state(state)
			await get_tree().process_frame
		for button: Button in dialog.find_children("CreateTable", "Button", true, false):
			if button.is_visible_in_tree() and not button.is_queued_for_deletion():
				button.pressed.emit()
		if state.is_empty():
			dialog._confirm()
		assert_int(chosen.size()).override_failure_message("state '%s'" % state).is_equal(1)


func test_the_direct_chooser_has_no_opponent_row() -> void:
	var dialog := _dialog(false)
	assert_object(dialog.find_child("OpponentRow", true, false)).is_null()
	assert_object(dialog.opponent).is_null()
