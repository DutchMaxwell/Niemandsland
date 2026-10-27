extends GdUnitTestSuite
## #1866: a rejoin whose new socket dies must be retried until RECONNECT_TIMEOUT. Today only the
## early rejoin (fast reconnect) retried; a normal rejoin only printed the close every frame and
## waited out the 25 s in silence.


const FIRST_RETRY_WAIT_MS := 2000.0  # RECREATE_RETRY_INTERVAL


func _seated() -> RelayMultiplayerPeer:
	var peer := RelayMultiplayerPeer.new()
	peer._process_control_message('{"type": "room_joined", "peer_id": 2, "takeover": true}')
	peer._room_code = "ABCDEF"
	peer._relay_url = "ws://127.0.0.1:9"
	return peer


func test_a_normal_rejoin_retries_a_failed_socket() -> void:
	var peer := _seated()
	var started := Time.get_ticks_msec()
	assert_int(peer.attempt_reconnect()).is_equal(OK)
	assert_bool(peer._is_reconnecting).is_true()
	# The first retry must not hammer the relay: it waits for the recreate interval.
	assert_int(peer._next_connect_retry_ms).is_greater_equal(started + int(FIRST_RETRY_WAIT_MS) - 50)
	var failed_socket := WebSocketPeer.new()  # never connected = CLOSED
	peer._ws = failed_socket
	peer._poll()
	assert_bool(peer._ws == failed_socket).is_true()  # before the interval: no new attempt
	# Two seconds later the next poll re-opens the socket instead of idling until the deadline.
	peer._next_connect_retry_ms = Time.get_ticks_msec() - 1
	peer._poll()
	assert_bool(peer._ws != failed_socket).is_true()
	assert_str(peer._pending_action).is_equal("join")
	assert_int(peer._next_connect_retry_ms).is_greater(Time.get_ticks_msec() - 1)
	assert_bool(peer._is_reconnecting).is_true()
	peer._close()


func test_a_normal_rejoin_still_gives_up_at_the_deadline() -> void:
	var fails := [0]
	var peer := _seated()
	peer._is_reconnecting = true
	peer._fast_reconnect_ms = 0
	peer._reconnect_start_ms = Time.get_ticks_msec() - 26000  # past RECONNECT_TIMEOUT (25 s)
	peer._ws = WebSocketPeer.new()
	peer.relay_reconnect_failed.connect(func(_r: String) -> void: fails[0] += 1)
	peer._poll()
	assert_int(fails[0]).is_equal(1)
	assert_bool(peer._is_reconnecting).is_false()
	peer._close()
