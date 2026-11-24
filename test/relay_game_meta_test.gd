extends GdUnitTestSuite
## The relay's anonymous game log: the host sends ONE game_meta per game with only the system id,
## faction ids, player count and version; a guest sends none (relay/PRIVACY.md).


class RecordingPeer extends RelayMultiplayerPeer:
	var sent: Array = []

	func _send_json(data: Dictionary) -> void:
		sent.append(data)


func test_the_host_sends_one_game_meta_with_only_the_allowed_fields() -> void:
	var peer := RecordingPeer.new()
	peer._handle_room_created("TESTCD", 1)
	assert_bool(peer.send_game_meta("gf", ["alien_hives", "orc_marauders"], 2, "0.3.16.0")).is_true()
	assert_bool(peer.send_game_meta("gf", ["alien_hives"], 2, "0.3.16.0")).is_false()
	assert_array(peer.sent).is_equal([{"type": "game_meta", "system": "gf",
		"factions": ["alien_hives", "orc_marauders"], "players": 2, "version": "0.3.16.0"}])


func test_a_guest_sends_no_game_meta() -> void:
	var peer := RecordingPeer.new()
	peer._handle_room_joined(2)
	assert_bool(peer.send_game_meta("aof", ["dwarves"], 2, "0.3.16.0")).is_false()
	assert_array(peer.sent).is_empty()


func test_a_one_player_room_sends_none_and_a_new_session_sends_again() -> void:
	var peer := RecordingPeer.new()
	peer._handle_room_created("TESTCD", 1)
	assert_bool(peer.send_game_meta("gf", [], 1, "0.3.16.0")).is_false()
	assert_bool(peer.send_game_meta("gf", [], 2, "0.3.16.0")).is_true()
	peer._close()
	peer._handle_room_created("NEWCDE", 1)
	assert_bool(peer.send_game_meta("gf", [], 2, "0.3.16.0")).is_true()
	assert_int(peer.sent.size()).is_equal(2)
