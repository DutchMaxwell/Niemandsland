extends GdUnitTestSuite
## E2E — the Privacy & data window, row 26 of the UI inventory (uimenus step 9): the overview (No thanks /
## Review details), the details page (fields, the byte-exact example preview, deletion code, the two-step
## accept, allow / withdraw, training toggle, Save example locally, Close), EN / DE words, Close hides it.
## privacy_consent_m10_test.gd pins consent and export bytes; this suite pins the controls a player uses.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

const MENU_SCENE := "res://scenes/privacy/privacy_menu.tscn"
const STORE := "user://e2e_privacy_menu_store.cfg"

var _menu: PrivacyMenu
var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	_menu = load(MENU_SCENE).instantiate() as PrivacyMenu
	add_child(_menu)
	_menu.set_store_path_for_tests(STORE)
	_menu.open_settings()
	await get_tree().process_frame


func after_test() -> void:
	_menu.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	TranslationServer.set_locale(_locale)


func _button(text: String) -> Button:
	for n: Node in _menu.find_children("*", "Button", true, false):
		if (n as Button).text == text and not n.is_queued_for_deletion():
			return n as Button
	return null


func _label_with(prefix: String) -> Label:
	for n: Node in _menu.find_children("*", "Label", true, false):
		if (n as Label).text.begins_with(prefix) and not n.is_queued_for_deletion():
			return n as Label
	return null


func _details() -> void:
	_button("Review details").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


func _details_missing() -> Array:
	var missing: Array = []
	for t: String in ["Save example locally", "Close", "Allow evaluation sharing"]:
		if _button(t) == null:
			missing.append("button: %s" % t)
	for name: String in ["ReviewedToggle", "AllowTrainingToggle", "ExamplePreview", "ExportStatus"]:
		if _menu.find_child(name, true, false) == null:
			missing.append("node: %s" % name)
	for prefix: String in ["Fields in the record:", "Never collected", "Destination:", "Deletion code: "]:
		if _label_with(prefix) == null:
			missing.append("label: %s" % prefix)
	return missing


func test_overview_has_heading_question_and_both_choices() -> void:
	assert_bool(_menu.visible).is_true()
	assert_object(_label_with("Help improve the computer opponent")).is_not_null()
	assert_object(_label_with("May Niemandsland share")).is_not_null()
	assert_object(_label_with("They can contain board setup")).is_not_null()
	assert_object(_button("No thanks")).is_not_null()
	assert_object(_button("Review details")).is_not_null()


func test_no_thanks_records_a_no_and_hides() -> void:
	_button("No thanks").pressed.emit()
	assert_bool(_menu.evaluation_sharing_enabled()).is_false()
	assert_bool(_menu.visible).is_false()


func test_details_page_has_every_control_and_the_byte_exact_example() -> void:
	await _details()
	assert_array(_details_missing()).override_failure_message("details controls missing: %s" % str(_details_missing())).is_empty()
	var preview := _menu.find_child("ExamplePreview", true, false) as TextEdit
	assert_str(preview.text).is_equal(_menu.example_bytes().get_string_from_utf8())
	assert_bool(preview.editable).is_false()
	assert_bool(_button("Allow evaluation sharing").disabled).is_true()
	assert_bool((_menu.find_child("AllowTrainingToggle", true, false) as CheckButton).disabled).is_true()


func test_two_step_accept_then_withdraw() -> void:
	await _details()
	var tick := _menu.find_child("ReviewedToggle", true, false) as CheckButton
	tick.button_pressed = true
	assert_bool(_button("Allow evaluation sharing").disabled).is_false()
	_button("Allow evaluation sharing").pressed.emit()
	assert_bool(_menu.evaluation_sharing_enabled()).is_true()
	assert_object(_button("Withdraw evaluation sharing")).is_not_null()
	assert_bool(tick.visible).is_false()
	assert_bool((_menu.find_child("AllowTrainingToggle", true, false) as CheckButton).disabled).is_false()
	_button("Withdraw evaluation sharing").pressed.emit()
	assert_bool(_menu.evaluation_sharing_enabled()).is_false()


func test_close_button_hides_the_window() -> void:
	await _details()
	_button("Close").pressed.emit()
	assert_bool(_menu.visible).is_false()


func test_escape_and_the_x_hide_the_panel() -> void:
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	_menu._unhandled_input(esc)
	assert_bool(_menu.visible).is_false()
	_menu.open_settings()
	(_menu.find_child("CloseButton", true, false) as Button).pressed.emit()
	assert_bool(_menu.visible).is_false()


func test_panel_is_house_style_and_owns_its_clicks() -> void:
	var root := _menu.get_child(0) as Control
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(root.theme).is_same(HouseStyle.theme())
	await _details()
	assert_str(String(_button("Allow evaluation sharing").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button("Save example locally").theme_type_variation)).is_equal(String(HouseStyle.BUTTON))


func test_german_words() -> void:
	assert_str(PrivacyMenu.text_for("de_DE", "title")).is_equal("Datenschutz & Daten")
	assert_str(PrivacyMenu.text_for("en", "no_thanks")).is_equal("No thanks")


func test_inventory_check_names_a_removed_control() -> void:
	await _details()
	assert_array(_details_missing()).is_empty()
	var close := _button("Close")
	var parent := close.get_parent()
	parent.remove_child(close)
	var missing := _details_missing()
	parent.add_child(close)
	assert_array(missing).contains_exactly(["button: Close"])
