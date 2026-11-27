extends GdUnitTestSuite
## The invite card at the table (step 49.2): the room's code, Copy code, Keep setting up, Esc.
## Red before the step: there is no res://scripts/hud/invite_card.gd.

const SCRIPT := "res://scripts/hud/invite_card.gd"


func _card() -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no invite card").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var card: Control = auto_free((load(SCRIPT) as GDScript).new())
	add_child(card)
	card.call("open", "ABC123", "Multiplayer is manual play.")
	await get_tree().process_frame
	return card


func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func test_the_card_shows_the_code_as_read() -> void:
	var card := await _card()
	if card == null:
		return
	assert_array(_texts(card)).contains(["YOUR ROOM", "Invite your group.", "INVITATION CODE", "ABC-123"])
	assert_bool(card.visible).is_true()


func test_copy_code_puts_the_code_on_the_clipboard_and_says_so() -> void:
	var card := await _card()
	if card == null:
		return
	var before := DisplayServer.clipboard_get()
	var copy := card.find_child("CopyCode", true, false) as Button
	copy.pressed.emit()
	var copied := DisplayServer.clipboard_get()
	DisplayServer.clipboard_set(before)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):   # the headless server keeps no clipboard
		assert_str(copied).is_equal("ABC123")
	assert_str(copy.text).is_equal("Copied")


func test_keep_setting_up_and_esc_close_the_card() -> void:
	var card := await _card()
	if card == null:
		return
	(card.find_child("KeepSettingUp", true, false) as Button).pressed.emit()
	assert_bool(card.visible).is_false()
	card.call("open", "ABC123", "")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	card.get_viewport().push_input(esc)
	await get_tree().process_frame
	assert_bool(card.visible).is_false()
