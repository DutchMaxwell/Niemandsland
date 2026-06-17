extends GdUnitTestSuite
## Pure-logic / offline-state tests for NetworkManager that the existing
## network_identity_test and network_version_handshake_test do NOT cover: chat
## sanitisation, connection-status naming, the RPC-ready guard's offline behaviour,
## and the presence-state half of disconnect_game(). Live RPC / socket paths are
## covered by the Python relay integration suite and the manual gauntlet.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")


func _make_manager() -> Node:
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	return nm


# ===== _clean_chat (static) =====

func test_clean_chat_passthrough_normal_text() -> void:
	assert_str(NetworkManagerScript._clean_chat("Hello world")).is_equal("Hello world")


func test_clean_chat_strips_control_chars() -> void:
	# \n is char 10 (< 32) -> removed, keeping the message one line.
	assert_str(NetworkManagerScript._clean_chat("foo\nbar")).is_equal("foobar")


func test_clean_chat_strips_edges() -> void:
	assert_str(NetworkManagerScript._clean_chat("  hi  ")).is_equal("hi")


func test_clean_chat_clamps_to_max_len() -> void:
	var long := "x".repeat(300)
	assert_int(NetworkManagerScript._clean_chat(long).length()).is_equal(NetworkManagerScript.MAX_CHAT_LEN)


func test_clean_chat_empty_passthrough() -> void:
	assert_str(NetworkManagerScript._clean_chat("")).is_equal("")


# ===== _connection_status_name =====

func test_connection_status_name_known() -> void:
	var nm := _make_manager()
	assert_str(nm._connection_status_name(MultiplayerPeer.CONNECTION_DISCONNECTED)).is_equal("DISCONNECTED")
	assert_str(nm._connection_status_name(MultiplayerPeer.CONNECTION_CONNECTING)).is_equal("CONNECTING")
	assert_str(nm._connection_status_name(MultiplayerPeer.CONNECTION_CONNECTED)).is_equal("CONNECTED")


func test_connection_status_name_unknown_fallback() -> void:
	var nm := _make_manager()
	assert_str(nm._connection_status_name(-1)).is_equal("UNKNOWN(-1)")


# ===== disconnect_game presence-state teardown =====
# (network_identity_test covers the token/slot identity maps; this covers the rest.)
# is_multiplayer_active()/_validate_rpc_ready() depend on the ambient SceneTree
# multiplayer peer (a default OfflineMultiplayerPeer in headless), so they are only
# asserted here where the peer is deterministically nulled by disconnect_game().

func test_disconnect_game_clears_presence_state() -> void:
	var nm := _make_manager()
	nm.connected_peers.append(7)
	nm.player_names[7] = "Alice"
	nm.validated_peers[7] = true
	nm.is_host = true
	nm.disconnect_game()
	assert_bool(nm.connected_peers.is_empty()).is_true()
	assert_bool(nm.player_names.is_empty()).is_true()
	assert_bool(nm.validated_peers.is_empty()).is_true()
	assert_bool(nm.is_host).is_false()
	assert_int(nm._last_connection_status).is_equal(-1)
	# Peer is now null -> session is no longer active.
	assert_bool(nm.is_multiplayer_active()).is_false()


# ===== handshake-timeout no-op for an absent peer =====

func test_handshake_timeout_noop_when_peer_absent() -> void:
	var nm := _make_manager()
	# Peer 9 never joined: must not crash, must not mark it validated.
	nm.enforce_version_handshake_timeout(9)
	assert_bool(nm.is_peer_validated(9)).is_false()
