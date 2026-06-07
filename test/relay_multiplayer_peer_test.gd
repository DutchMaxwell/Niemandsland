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
	var result = peer._build_outgoing_frame(payload)

	# First 4 bytes should be target_peer_id (2) in big-endian
	var expected_header = PackedByteArray([0, 0, 0, 2])
	assert_that(result.slice(0, 4)).is_equal(expected_header)
	# Rest should be the payload
	assert_that(result.slice(4)).is_equal(payload)


func test_incoming_binary_queued_as_packet() -> void:
	var peer = RelayMultiplayerPeer.new()
	peer._my_peer_id = 2

	# Simulate receiving a binary frame from the relay
	# Format: [source_peer_id: 4 bytes BE] [payload]
	var source_id_bytes = PackedByteArray([0, 0, 0, 1])  # From peer 1
	var payload = PackedByteArray([42, 43, 44])
	var frame = source_id_bytes + payload

	peer._process_incoming_binary(frame)

	assert_that(peer._get_available_packet_count()).is_equal(1)
	var packet = peer._incoming_packets[0]
	assert_that(packet.from_peer).is_equal(1)
	assert_that(packet.data).is_equal(payload)


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
	var result = peer._build_outgoing_frame(payload)

	# Target 0 = broadcast
	var expected_header = PackedByteArray([0, 0, 0, 0])
	assert_that(result.slice(0, 4)).is_equal(expected_header)


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
