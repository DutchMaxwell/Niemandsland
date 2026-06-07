class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension
## Custom MultiplayerPeer that routes traffic through a WebSocket relay server.
##
## Once assigned to multiplayer.multiplayer_peer, all existing RPCs
## (spawn, move, wounds, markers, hero attachment) work without modification.
##
## Binary frame format (sent to relay):
##   [target_peer_id: 4 bytes int32 BE] [payload]
##   target_peer_id = 0 means broadcast to all other peers in room.
##
## Binary frame format (received from relay):
##   [source_peer_id: 4 bytes int32 BE] [payload]

signal room_created(code: String)
signal room_joined(peer_id: int)
signal room_join_failed(reason: String)
signal relay_connected()
signal relay_disconnected()
## The connection was lost unexpectedly (WebSocket closed or heartbeat-ack timeout).
signal relay_connection_lost()
## An automatic rejoin of the same room has started.
signal relay_reconnecting()
## An automatic rejoin attempt failed (could not re-reach the relay/room).
signal relay_reconnect_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const HEARTBEAT_INTERVAL: float = 10.0

## If no heartbeat_ack arrives for this long the connection is treated as dead.
## Must exceed the relay's own 30 s heartbeat timeout to avoid false positives.
const HEARTBEAT_TIMEOUT: float = 35.0

## Give up an automatic rejoin if it hasn't succeeded within this long.
const RECONNECT_TIMEOUT: float = 15.0

## Max WebSocket frames sent per _poll() cycle.
## At ~60fps this caps at ~240 msg/s, staying under the relay server limit (300).
const MAX_SENDS_PER_POLL: int = 4

var _ws: WebSocketPeer = null
var _relay_url: String = ""
var _my_peer_id: int = 0
var _target_peer: int = 0
var _transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var _incoming_packets: Array[IncomingPacket] = []
var _outgoing_queue: Array[PackedByteArray] = []
var _heartbeat_timer: float = 0.0
## Seconds since the last heartbeat_ack from the relay (drop detection).
var _time_since_ack: float = 0.0
var _room_code: String = ""
var _ws_connected: bool = false
var _pending_action: String = ""  # "create" or "join"
var _pending_code: String = ""
## True while an automatic rejoin of the same room is in progress.
var _is_reconnecting: bool = false
## Counts up while reconnecting; aborts the attempt past RECONNECT_TIMEOUT.
var _reconnect_timer: float = 0.0


## Stores an incoming packet with its source peer ID.
class IncomingPacket:
	var from_peer: int
	var data: PackedByteArray

	func _init(p_from: int = 0, p_data: PackedByteArray = PackedByteArray()) -> void:
		from_peer = p_from
		data = p_data


# ===== Public API =====


## Connect to a relay server and create a new room (host flow).
func host_via_relay(url: String) -> Error:
	_pending_action = "create"
	return _connect_to_relay(url)


## Connect to a relay server and join an existing room (guest flow).
func join_via_relay(url: String, code: String) -> Error:
	_pending_action = "join"
	_pending_code = code.to_upper().strip_edges()
	return _connect_to_relay(url)


## Get the current room code (available after room_created / room_joined).
func get_room_code() -> String:
	return _room_code


## Whether this peer is the room host (relay peer id 1).
func is_host_peer() -> bool:
	return _is_server_relay()


## Called when the link dies unexpectedly (socket closed or heartbeat-ack timeout).
## Emits relay_connection_lost so the app can notify the player + try to rejoin.
## Does NOT emit relay_disconnected (that means "session over"); the reconnect flow
## decides the final outcome.
func _on_connection_lost() -> void:
	if _is_reconnecting:
		return  # a rejoin is already in flight; the reconnect timer governs the outcome
	if _connection_status == MultiplayerPeer.CONNECTION_DISCONNECTED and not _ws_connected:
		return  # already handled
	_ws_connected = false
	_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	relay_connection_lost.emit()


## Rejoin the SAME room after a drop. Guests get a fresh peer id and the host then
## re-syncs full state (version handshake -> _sync_state_to_peer), so no game state
## is lost. Hosts cannot rejoin a room they owned (would need relay-side room
## preservation), so this reports a reconnect failure for them.
func attempt_reconnect() -> Error:
	if _is_reconnecting:
		return OK
	if _room_code.is_empty():
		relay_reconnect_failed.emit("no room code")
		return ERR_UNAVAILABLE
	if _is_server_relay():
		relay_reconnect_failed.emit("host cannot rejoin")
		return ERR_UNAVAILABLE
	_is_reconnecting = true
	_reconnect_timer = 0.0
	relay_reconnecting.emit()
	if _ws:
		_ws.close()
		_ws = null
	_ws_connected = false
	_heartbeat_timer = 0.0
	_time_since_ack = 0.0
	_pending_action = "join"
	_pending_code = _room_code
	var err := _connect_to_relay(_relay_url)
	if err != OK:
		_is_reconnecting = false
		relay_reconnect_failed.emit("could not reach relay")
	return err


# ===== MultiplayerPeerExtension overrides =====


func _poll() -> void:
	if _ws == null:
		return

	_ws.poll()

	# Abort a stuck reconnect (relay unreachable / room gone, no response).
	if _is_reconnecting:
		_reconnect_timer += 0.016
		if _reconnect_timer > RECONNECT_TIMEOUT:
			_is_reconnecting = false
			_reconnect_timer = 0.0
			relay_reconnect_failed.emit("timed out")

	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_connected:
			_ws_connected = true
			_connection_status = MultiplayerPeer.CONNECTION_CONNECTING
			_time_since_ack = 0.0  # fresh socket: reset the drop-detection clock
			relay_connected.emit()

			# Execute pending action
			if _pending_action == "create":
				_send_json({"type": "create_room"})
			elif _pending_action == "join":
				_send_json({"type": "join_room", "code": _pending_code})
			_pending_action = ""

		# Process incoming messages
		while _ws.get_available_packet_count() > 0:
			var packet = _ws.get_packet()
			if _ws.was_string_packet():
				_process_control_message(packet.get_string_from_utf8())
			else:
				_process_incoming_binary(packet)

		# Flush queued outgoing packets (rate-limited)
		_flush_outgoing_queue()

		# Heartbeat
		_heartbeat_timer += 0.016  # ~60fps
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_send_json({"type": "heartbeat"})

		# Drop detection: the relay acks every heartbeat. If acks stop arriving the
		# link is dead even though the socket may not have reported CLOSED yet.
		_time_since_ack += 0.016
		if _time_since_ack > HEARTBEAT_TIMEOUT:
			print("[Relay] No heartbeat_ack for %.0fs — connection considered lost" % HEARTBEAT_TIMEOUT)
			_on_connection_lost()

	elif state == WebSocketPeer.STATE_CLOSED:
		if _ws_connected or _connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
			var code = _ws.get_close_code()
			var reason = _ws.get_close_reason()
			print("[Relay] WebSocket closed: code=%d reason='%s'" % [code, reason])
			_on_connection_lost()


func _get_packet_script() -> PackedByteArray:
	if _incoming_packets.is_empty():
		return PackedByteArray()
	var pkt = _incoming_packets.pop_front()
	return pkt.data


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE

	var frame := _build_outgoing_frame(p_buffer)
	_outgoing_queue.append(frame)
	return OK


func _get_available_packet_count() -> int:
	return _incoming_packets.size()


func _get_packet_peer() -> int:
	if _incoming_packets.is_empty():
		return 0
	return _incoming_packets[0].from_peer


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> int:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_unique_id() -> int:
	return _my_peer_id


func _get_connection_status() -> int:
	return _connection_status


func _is_server() -> bool:
	return _my_peer_id == 1


## Whether this peer supports relaying messages through the server.
func _is_server_relay_supported() -> bool:
	return true


## Internal helper for tests to check if this peer is the host.
func _is_server_relay() -> bool:
	return _my_peer_id == 1


func _close() -> void:
	if _ws:
		_ws.close()
		_ws = null
	_my_peer_id = 0
	_target_peer = 0
	_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_incoming_packets.clear()
	_outgoing_queue.clear()
	_heartbeat_timer = 0.0
	_room_code = ""
	_ws_connected = false
	_pending_action = ""
	_pending_code = ""


func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = p_channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(p_mode: int) -> void:
	_transfer_mode = p_mode


func _get_transfer_mode() -> int:
	return _transfer_mode


func _connect_to_relay(url: String) -> Error:
	_relay_url = url
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1048576   # 1MB, matching relay server MAX_MESSAGE_SIZE
	_ws.outbound_buffer_size = 1048576  # 1MB
	var err = _ws.connect_to_url(url)
	if err != OK:
		push_error("RelayMultiplayerPeer: Failed to connect to %s: %d" % [url, err])
		_ws = null
		return err
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


func _send_json(data: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send(JSON.stringify(data).to_utf8_buffer(), WebSocketPeer.WRITE_MODE_TEXT)


## Build the outgoing binary frame: [target_peer_id: 4B BE] [payload]
func _build_outgoing_frame(payload: PackedByteArray) -> PackedByteArray:
	var frame = PackedByteArray()
	frame.resize(4)
	frame.encode_s32(0, 0)  # Will be overwritten
	# Encode target_peer as big-endian int32
	frame[0] = (_target_peer >> 24) & 0xFF
	frame[1] = (_target_peer >> 16) & 0xFF
	frame[2] = (_target_peer >> 8) & 0xFF
	frame[3] = _target_peer & 0xFF
	frame.append_array(payload)
	return frame


## Process a JSON control message from the relay.
func _process_control_message(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_warning("RelayMultiplayerPeer: Invalid JSON from relay")
		return

	var msg_type = parsed.get("type", "")

	match msg_type:
		"room_created":
			var code = parsed.get("code", "")
			var peer_id = int(parsed.get("peer_id", 0))
			_handle_room_created(code, peer_id)

		"room_joined":
			var peer_id = int(parsed.get("peer_id", 0))
			_handle_room_joined(peer_id)

		"peer_connected":
			var peer_id = int(parsed.get("peer_id", 0))
			print("[Relay] Peer %d connected — emitting peer_connected signal" % peer_id)
			peer_joined.emit(peer_id)
			# Notify SceneMultiplayer so it adds the peer to connected_peers.
			# Without this, all RPCs silently fail (both send and receive).
			emit_signal("peer_connected", peer_id)

		"peer_disconnected":
			var peer_id = int(parsed.get("peer_id", 0))
			print("[Relay] Peer %d disconnected — emitting peer_disconnected signal" % peer_id)
			peer_left.emit(peer_id)
			emit_signal("peer_disconnected", peer_id)

		"error":
			var message = parsed.get("message", "Unknown error")
			push_warning("RelayMultiplayerPeer: Relay error: %s" % message)
			if _is_reconnecting:
				# The room is gone (e.g. host left) — a rejoin is impossible.
				_is_reconnecting = false
				_reconnect_timer = 0.0
				relay_reconnect_failed.emit(message)
			elif _connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
				room_join_failed.emit(message)

		"heartbeat_ack":
			_time_since_ack = 0.0  # connection is alive


func _handle_room_created(code: String, peer_id: int) -> void:
	_room_code = code
	_my_peer_id = peer_id
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	_is_reconnecting = false
	room_created.emit(code)


func _handle_room_joined(peer_id: int) -> void:
	_my_peer_id = peer_id
	_room_code = _pending_code  # remember the code so we can rejoin after a drop
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	_is_reconnecting = false
	room_joined.emit(peer_id)


## Process an incoming binary game data frame from the relay.
## Format: [source_peer_id: 4 bytes int32 BE] [payload]
func _process_incoming_binary(frame: PackedByteArray) -> void:
	if frame.size() < 4:
		return  # Too short, ignore

	# Decode source peer ID (big-endian int32)
	var source_peer: int = (frame[0] << 24) | (frame[1] << 16) | (frame[2] << 8) | frame[3]
	var payload = frame.slice(4)

	var pkt = IncomingPacket.new()
	pkt.from_peer = source_peer
	pkt.data = payload
	_incoming_packets.append(pkt)


## Send queued outgoing frames, limited to MAX_SENDS_PER_POLL per cycle.
## At ~60fps with MAX_SENDS_PER_POLL=2 this caps at ~120 msg/s,
## matching the relay server's RATE_LIMIT_MESSAGES_PER_SECOND.
func _flush_outgoing_queue() -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var sent := 0
	while not _outgoing_queue.is_empty() and sent < MAX_SENDS_PER_POLL:
		var frame: PackedByteArray = _outgoing_queue.pop_front()
		var err := _ws.send(frame)
		if err != OK:
			push_warning("[Relay] Send failed: error=%d frame_size=%d bytes" % [err, frame.size()])
			break
		sent += 1
