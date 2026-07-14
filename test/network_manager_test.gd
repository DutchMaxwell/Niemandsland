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


# ===== Peer busy/loading gate =====
# The set tracking + aggregate signal are pure state logic (no socket); the over-the-wire
# broadcast/RPC paths are exercised by the relay suite + the manual MP gauntlet.

func test_no_remote_peer_busy_by_default() -> void:
	var nm := _make_manager()
	assert_bool(nm.is_any_remote_peer_busy()).is_false()


func test_set_remote_peer_busy_toggles_aggregate() -> void:
	var nm := _make_manager()
	nm._set_remote_peer_busy(7, true)
	assert_bool(nm.is_any_remote_peer_busy()).is_true()
	nm._set_remote_peer_busy(7, false)
	assert_bool(nm.is_any_remote_peer_busy()).is_false()


func test_session_busy_signal_fires_only_on_aggregate_flip() -> void:
	var nm := _make_manager()
	var monitor := monitor_signals(nm)
	# First peer busy -> one "true". Second peer busy -> NO new emit (already busy).
	nm._set_remote_peer_busy(7, true)
	nm._set_remote_peer_busy(8, true)
	await assert_signal(monitor).is_emitted("session_busy_changed", [true])
	# First peer idle -> still busy (8), no "false". Last peer idle -> one "false".
	nm._set_remote_peer_busy(7, false)
	assert_bool(nm.is_any_remote_peer_busy()).is_true()
	nm._set_remote_peer_busy(8, false)
	await assert_signal(monitor).is_emitted("session_busy_changed", [false])


func test_peer_disconnect_failsafe_clears_busy_flag() -> void:
	var nm := _make_manager()
	nm._set_remote_peer_busy(7, true)
	# A peer that drops mid-load must not freeze the table forever.
	nm._on_peer_disconnected(7)
	assert_bool(nm.is_any_remote_peer_busy()).is_false()


func test_disconnect_game_clears_busy_peers() -> void:
	var nm := _make_manager()
	nm._set_remote_peer_busy(7, true)
	nm.disconnect_game()
	assert_bool(nm.is_any_remote_peer_busy()).is_false()


func test_broadcast_peer_busy_records_local_flag_offline() -> void:
	var nm := _make_manager()
	# Offline: no broadcast goes out, but the local flag is still tracked (for late-joiner forward).
	nm.broadcast_peer_busy(true)
	assert_bool(nm._local_busy).is_true()
	nm.broadcast_peer_busy(false)
	assert_bool(nm._local_busy).is_false()


# ===== Dice cup-composition + colour-tag sync =====
# The broadcasters are offline-safe no-ops; the RPC handlers re-emit the local-facing signals.
# Live routing is covered by the relay suite + the manual 2-instance MP test.

func test_broadcast_dice_composition_offline_is_safe() -> void:
	var nm := _make_manager()
	nm.broadcast_dice_composition(6, [1, 0, 2, 0, 0, 0])  # offline: must not crash


func test_broadcast_dice_color_tag_offline_is_safe() -> void:
	var nm := _make_manager()
	nm.broadcast_dice_color_tag(2, 3)  # offline: must not crash


func test_sync_dice_composition_emits_signal() -> void:
	var nm := _make_manager()
	var monitor := monitor_signals(nm)
	# Sender is 0 offline (no command dispatch / @rpc context); the args are still forwarded.
	nm.sync_dice_composition(5, [0, 1, 2, 3, 4])
	await assert_signal(monitor).is_emitted("remote_dice_composition", [0, 5, [0, 1, 2, 3, 4]])


func test_sync_dice_color_tag_emits_signal() -> void:
	var nm := _make_manager()
	var monitor := monitor_signals(nm)
	nm.sync_dice_color_tag(1, 4)
	await assert_signal(monitor).is_emitted("remote_dice_color_tag", [0, 1, 4])


func test_sync_dice_roll_emits_signal_with_tags() -> void:
	var nm := _make_manager()
	var monitor := monitor_signals(nm)
	nm.sync_dice_roll([4, 2], {"context": "test"}, [1, 0])
	await assert_signal(monitor).is_emitted("remote_dice_rolled", [0, [4, 2], {"context": "test"}, [1, 0]])


# ===== Deployment ready-sync (host-authoritative both-ready gate) =====
# The host-side gate keys off the is_host flag (set from multiplayer.is_server() on connect in prod),
# so a test sets is_host=true to act as the host. Seated slots are simulated by populating
# connected_peers/validated_peers/peer_to_slot directly, the same way network_identity_test seeds host
# state. The over-the-wire report/broadcast frames are exercised by the relay suite + manual MP test.

## A NetworkManager acting as the HOST (host-authority gate keys off is_host, set on connect in prod).
func _make_host() -> Node:
	var nm := _make_manager()
	nm.is_host = true
	return nm


## Seat a validated guest at `slot` on transport `peer` in the host's roster.
func _seat_guest(nm: Node, peer: int, slot: int) -> void:
	nm.connected_peers.append(peer)
	nm.validated_peers[peer] = true
	nm.peer_to_slot[peer] = slot
	nm.slot_to_peer[slot] = peer


func test_seated_slots_host_only_when_alone() -> void:
	var nm := _make_host()
	assert_array(nm.seated_slots()).is_equal([1])


func test_seated_slots_includes_validated_guest_excludes_unvalidated() -> void:
	var nm := _make_host()
	_seat_guest(nm, 10, 2)
	# An unvalidated, still-handshaking peer is NOT counted toward the ready gate.
	nm.connected_peers.append(11)
	nm.peer_to_slot[11] = 3
	assert_array(nm.seated_slots()).is_equal([1, 2])


func test_all_players_ready_false_until_every_seat_ready() -> void:
	var nm := _make_host()
	_seat_guest(nm, 10, 2)
	assert_bool(nm.all_players_ready()).is_false()   # nobody ready
	nm._host_record_ready(1, true)                   # host readies
	assert_bool(nm.all_players_ready()).is_false()   # guest slot 2 still not ready
	assert_int(nm.ready_count()).is_equal(1)


func test_single_ready_does_not_fire_transition() -> void:
	var nm := _make_host()
	_seat_guest(nm, 10, 2)
	var monitor := monitor_signals(nm)
	nm._host_record_ready(1, true)  # only the host is ready
	await assert_signal(monitor).is_not_emitted("remote_game_phase_changed")


func test_both_ready_fires_authoritative_transition() -> void:
	var nm := _make_host()
	_seat_guest(nm, 10, 2)
	var monitor := monitor_signals(nm)
	nm._host_record_ready(1, true)  # host
	nm._host_record_ready(2, true)  # guest -> gate closes, host broadcasts PLAYING
	await assert_signal(monitor).is_emitted("remote_game_phase_changed", [OPRArmyManager.GamePhase.PLAYING])
	# The ready roster is cleared once the start fires (a later re-deploy re-arms it).
	assert_bool(nm.is_local_ready()).is_false()


func test_unready_reopens_the_gate() -> void:
	var nm := _make_host()
	# Two guests so a partial-ready set never trips the transition mid-test.
	_seat_guest(nm, 10, 2)
	_seat_guest(nm, 11, 3)
	nm._host_record_ready(1, true)
	nm._host_record_ready(2, true)
	assert_bool(nm.all_players_ready()).is_false()  # slot 3 outstanding
	assert_int(nm.ready_count()).is_equal(2)
	# A player un-readies before the start fires — the gate stays closed.
	nm._host_record_ready(2, false)
	assert_bool(nm.all_players_ready()).is_false()
	assert_int(nm.ready_count()).is_equal(1)


func test_reset_ready_state_clears_flags() -> void:
	var nm := _make_host()
	_seat_guest(nm, 10, 2)
	nm._host_record_ready(1, true)
	nm.set_local_ready(true)
	nm.reset_ready_state()
	assert_bool(nm.is_local_ready()).is_false()
	assert_int(nm.ready_count()).is_equal(0)


func test_rpc_set_game_phase_emits_for_guest_apply() -> void:
	# The guest-side handler simply re-emits the authoritative phase for main.gd to apply.
	var nm := _make_manager()
	var monitor := monitor_signals(nm)
	nm._rpc_set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	await assert_signal(monitor).is_emitted("remote_game_phase_changed", [OPRArmyManager.GamePhase.PLAYING])
