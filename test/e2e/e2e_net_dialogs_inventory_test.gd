extends GdUnitTestSuite
## E2E — the online dialogs built by NetDialog, rows 24 and 50 of the UI inventory (uimenus step 8): Create a room
## / Join with a code (menu) and Public tables (NET-03). Every field, checkbox, button, header and status line
## of today's dialogs, and what each does. The probe swaps the scene change for a flag and the relay request of
## the room browser for a status line: no test here touches the network. NetDialog.build is also checked
## directly, since the in-game Host / Join dialogs (main.gd) use the same builder.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

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
	for t in _texts(d, "Label"):
		if t.begins_with(prefix):
			return true
	return false


func _host_missing(d: AcceptDialog) -> Array:
	var missing: Array = []
	for p: String in ["Create a room", "NET-01", "Your name:", "Relay server:", "Your invitation code appears"]:
		if not _has_label(d, p) and not _texts(d, "Label").any(func(t: String) -> bool: return t.to_upper().contains(p.to_upper())):
			missing.append("label: %s" % p)
	if not _texts(d, "CheckBox").has("List room publicly"):
		missing.append("checkbox: List room publicly")
	if d.ok_button_text != "Prepare table":
		missing.append("button: Prepare table")
	return missing


func test_create_a_room_dialog_has_every_field_and_reaches_the_table_chooser() -> void:
	_menu._on_host_online_pressed()
	await _frames(2)
	var d: AcceptDialog = _menu._host_popup
	assert_array(_host_missing(d)).override_failure_message("host dialog controls missing: %s" % str(_host_missing(d))).is_empty()
	assert_int(_menu._host_name_input.max_length).is_equal(PlayerIdentity.MAX_NAME_LEN)
	assert_str(_menu._relay_url_input.text).is_equal(InternetLobby.DEFAULT_RELAY_URL)
	assert_bool(_menu._host_public_check.button_pressed).is_false()
	d.confirmed.emit()
	await _frames(2)
	assert_object(_menu._table_setup).override_failure_message("Prepare table did not open the table chooser").is_not_null()


func test_join_dialog_has_every_field_and_keeps_an_unusable_code_open() -> void:
	_menu._on_join_online_pressed()
	await _frames(2)
	var d: AcceptDialog = _menu._join_popup
	for p: String in ["NET-02", "Your name:", "Invitation code:", "Relay server:"]:
		assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.contains(p))).override_failure_message("join dialog lost %s" % p).is_true()
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
	assert_bool(_menu.entered_game).override_failure_message("a usable code did not join").is_true()


func test_public_tables_has_fields_refresh_status_and_room_rows() -> void:
	_menu._on_browse_online_pressed()
	await _frames(2)
	var d: AcceptDialog = _menu._browse_popup
	assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.contains("NET-03"))).is_true()
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
	assert_bool(_texts(d, "Label").any(func(t: String) -> bool: return t.contains("NET-01"))).is_true()
	d.queue_free()


func test_all_three_dialogs_wear_the_house_chrome() -> void:
	_menu._on_host_online_pressed()
	_menu._on_join_online_pressed()
	_menu._on_browse_online_pressed()
	await _frames(2)
	for d: AcceptDialog in [_menu._host_popup, _menu._join_popup, _menu._browse_popup]:
		assert_object(d.theme).override_failure_message("%s is not in the house theme" % d.title).is_same(HouseStyle.theme())
		assert_str(String(d.get_ok_button().theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
		var head := NetDialog.content(d).get_child(0) as HBoxContainer
		assert_str(String((head.get_child(0) as Label).theme_type_variation)).is_equal(String(HouseStyle.EYEBROW))
	assert_str(String(_menu._join_error_label.get_theme_color(&"font_color").to_html())).is_equal(HouseStyle.tone_ink(HouseStyle.TONE_DANGER).to_html())
	var src := FileAccess.get_file_as_string("res://scripts/startup_menu.gd")
	assert_str(src).not_contains("HudTokens.TEXT_MUTED")
	assert_str(src).not_contains("HudTokens.DANGER")


func test_inventory_check_names_a_removed_control() -> void:
	_menu._on_host_online_pressed()
	await _frames(2)
	var d: AcceptDialog = _menu._host_popup
	assert_array(_host_missing(d)).is_empty()
	var check: CheckBox = _menu._host_public_check
	var parent := check.get_parent()
	parent.remove_child(check)
	var missing := _host_missing(d)
	parent.add_child(check)
	assert_array(missing).contains_exactly(["checkbox: List room publicly"])
