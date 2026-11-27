extends GdUnitTestSuite
## E2E — the online dialogs built by NetDialog, rows 24 and 50 of the UI inventory (uimenus step 8): Join with a
## code (menu) and Public tables (NET-03); Create a room became the online hub (test/online_hub_test.gd). Every field, checkbox, button, header and status line
## of today's dialogs, and what each does. The probe swaps the scene change for a flag and the relay request of
## the room browser for a status line: no test here touches the network. NetDialog.build is also checked
## directly, since the in-game Host / Join dialogs (main.gd) use the same builder.

class MenuProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _transition_to_game() -> void:
		entered_game = true
	func _refresh_browse_list() -> void:
		_set_browse_status("Loading rooms…")

var _menu: Control
var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_menu = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	_menu.set_script(MenuProbe)
	add_child(_menu)
	await _frames(2)


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	_menu = null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _texts(d: Node, kind: String) -> Array[String]:
	var out: Array[String] = []
	for n: Node in d.find_children("*", kind, true, false):
		if not n.is_queued_for_deletion():
			out.append(n.text)
	return out


func _has_label(d: Node, prefix: String) -> bool:
	for t in _texts(d, "Label") + _texts(d, "Button"):
		if t.begins_with(prefix):
			return true
	return false


func test_join_dialog_has_every_field_and_keeps_an_unusable_code_open() -> void:
	_menu._on_join_online_pressed()
	await _frames(2)
	var d: AcceptDialog = _menu._join_popup
	for p: String in ["Your name:", "Invitation code:", "Relay server:"]:
		assert_bool((_texts(d, "Label") + _texts(d, "Button")).any(func(t: String) -> bool: return t.contains(p))).override_failure_message("join dialog lost %s" % p).is_true()
	assert_str(d.ok_button_text).is_equal("Join")
	assert_int(_menu._join_code_input.max_length).is_equal(7)
	assert_str(_menu._join_code_input.placeholder_text).is_equal("ABC-123")
	assert_bool(_menu._join_error_label.visible).is_false()
	_menu._join_code_input.text = "AB"
	d.confirmed.emit()
	assert_bool(_menu._join_error_label.visible).is_true()
	assert_bool(d.visible).is_true()
	_menu._join_code_input.text = "ABC-123"
	d.confirmed.emit()
	await get_tree().create_timer(HudTokens.DUR_COMMIT + 0.1).timeout   # the commit beat, then the screen change
	assert_bool(_menu.entered_game).override_failure_message("a usable code did not join").is_true()


func test_public_tables_has_fields_refresh_status_and_room_rows() -> void:
	_menu._on_browse_online_pressed()
	await _frames(2)
	var d: AcceptDialog = _menu._browse_popup
	assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.contains("NET-0"))).is_false()
	assert_str(d.ok_button_text).is_equal("Close")
	assert_bool(_texts(d, "Button").has("Refresh list")).is_true()
	assert_bool(_texts(d, "Label").has("Loading rooms…")).is_true()
	_menu._on_browse_rooms_received([])
	await _frames(2)
	assert_bool(_texts(d, "Label").has("0 games online right now.")).is_true()
	_menu._on_browse_rooms_received([{"code": "ABC123", "players": 2}])
	await _frames(2)
	assert_bool(_texts(d, "Label").has("1 game online:")).is_true()
	assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.begins_with("ABC-123"))).is_true()
	var join := d.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "Join")
	assert_int(join.size()).is_equal(1)
	(join[0] as Button).pressed.emit()
	assert_bool(_menu.entered_game).is_true()


func test_room_browser_failure_shows_its_reason() -> void:
	_menu._on_browse_online_pressed()
	await _frames(2)
	_menu._on_browse_failed("Could not reach the relay (timed out).")
	await _frames(2)
	assert_bool(_texts(_menu._browse_popup, "Label").has("Could not reach the relay (timed out).")).is_true()


func test_net_dialog_builder_gives_the_in_game_dialogs_header_and_content() -> void:
	var d := NetDialog.build("HOST ONLINE GAME", "NET-01", "Start Hosting")
	add_child(d)
	assert_object(NetDialog.content(d)).is_not_null()
	assert_str(d.ok_button_text).is_equal("Start Hosting")
	assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.contains("NET-0"))).is_false()
	d.queue_free()


func test_all_three_dialogs_wear_the_house_chrome() -> void:
	_menu._on_join_online_pressed()
	_menu._on_browse_online_pressed()
	await _frames(2)
	for d: AcceptDialog in [_menu._join_popup, _menu._browse_popup]:
		assert_object(d.theme).override_failure_message("%s is not in the house theme" % d.title).is_same(HouseStyle.menu_theme())
		assert_str(String(d.get_ok_button().theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
		var head := NetDialog.content(d).get_child(0) as HBoxContainer
		assert_str(String((head.get_child(0) as Label).theme_type_variation)).is_equal(String(HouseStyle.EYEBROW))
	assert_str(String(_menu._join_error_label.get_theme_color(&"font_color").to_html())).is_equal(HouseStyle.tone_ink(HouseStyle.TONE_DANGER).to_html())
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu.gd")
	assert_str(src).not_contains("HudTokens.TEXT_MUTED")
	assert_str(src).not_contains("HudTokens.DANGER")


## The code field reads as a code: upper case as you type, the hyphen after the third character, mono 30 px.
## RED on main: the typed text stayed as typed and the field was 24 px in the text font.
func test_join_code_field_reads_as_a_code() -> void:
	var net: GDScript = load("res://scripts/net_dialog.gd")
	assert_bool(net.has_method("code_as_typed")).override_failure_message("no code formatting").is_true()
	if net.has_method("code_as_typed"):
		for pair: Array in [["abc123", "ABC-123"], ["ab", "AB"], ["abc", "ABC"], ["abcd", "ABC-D"],
				["a-b c12 3x", "ABC-123"], ["", ""]]:
			assert_str(net.call("code_as_typed", pair[0])).is_equal(pair[1])
	_menu._on_join_online_pressed()
	await _frames(2)
	var field: LineEdit = _menu._join_code_input
	field.text = "abcd"
	field.text_changed.emit("abcd")
	assert_str(field.text).override_failure_message("the code was not formatted as typed").is_equal("ABC-D")
	assert_int(field.get_theme_font_size("font_size")).is_equal(30)
	assert_object(field.get_theme_font("font")).is_same(HouseStyle.mono())
	assert_str(field.placeholder_text).is_equal("ABC-123")


func _relay_toggle(d: Node) -> Button:
	for n: Node in d.find_children("*", "Button", true, false):
		if (n as Button).text.begins_with("Relay server:"):
			return n as Button
	return null


## The relay address is folded away in all three online windows and opens on its row; its default text and
## the way it is read are unchanged. RED on main: the field stood open under its label.
func test_relay_address_is_folded_away_in_the_three_online_windows() -> void:
	_menu._on_join_online_pressed()
	_menu._on_browse_online_pressed()
	await _frames(2)
	var rows := [[_menu._join_popup, _menu._join_relay_url_input],
		[_menu._browse_popup, _menu._browse_url_input]]
	for row: Array in rows:
		var dialog: AcceptDialog = row[0]
		var field: LineEdit = row[1]
		var toggle := _relay_toggle(dialog)
		assert_object(toggle).override_failure_message("%s has no Relay server row" % dialog.title).is_not_null()
		if toggle == null:
			continue
		assert_bool(field.visible).override_failure_message("%s shows the relay address" % dialog.title).is_false()
		assert_str(field.text).is_equal(InternetLobby.DEFAULT_RELAY_URL)
		toggle.pressed.emit()
		assert_bool(field.visible).is_true()
		toggle.pressed.emit()
		assert_bool(field.visible).is_false()



## A working index never stands on a player's screen, and the three online windows join the menu's family: a close box in
## the header and a scrim that dims the menu while one is open (red on main: "NET-01..03" labels, no scrim, no close box).
func test_the_online_windows_show_no_working_codes_and_dim_the_menu() -> void:
	var regex := RegEx.create_from_string("NET-\\d+")
	_menu._on_join_online_pressed()
	_menu._on_browse_online_pressed()
	await _frames(2)
	for d: AcceptDialog in [_menu._join_popup, _menu._browse_popup]:
		for text in _texts(d, "Label") + _texts(d, "Button"):
			assert_bool(regex.search(text) != null).override_failure_message("%s shows %s" % [d.title, text]).is_false()
		assert_object(d.find_child("CloseButton", true, false)).override_failure_message("%s has no close box" % d.title).is_not_null()
	var scrims := _menu.get_children().filter(func(n: Node) -> bool: return n is ColorRect and n.name == "DialogScrim" and n.visible)
	assert_int(scrims.size()).override_failure_message("no scrim over the menu").is_greater(0)
