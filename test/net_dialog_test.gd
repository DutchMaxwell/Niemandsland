extends GdUnitTestSuite
## NetDialog: the shared online Host/Join/Browse dialog chrome. Guards that the
## content node resolves (the MarginContainer gets a runtime auto-name, so a fixed
## node path would return null and adding fields would crash).

func test_build_returns_dialog() -> void:
	var dialog := NetDialog.build("HOST ONLINE", "NET-01", "Start")
	assert_object(dialog).is_not_null()
	assert_str(dialog.ok_button_text).is_equal("Start")
	dialog.free()


func test_content_resolves_and_accepts_fields() -> void:
	var dialog := NetDialog.build("JOIN ONLINE", "NET-02", "Join")
	var content := NetDialog.content(dialog)
	assert_object(content).is_not_null()  # the find_child fix — not null
	# Adding fields must not crash (the original bug: content was null).
	content.add_child(NetDialog.label("Player Name:"))
	content.add_child(NetDialog.line_edit("", "Your name"))
	assert_int(content.get_child_count()).is_greater_equal(3)  # header + 2 fields
	dialog.free()


func test_line_edit_and_label_carry_values() -> void:
	var lbl: Label = auto_free(NetDialog.label("Room Code:"))
	assert_str(lbl.text).is_equal("Room Code:")
	var edit: LineEdit = auto_free(NetDialog.line_edit("ABC", "hint"))
	assert_str(edit.text).is_equal("ABC")
	assert_str(edit.placeholder_text).is_equal("hint")
