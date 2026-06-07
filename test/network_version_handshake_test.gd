extends GdUnitTestSuite
## Tests for the multiplayer version handshake in network_manager.gd.
## The RPC round-trip needs a live session, but the gating helpers are pure and
## are what guarantee a mismatched (or silent) peer never receives game state.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")


func _make_manager() -> Node:
	# Added to the tree so Node.multiplayer is valid for disconnect_game().
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	return nm


func test_game_version_matches_project_setting() -> void:
	var nm := _make_manager()
	var expected := str(ProjectSettings.get_setting("application/config/version", "unknown"))
	assert_that(nm.get_game_version()).is_equal(expected)
	assert_that(nm.get_game_version()).is_not_equal("unknown")


func test_unknown_peer_is_not_validated() -> void:
	var nm := _make_manager()
	assert_that(nm.is_peer_validated(42)).is_false()


func test_validated_peer_is_recognized() -> void:
	var nm := _make_manager()
	nm.validated_peers[7] = true
	assert_that(nm.is_peer_validated(7)).is_true()


func test_disconnect_clears_validated_peers() -> void:
	var nm := _make_manager()
	nm.validated_peers[3] = true
	nm.validated_peers[4] = true
	nm.disconnect_game()
	assert_that(nm.validated_peers.is_empty()).is_true()


func test_handshake_timeout_keeps_validated_peer() -> void:
	# A peer that already passed the handshake must not be kicked by the timeout.
	var nm := _make_manager()
	nm.connected_peers.append(9)
	nm.validated_peers[9] = true
	nm.enforce_version_handshake_timeout(9)  # no-op: validated
	assert_that(nm.is_peer_validated(9)).is_true()
	assert_that(nm.connected_peers.has(9)).is_true()
