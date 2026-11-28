extends GdUnitTestSuite
## The online hub of the main menu (step 47.1): one page with the player's name and "Create a room". Red before the step: there is no res://scripts/online_hub.gd.

const SCRIPT := "res://scripts/online_hub.gd"


func _hub() -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no online hub").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var hub: Control = (load(SCRIPT) as GDScript).new()
	hub.set("lists_on_open", false)   # no request to the production relay from a test
	host.add_child(hub)
	hub.size = host.size
	await get_tree().process_frame
	return hub


func _settings_on_prepare(hub: Control) -> Dictionary:
	var got: Array = []
	hub.connect("host_requested", func(settings: Dictionary) -> void: got.append(settings))
	(hub.get("prepare_button") as Button).pressed.emit()
	return got[0] if not got.is_empty() else {}


func test_prepare_table_hands_over_the_name_the_relay_and_the_public_check() -> void:
	var hub := await _hub()
	if hub == null:
		return
	(hub.get("name_field") as LineEdit).text = "  Ashfall  "
	(hub.get("public_check") as CheckBox).button_pressed = true
	var settings := _settings_on_prepare(hub)
	assert_bool(bool(settings.get("niemandsland/pending_internet_lobby", false))).is_true()
	assert_bool(bool(settings.get("niemandsland/internet_is_host", false))).is_true()
	assert_str(str(settings.get("niemandsland/player_name", ""))).is_equal(PlayerIdentity.sanitize("  Ashfall  "))
	assert_str(str(settings.get("niemandsland/internet_relay_url", ""))).is_equal(InternetLobby.DEFAULT_RELAY_URL)
	assert_bool(bool(settings.get("niemandsland/internet_public", false))).is_true()


func test_enter_in_the_name_field_prepares_the_table() -> void:
	var hub := await _hub()
	if hub == null:
		return
	var got: Array = []
	hub.connect("host_requested", func(settings: Dictionary) -> void: got.append(settings))
	var name_field := hub.get("name_field") as LineEdit
	name_field.text_submitted.emit(name_field.text)
	assert_int(got.size()).is_equal(1)


## Step 47.1b: one folded relay line for every function of the page; an emptied field gives the default address.
func test_the_relay_field_stays_folded_until_its_line_is_pressed() -> void:
	var hub := await _hub()
	if hub == null:
		return
	var field := hub.get("relay_field") as LineEdit
	assert_object(field).override_failure_message("no relay field").is_not_null()
	if field == null:
		return
	assert_bool(field.is_visible_in_tree()).is_false()
	(hub.get("relay_line") as Button).pressed.emit()
	assert_bool(field.is_visible_in_tree()).is_true()
	field.text = "wss://example.invalid"
	assert_str(str(_settings_on_prepare(hub).get("niemandsland/internet_relay_url", ""))).is_equal(
		"wss://example.invalid")


func test_an_emptied_relay_field_gives_the_default_address() -> void:
	var hub := await _hub()
	if hub == null or hub.get("relay_field") == null:
		fail("no relay field")
		return
	(hub.get("relay_field") as LineEdit).text = "   "
	var settings := _settings_on_prepare(hub)
	assert_str(str(settings.get("niemandsland/internet_relay_url", ""))).is_equal(InternetLobby.DEFAULT_RELAY_URL)


func _join(hub: Control) -> Dictionary:
	return {"boxes": hub.get("code_boxes"), "button": hub.get("join_button"), "error": hub.get("join_error")}


## Step 47.2b: "Join with a code" - Join is off below six characters; Enter with a short code says why and emits
## nothing; six characters join without the hyphen; the error goes with the next keystroke (red before: no block).
func test_join_with_a_code() -> void:
	var hub := await _hub()
	if hub == null:
		return
	var parts := _join(hub)
	assert_object(parts.boxes).override_failure_message("no join block").is_not_null()
	if parts.boxes == null:
		return
	var field: LineEdit = parts.boxes.field
	var got: Array = []
	hub.connect("join_requested", func(code: String, url: String, _n: String, _b: Button) -> void:
		got.append([code, url]))
	field.text = "ab1"
	field.text_changed.emit("ab1")
	assert_bool((parts.button as Button).disabled).is_true()
	field.text_submitted.emit(field.text)
	assert_bool((parts.error as Label).visible).is_true()
	assert_str((parts.error as Label).text).is_equal("An invitation code has 6 characters, for example ABC-123.")
	assert_array(got).is_empty()
	field.text = "ab1c23"
	field.text_changed.emit("ab1c23")
	assert_bool((parts.error as Label).visible).is_false()
	assert_bool((parts.button as Button).disabled).is_false()
	assert_str(String((parts.button as Button).theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	field.text_submitted.emit(field.text)
	assert_array(got).is_equal([["AB1C23", InternetLobby.DEFAULT_RELAY_URL]])



func _rows(hub: Control) -> Array:
	var rows := hub.find_child("RoomRows", true, false)
	return [] if rows == null else rows.get_children().filter(func(r: Node) -> bool: return r.name.begins_with("Room"))


## Step 47.3a: the public list draws what the relay answers (red before: no list).
func test_the_public_list_shows_one_row_per_room_and_the_count() -> void:
	var hub := await _hub()
	if hub == null:
		return
	assert_bool(hub.has_method("_on_rooms")).override_failure_message("no public list").is_true()
	if not hub.has_method("_on_rooms"):
		return
	hub.call("_on_rooms", [{"code": "ABC123", "players": 1}, {"code": "KLM456", "players": 2}], hub.get("_gen"))
	var rows := _rows(hub)
	assert_int(rows.size()).is_equal(2)
	assert_str((hub.get("count_label") as Label).text).is_equal("2 games online")
	var pips: Array = (rows[0] as Node).find_children("Pip*", "Panel", true, false)
	assert_int(pips.size()).is_equal(8)
	assert_int(pips.filter(func(p: Panel) -> bool: return bool(p.get_meta("filled", false))).size()).is_equal(1)
	assert_array(_texts_of(rows[0])).contains(["ABC-123", "1 / 8 players"])
	hub.call("_on_rooms", [], hub.get("_gen"))
	assert_int(_rows(hub).size()).is_equal(0)
	assert_str((hub.get("status_label") as Label).text).is_equal("0 games online right now.")


func _texts_of(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)



## Step 47.3b: one request kind from a fresh listing lobby; a reply of an older request changes nothing; a failure
## shows the relay's reason; the listing lobby goes with the page (red before: no refresh).
func test_requests_generations_and_clean_up() -> void:
	var hub := await _hub()
	if hub == null:
		return
	assert_bool(hub.has_method("refresh")).override_failure_message("no requests").is_true()
	if not hub.has_method("refresh"):
		return
	(hub.get("relay_field") as LineEdit).text = "ws://127.0.0.1:9"   # a closed local port, never the real relay
	hub.call("refresh")
	var old: int = hub.get("_gen")
	hub.call("refresh")
	hub.call("_on_rooms", [{"code": "ABC123", "players": 1}], old)
	assert_int(_rows(hub).size()).is_equal(0)
	assert_str((hub.get("status_label") as Label).text).is_equal("Loading rooms…")
	hub.call("_on_failed", "relay says no", hub.get("_gen"))
	assert_str((hub.get("status_label") as Label).text).is_equal("relay says no")
	var lobby: Node = hub.get("_lobby")
	assert_object(lobby).is_not_null()
	hub.get_parent().remove_child(hub)
	await get_tree().process_frame
	assert_bool(is_instance_valid(lobby)).override_failure_message("the listing lobby outlived the page").is_false()
	hub.free()


## Step 47.8: Tab walks the hub in reading order - way back, name, the check, Prepare table, the code, Join, the
## relay line, refresh, then the rows' Join buttons - and wraps (red before: the engine's own order).
func test_tab_walks_the_hub_in_reading_order() -> void:
	var hub := await _hub()
	if hub == null:
		return
	hub.call("_on_rooms", [{"code": "ABC123", "players": 1}, {"code": "KLM456", "players": 2}], hub.get("_gen"))
	await get_tree().process_frame
	var expected: Array = [hub.get("back"), hub.get("name_field"), hub.get("public_check"), hub.get("prepare_button"),
		(hub.get("code_boxes") as CodeBoxes).field, hub.get("join_button"), hub.get("relay_line"),
		hub.find_child("Refresh", true, false)]
	for row: Node in _rows(hub):
		expected.append(row.find_children("*", "Button", true, false)[0])
	var order: Array = []
	var at := hub.get("back") as Control
	for _i in expected.size() + 1:
		order.append(at)
		at = at.get_node_or_null(at.focus_next) if not at.focus_next.is_empty() else null
		if at == null:
			break
	assert_array(order).is_equal(expected + [hub.get("back")])


## Gap review 27.11. (sheet 02): the first room is the chosen one - filled, its Join gold -, the refresh button is 44 px
## and an info line stands under the list (red before: bare rows, a 32 px icon, no line).
func test_the_chosen_room_is_filled_and_refresh_is_44_px() -> void:
	var hub := await _hub()
	if hub == null:
		return
	hub.call("_on_rooms", [{"code": "ABC123", "players": 1}, {"code": "KLM456", "players": 2}], hub.get("_gen"))
	var rows := _rows(hub)
	assert_bool(rows[0] is PanelContainer).override_failure_message("a room row has no box").is_true()
	if not rows[0] is PanelContainer:
		return
	var box := (rows[0] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_bool(box != null and box.bg_color == HouseStyle.ROW_HOVER).is_true()
	assert_str(String(((rows[0] as Node).find_child("Join", true, false) as Button).theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(((rows[1] as Node).find_child("Join", true, false) as Button).theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_float((hub.find_child("Refresh", true, false) as Control).custom_minimum_size.x).is_equal(44.0)
	assert_array(_texts_of(hub)).contains(["The list shows what the relay reports today: a code and its player count."])


## Sheet 02: the name field is 46 px high as the mockups' field (red before: 38 px).
func test_the_name_field_is_46_px() -> void:
	var hub := await _hub()
	if hub == null:
		return
	await get_tree().process_frame
	assert_float((hub.get("name_field") as Control).size.y).is_greater_equal(46.0)


## The Join button's Enter cap never covers its word (seen on the 28.11. capture after the menu buttons took the
## mockups' 18 px padding and 17 px text: "Join" ran under the cap; red before).
func test_join_keeps_its_word_clear_of_the_enter_cap() -> void:
	var hub := await _hub()
	if hub == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var join := hub.find_child("JoinWithCode", true, false) as Button
	var cap := join.get_child(0) as Control
	var font := join.get_theme_font(&"font")
	var text_end := join.get_theme_stylebox(&"normal").content_margin_left \
		+ font.get_string_size(join.text, HORIZONTAL_ALIGNMENT_LEFT, -1, join.get_theme_font_size(&"font_size")).x
	assert_float(cap.position.x).override_failure_message("cap at %d, word ends at %d" % [int(cap.position.x), int(text_end)]) \
		.is_greater_equal(text_end + 4.0)
	var block := join.get_parent().get_parent() as Control
	assert_float(join.get_global_rect().end.x).is_less_equal(block.get_global_rect().end.x + 1.0)
