extends GdUnitTestSuite
## Bug 4: a Wi-Fi flow can go silent both ways for 13-28 s. On a relay that can hand our seat to a new
## socket ("takeover" in its join reply) the client rejoins after FAST_SILENCE_TIMEOUT of inbound silence;
## a main-loop stall is not silence; an older relay keeps today's 35 s rule.


func _seated_guest(takeover_reply: String) -> RelayMultiplayerPeer:
	var peer := RelayMultiplayerPeer.new()
	peer._process_control_message('{"type": "room_joined", "peer_id": 2%s}' % takeover_reply)
	return peer


func _count_drops(peer: RelayMultiplayerPeer) -> Array:
	var drops := [0]
	peer.relay_connection_lost.connect(func() -> void: drops[0] += 1)
	return drops


func test_silent_link_rejoins_early_on_a_takeover_relay() -> void:
	var peer := _seated_guest(', "takeover": true')
	var drops := _count_drops(peer)
	peer._quiet_since_ms = 1000
	peer._check_silence(1000 + 9000)
	assert_int(drops[0]).is_equal(0)
	assert_bool(peer.is_fast_reconnect()).is_false()
	peer._check_silence(1000 + 10500)
	assert_int(drops[0]).is_equal(1)
	assert_bool(peer.is_fast_reconnect()).is_true()


func test_an_old_relay_keeps_the_35s_rule() -> void:
	var peer := _seated_guest("")
	var drops := _count_drops(peer)
	peer._quiet_since_ms = 1000
	peer._check_silence(1000 + 20000)
	assert_int(drops[0]).is_equal(0)
	assert_bool(peer.is_fast_reconnect()).is_false()


## The 7.6 s stall of the live log: last ack at 0.05 s, the main loop frozen from 4.9 s to 12.5 s, so no
## heartbeat went out and nothing read the socket. 12.45 s of wall clock, but the link was idle only 4.85 s.
func test_a_main_loop_stall_is_not_link_silence() -> void:
	var peer := _seated_guest(', "takeover": true')
	var drops := _count_drops(peer)
	peer._ws = WebSocketPeer.new()  # unconnected: _poll runs its clock bookkeeping, then sees no open socket
	while Time.get_ticks_msec() < 8000:  # the real clock must be able to hold a 7.6 s gap after a poll at > 0
		await get_tree().process_frame
	var now := Time.get_ticks_msec()
	peer._quiet_since_ms = now - 12450
	peer._last_poll_ms = now - 7600
	peer._poll()
	peer._check_silence(Time.get_ticks_msec())
	assert_int(drops[0]).is_equal(0)
	# The same 12.45 s while the loop kept running IS a silent link (the check can fail).
	peer._check_silence(peer._quiet_since_ms + 12450)
	assert_int(drops[0]).is_equal(1)


func test_one_early_rejoin_per_minute() -> void:
	var peer := _seated_guest(', "takeover": true')
	var drops := _count_drops(peer)
	peer._quiet_since_ms = 1000
	peer._check_silence(11500)
	assert_int(drops[0]).is_equal(1)
	peer._process_control_message('{"type": "room_joined", "peer_id": 2, "takeover": true}')
	assert_bool(peer.is_fast_reconnect()).is_false()
	peer._quiet_since_ms = 20000
	peer._check_silence(31000)   # a second silence 19.5 s later: back to the 35 s rule
	assert_int(drops[0]).is_equal(1)


func test_a_rejoin_names_its_old_seat_a_first_join_does_not() -> void:
	var peer := _seated_guest(', "takeover": true')
	assert_bool(peer._join_request("ABCDEF").has("takeover")).is_false()
	peer._is_reconnecting = true
	var rejoin := peer._join_request("ABCDEF")
	assert_int(int(rejoin.get("takeover", 0))).is_equal(2)
	assert_str(str(rejoin.get("code", ""))).is_equal("ABCDEF")


func test_a_normal_drop_is_not_a_fast_reconnect() -> void:
	var peer := _seated_guest(', "takeover": true')
	var drops := _count_drops(peer)
	peer._on_connection_lost()   # what a closed socket or the 35 s rule does
	assert_int(drops[0]).is_equal(1)
	assert_bool(peer.is_fast_reconnect()).is_false()


## Mid-rejoin with the link fully down: the new socket failed. `fast` = an early rejoin.
func _rejoining(fast: bool, started_ago_ms: int) -> RelayMultiplayerPeer:
	var peer := _seated_guest(', "takeover": true')
	var now := Time.get_ticks_msec()
	peer._is_reconnecting = true
	peer._fast_reconnect_ms = now if fast else 0
	peer._reconnect_start_ms = now - started_ago_ms
	peer._room_code = "ABCDEF"
	peer._relay_url = "ws://127.0.0.1:9"
	peer._ws = WebSocketPeer.new()   # never connected = CLOSED
	return peer


func test_an_early_rejoin_retries_a_failed_socket_today_s_rejoin_does_not() -> void:
	var fast := _rejoining(true, 1000)
	var failed_socket := fast._ws
	fast._poll()
	assert_bool(fast._ws != failed_socket).is_true()
	assert_str(fast._pending_action).is_equal("join")
	fast._close()
	var normal := _rejoining(false, 1000)
	var kept := normal._ws
	normal._poll()
	assert_bool(normal._ws == kept).is_true()


func test_an_early_rejoin_gives_up_when_today_s_rejoin_would() -> void:
	# 30 s into the rejoin: past RECONNECT_TIMEOUT (25 s), but an early rejoin started 25 s sooner.
	var fails := [0]
	var fast := _rejoining(true, 30000)
	fast.relay_reconnect_failed.connect(func(_r: String) -> void: fails[0] += 1)
	fast._poll()
	assert_int(fails[0]).is_equal(0)
	fast._reconnect_start_ms = Time.get_ticks_msec() - 50500
	fast._poll()
	assert_int(fails[0]).is_equal(1)
	fast._close()
	var normal := _rejoining(false, 30000)
	normal.relay_reconnect_failed.connect(func(_r: String) -> void: fails[0] += 1)
	normal._poll()
	assert_int(fails[0]).is_equal(2)
