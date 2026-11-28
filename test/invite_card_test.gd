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


## Step 49.2b: the session's caption under the buttons, a click on the dimmed table closes the card, the focus
## opens on Copy code (red before: no caption, the scrim ignored the click).
func test_caption_scrim_click_and_first_focus() -> void:
	var card := await _card()
	if card == null:
		return
	await get_tree().process_frame
	assert_array(_texts(card)).contains(["Multiplayer is manual play."])
	assert_object(card.get_viewport().gui_get_focus_owner()).is_same(card.find_child("CopyCode", true, false))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(card.get_child(0) as Control).gui_input.emit(click)
	assert_bool(card.visible).is_false()


class StubMain extends Node:
	var network_manager: Node
	var starts := 0
	func _peer_display_name(peer_id: int) -> String:
		return "Player %d" % peer_id
	func _get_player_color(_peer_id: int) -> Color:
		return HouseStyle.ACCENT
	func _on_start_game_pressed() -> void:
		starts += 1


func _hosted_card(host: bool) -> Array:
	var nm: Node = auto_free(load("res://scripts/network_manager.gd").new())
	add_child(nm)
	nm.is_host = host
	var main: StubMain = auto_free(StubMain.new())
	main.network_manager = nm
	add_child(main)
	var card := await _card()
	if card == null or not card.has_method("setup"):
		fail("no players on the card")
		return []
	card.call("setup", main)
	return [card, nm, main]


func _player_rows(card: Control) -> Array:
	return card.find_children("Player*", "PanelContainer", true, false)


## Step 49.3: the players at the table and Ready (red before: no setup).
func test_the_host_sees_the_seats_and_their_ready_tags() -> void:
	var parts := await _hosted_card(true)
	if parts.is_empty():
		return
	var card: Control = parts[0]
	var nm: Node = parts[1]
	assert_int(_player_rows(card).size()).is_equal(1)
	assert_array(_texts(card)).contains(["(you, host)", "AT THE TABLE · 1 / 8", "Waiting for a player …"])
	nm.connected_peers.append(10)
	nm.validated_peers[10] = true
	nm.peer_to_slot[10] = 2
	nm.player_connected.emit(10)
	assert_int(_player_rows(card).size()).is_equal(2)
	nm._host_record_ready(2, true)
	assert_array(_texts(_player_rows(card)[1])).contains(["Ready"])
	assert_array(_texts(_player_rows(card)[0])).contains(["Not ready"])


func test_a_guest_sees_a_tag_on_its_own_row_only_and_ready_calls_the_game() -> void:
	var parts := await _hosted_card(false)
	if parts.is_empty():
		return
	var card: Control = parts[0]
	var nm: Node = parts[1]
	nm.connected_peers.append(5)   # another guest (the offline peer is id 1 = this client)
	nm.player_connected.emit(5)
	var rows := _player_rows(card)
	assert_int(rows.size()).is_equal(2)
	var tags := rows.map(func(r: Node) -> bool: return _texts(r).has("Not ready") or _texts(r).has("Ready"))
	assert_array(tags).is_equal([true, false])   # own row first; another player's flag is unknown to a guest
	(card.find_child("ReadyButton", true, false) as Button).pressed.emit()
	assert_int((parts[2] as StubMain).starts).is_equal(1)


## Gap review 27.11. (sheet 02b): the empty seat is a dashed frame without the card's solid box, and the ready tag is a
## bordered chip (red before: a solid card, bare mono text).
func test_the_empty_seat_is_dashed_and_the_tag_is_a_chip() -> void:
	var parts := await _hosted_card(true)
	if parts.is_empty():
		return
	var card: Control = parts[0]
	var seat := card.find_child("WaitingSeat", true, false) as PanelContainer
	assert_object(seat).override_failure_message("no dashed seat").is_not_null()
	if seat != null:
		assert_bool(seat.get_theme_stylebox(&"panel") is StyleBoxEmpty).is_true()
	var tag: Array = (_player_rows(card)[0] as Node).find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text == "Not ready")
	assert_bool(not tag.is_empty() and (tag[0] as Node).get_parent() is PanelContainer \
		and (tag[0] as Node).get_parent() != _player_rows(card)[0]).override_failure_message("the tag is not a chip").is_true()
