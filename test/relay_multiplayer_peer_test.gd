extends GdUnitTestSuite
## Tests for RelayMultiplayerPeer
## Tests the custom MultiplayerPeerExtension that routes traffic through a WebSocket relay.


func test_initial_status_is_disconnected() -> void:
	var peer = RelayMultiplayerPeer.new()
	assert_that(peer.get_connection_status()).is_equal(MultiplayerPeer.CONNECTION_DISCONNECTED)


func test_initial_unique_id_is_zero() -> void:
	var peer = RelayMultiplayerPeer.new()
	assert_that(peer.get_unique_id()).is_equal(0)


func test_initial_is_server_false() -> void:
	var peer = RelayMultiplayerPeer.new()
	assert_that(peer._is_server_relay()).is_false()


func test_close_resets_all_state() -> void:
	var peer = RelayMultiplayerPeer.new()
	# Simulate having been connected
	peer._my_peer_id = 1
	peer._connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	peer._room_code = "ABC123"
	peer._incoming_packets.append(RelayMultiplayerPeer.IncomingPacket.new(2, PackedByteArray([1, 2, 3])))

	peer._close()

	assert_that(peer._my_peer_id).is_equal(0)
	assert_that(peer._connection_status).is_equal(MultiplayerPeer.CONNECTION_DISCONNECTED)
	assert_that(peer._room_code).is_equal("")
	assert_that(peer._incoming_packets.size()).is_equal(0)


func test_host_gets_peer_id_one() -> void:
	var peer = RelayMultiplayerPeer.new()
	# Simulate room_created response
	peer._handle_room_created("TESTCD", 1)
	assert_that(peer.get_unique_id()).is_equal(1)
	assert_that(peer._is_server_relay()).is_true()


func test_guest_gets_assigned_peer_id() -> void:
	var peer = RelayMultiplayerPeer.new()
	# Simulate room_joined response
	peer._handle_room_joined(3)
	assert_that(peer.get_unique_id()).is_equal(3)
	assert_that(peer._is_server_relay()).is_false()


func test_room_code_stored_on_create() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._handle_room_created("XYZ789", 1)
	assert_that(peer.get_room_code()).is_equal("XYZ789")


func test_put_packet_prepends_target_peer_header() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._my_peer_id = 1
	peer._target_peer = 2

	var payload = PackedByteArray([10, 20, 30])
	var result = peer._build_outgoing_frame(payload, RelayMultiplayerPeer.FRAME_CHANNEL_RPC, peer._target_peer)

	# [target_peer: 4 bytes BE][channel: 1 byte][payload]
	assert_that(result.slice(0, 4)).is_equal(PackedByteArray([0, 0, 0, 2]))
	assert_that(result[4]).is_equal(RelayMultiplayerPeer.FRAME_CHANNEL_RPC)
	assert_that(result.slice(5)).is_equal(payload)


func test_incoming_binary_queued_as_packet() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._my_peer_id = 2

	# [source_peer_id: 4 bytes BE][channel: 1 byte][payload]; channel 0 -> SceneMultiplayer queue
	var frame = PackedByteArray([0, 0, 0, 1, RelayMultiplayerPeer.FRAME_CHANNEL_RPC, 42, 43, 44])

	peer._process_incoming_binary(frame)

	assert_that(peer._get_available_packet_count()).is_equal(1)
	var packet = peer._incoming_packets[0]
	assert_that(packet.from_peer).is_equal(1)
	assert_that(packet.data).is_equal(PackedByteArray([42, 43, 44]))


func test_command_channel_frame_emits_signal_not_queued() -> void:
	var peer = RelayMultiplayerPeer.new()
	# [source: 4][channel = 1 (command)][payload] -> surfaced via command_received, NOT the @rpc queue
	var frame = PackedByteArray([0, 0, 0, 1, RelayMultiplayerPeer.FRAME_CHANNEL_COMMAND, 7, 8])
	var got := {"from": -1, "data": PackedByteArray()}
	peer.command_received.connect(func(from_peer, data): got.from = from_peer; got.data = data)

	peer._process_incoming_binary(frame)

	assert_that(peer._get_available_packet_count()).is_equal(0)  # not in the @rpc path
	assert_that(got.from).is_equal(1)
	assert_that(got.data).is_equal(PackedByteArray([7, 8]))


func test_get_available_packet_count() -> void:
	var peer = RelayMultiplayerPeer.new()
	assert_that(peer._get_available_packet_count()).is_equal(0)

	peer._incoming_packets.append(RelayMultiplayerPeer.IncomingPacket.new(1, PackedByteArray([1])))
	assert_that(peer._get_available_packet_count()).is_equal(1)

	peer._incoming_packets.append(RelayMultiplayerPeer.IncomingPacket.new(2, PackedByteArray([2])))
	assert_that(peer._get_available_packet_count()).is_equal(2)


func test_broadcast_uses_target_zero() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._my_peer_id = 1
	peer._target_peer = 0  # Broadcast

	var payload = PackedByteArray([99])
	var result = peer._build_outgoing_frame(payload, RelayMultiplayerPeer.FRAME_CHANNEL_RPC, 0)

	# Target 0 = broadcast
	assert_that(result.slice(0, 4)).is_equal(PackedByteArray([0, 0, 0, 0]))


func test_room_joined_stores_room_code_for_reconnect() -> void:
	# A guest must remember its room code so it can rejoin after a drop.
	var peer = RelayMultiplayerPeer.new()
	peer._pending_code = "ABC123"
	peer._handle_room_joined(2)
	assert_that(peer.get_room_code()).is_equal("ABC123")


func test_is_host_peer_distinguishes_host_and_guest() -> void:
	var host = RelayMultiplayerPeer.new()
	host._handle_room_created("XYZ999", 1)
	assert_that(host.is_host_peer()).is_true()

	var guest = RelayMultiplayerPeer.new()
	guest._pending_code = "XYZ999"
	guest._handle_room_joined(2)
	assert_that(guest.is_host_peer()).is_false()


func test_attempt_reconnect_without_room_code_fails() -> void:
	var peer = RelayMultiplayerPeer.new()
	# No room code yet -> cannot rejoin.
	assert_that(peer.attempt_reconnect()).is_equal(ERR_UNAVAILABLE)


## Regression: the rooms_list listing reply must deliver the rooms and must NOT
## tear the socket down inline — an inline _close() nulled _ws while _poll's
## receive loop was still iterating (null deref; crashed the engine live).
func test_rooms_list_emits_rooms_and_defers_close() -> void:
	var peer = RelayMultiplayerPeer.new()
	var received: Array = []
	peer.rooms_list_received.connect(func(rooms: Array) -> void: received.append(rooms))

	peer._process_control_message('{"type": "rooms_list", "rooms": [{"code": "ABC123", "players": 2}]}')

	assert_that(received.size()).is_equal(1)
	assert_that(received[0].size()).is_equal(1)
	assert_that(received[0][0]["code"]).is_equal("ABC123")
	# The close is DEFERRED — state is still intact right after the handler...
	assert_that(peer._pending_action).is_equal("")
	# ...and fully reset once deferred calls flush (end of frame).
	await get_tree().process_frame
	assert_that(peer.get_connection_status()).is_equal(MultiplayerPeer.CONNECTION_DISCONNECTED)
	assert_that(peer.get_room_code()).is_equal("")


func test_rooms_list_with_empty_array_emits_empty() -> void:
	var peer = RelayMultiplayerPeer.new()
	var received: Array = []
	peer.rooms_list_received.connect(func(rooms: Array) -> void: received.append(rooms))

	peer._process_control_message('{"type": "rooms_list", "rooms": []}')

	assert_that(received.size()).is_equal(1)
	assert_that(received[0].is_empty()).is_true()


## Regression: _disconnect_peer MUST be overridden (the engine errors otherwise) so the
## host's failed-handshake kick actually completes. The relay has no host-kick message, so
## the override drops the peer locally: forget it + emit peer_disconnected for SceneMultiplayer.
func test_disconnect_peer_emits_and_forgets() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._my_peer_id = 1
	peer._known_peers[3] = true
	var disconnected: Array = []
	peer.peer_disconnected.connect(func(id: int) -> void: disconnected.append(id))

	peer._disconnect_peer(3, false)

	assert_that(disconnected).is_equal([3])
	assert_that(peer._known_peers.has(3)).is_false()


## Never disconnect ourselves or an invalid id — on a client, emitting peer_disconnected(1)
## would trigger server_disconnected and tear the whole session down.
func test_disconnect_peer_ignores_self_and_invalid() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._my_peer_id = 1
	var disconnected: Array = []
	peer.peer_disconnected.connect(func(id: int) -> void: disconnected.append(id))

	peer._disconnect_peer(1, false)   # self (host id)
	peer._disconnect_peer(0, false)   # invalid

	assert_that(disconnected.is_empty()).is_true()


## Guard: the wall-clock send budget (steady rate + a full burst) must stay under the relay
## server's RATE_LIMIT_MESSAGES_PER_SECOND (300). A per-frame cap once scaled with fps and
## blew past it on high-refresh displays — this invariant fails loudly if someone re-raises it.
func test_send_rate_cap_stays_under_relay_limit() -> void:
	var steady := RelayMultiplayerPeer.MAX_SENDS_PER_SECOND
	var burst := RelayMultiplayerPeer.SEND_BURST_MAX
	assert_that(steady + burst < 300.0).is_true()
