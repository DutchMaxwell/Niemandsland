extends GdUnitTestSuite
## E2E — the after-game card "Share this game?", row 27 of the UI inventory (uimenus step 9). Keep private
## (default focus), Preview, Save locally, the status line, Esc = keep private, EN / DE words, no Share
## button and no network node. privacy_consent_m10_test.gd pins the consent and export bytes; this suite pins
## the card itself. test_inventory_check_names_a_removed_control proves the presence check can fail.

const WORDS := ["Keep private", "Preview", "Save locally"]

class StubMenu extends PrivacyMenu:
	var previews := 0
	var saved_to := ""
	func open_details() -> void:
		previews += 1
	func save_last_game_locally(path: String = "") -> String:
		saved_to = path
		return path
	func localized_text(key: String) -> String:
		return "saved: %s" if key == "saved_last" else key

var _card: AfterGameCard
var _menu: StubMenu
var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_menu = StubMenu.new()
	_card = AfterGameCard.new()
	add_child(_card)
	_card.export_path = "user://e2e_after_game_card.json"
	_card.open_for(_menu)
	await get_tree().process_frame


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	_card.queue_free()
	_menu.free()


func _button(text: String) -> Button:
	for n: Node in _card.find_children("*", "Button", true, false):
		if (n as Button).text == text and not n.is_queued_for_deletion():
			return n as Button
	return null


func _missing() -> Array:
	var missing: Array = []
	for t: String in WORDS:
		if _button(t) == null:
			missing.append("button: %s" % t)
	if _card.find_child("CardStatus", true, false) == null:
		missing.append("label: CardStatus")
	return missing


func test_every_control_is_on_the_card_and_keep_private_has_focus() -> void:
	assert_array(_missing()).override_failure_message("card controls missing: %s" % str(_missing())).is_empty()
	assert_bool(_card.visible).is_true()
	assert_object(_card.get_viewport().gui_get_focus_owner()).is_same(_button("Keep private"))
	assert_str((_card.find_child("CardStatus", true, false) as Label).text).is_empty()
	for n: Node in _card.find_children("*", "Button", true, false):
		assert_bool((n as Button).text.contains("Share")).is_false()


func test_words_come_in_english_and_german() -> void:
	assert_str(AfterGameCard.text_for("en_US", "card_title")).is_equal("Share this game?")
	assert_str(AfterGameCard.text_for("de_DE", "save_locally")).is_equal("Lokal speichern")
	assert_str(AfterGameCard.text_for("de", "keep_private")).is_equal("Privat behalten")


func test_keep_private_and_escape_hide_the_card_and_write_nothing() -> void:
	_button("Keep private").pressed.emit()
	assert_bool(_card.visible).is_false()
	assert_str(_menu.saved_to).is_empty()
	_card.open_for(_menu)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	_card._unhandled_input(esc)
	assert_bool(_card.visible).is_false()
	assert_str(_menu.saved_to).is_empty()


func test_preview_hands_over_to_the_details_page_and_hides() -> void:
	_button("Preview").pressed.emit()
	assert_bool(_card.visible).is_false()
	assert_int(_menu.previews).is_equal(1)


func test_save_locally_saves_to_the_export_path_and_names_it() -> void:
	_button("Save locally").pressed.emit()
	assert_str(_menu.saved_to).is_equal("user://e2e_after_game_card.json")
	assert_str((_card.find_child("CardStatus", true, false) as Label).text).is_equal("saved: user://e2e_after_game_card.json")


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing()).is_empty()
	var preview := _button("Preview")
	var parent := preview.get_parent()
	parent.remove_child(preview)
	var missing := _missing()
	parent.add_child(preview)
	assert_array(missing).contains_exactly(["button: Preview"])
