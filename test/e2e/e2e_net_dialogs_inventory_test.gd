extends GdUnitTestSuite
## E2E — the online dialogs built by NetDialog, rows 24 and 50 of the UI inventory (uimenus step 8). The menu's
## three online windows (Create a room, Join with a code, Public tables) became the online hub
## (test/online_hub_test.gd); NetDialog stays the builder of the two windows the table opens (Host / Join from
## the game menu, main.gd), and its code formatting is what the hub's code boxes type with.


func _texts(d: Node, kind: String) -> Array[String]:
	var out: Array[String] = []
	for n: Node in d.find_children("*", kind, true, false):
		if not n.is_queued_for_deletion():
			out.append(n.text)
	return out


func test_net_dialog_builder_gives_the_in_game_dialogs_header_and_content() -> void:
	var d := NetDialog.build("HOST ONLINE GAME", "NET-01", "Start Hosting")
	add_child(d)
	assert_object(NetDialog.content(d)).is_not_null()
	assert_str(d.ok_button_text).is_equal("Start Hosting")
	assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.contains("NET-0"))).is_false()
	d.queue_free()


## The code reads as a code: upper case as you type, letters and digits, six at most, the hyphen after the third.
func test_a_code_is_formatted_as_typed() -> void:
	for pair: Array in [["abc123", "ABC-123"], ["ab", "AB"], ["abc", "ABC"], ["abcd", "ABC-D"],
			["a-b c12 3x", "ABC-123"], ["", ""]]:
		assert_str(NetDialog.code_as_typed(pair[0])).is_equal(pair[1])


## The menu's script keeps no colour literal of the June layer (its online windows used them).
func test_the_menu_defines_no_colour_literals() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu.gd")
	assert_str(src).not_contains("HudTokens.TEXT_MUTED")
	assert_str(src).not_contains("HudTokens.DANGER")
