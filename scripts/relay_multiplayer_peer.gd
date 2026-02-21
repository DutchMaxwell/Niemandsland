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
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const HEARTBEAT_INTERVAL: float = 10.0

var _ws: WebSocketPeer = null
var _relay_url: String = ""
var _my_peer_id: int = 0
var _target_peer: int = 0
var _transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var _incoming_packets: Array[IncomingPacket] = []
var _heartbeat_timer: float = 0.0
var _room_code: String = ""
var _ws_connected: bool = false
var _pending_action: String = ""  # "create" or "join"
var _pending_code: String = ""


## Stores an incoming packet with its source peer ID.
class IncomingPacket:
	var from_peer: int
	var data: PackedByteArray

	func _init(p_from: int = 0, p_data: PackedByteArray = PackedByteArray()) -> void:
		from_peer = p_from
		data = p_data

	static func new(p_from: int, p_data: PackedByteArray) -> IncomingPacket:
		var pkt = IncomingPacket.new()
		pkt.from_peer = p_from
		pkt.data = p_data
		return pkt


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


## Get the current room code (available after room_created signal).
func get_room_code() -> String:
	return _room_code


# ===== MultiplayerPeerExtension overrides =====


func _poll() -> void:
	if _ws == null:
		return

	_ws.poll()

	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_connected:
			_ws_connected = true
			_connection_status = MultiplayerPeer.CONNECTION_CONNECTING
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

		# Heartbeat
		_heartbeat_timer += 0.016  # ~60fps
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_send_json({"type": "heartbeat"})

	elif state == WebSocketPeer.STATE_CLOSED:
		if _ws_connected or _connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
			_ws_connected = false
			_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			relay_disconnected.emit()


func _get_packet_script() -> PackedByteArray:
	if _incoming_packets.is_empty():
		return PackedByteArray()
	var pkt = _incoming_packets.pop_front()
	return pkt.data


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE

	var frame = _build_outgoing_frame(p_buffer)
	return _ws.send(frame)


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
			peer_joined.emit(peer_id)

		"peer_disconnected":
			var peer_id = int(parsed.get("peer_id", 0))
			peer_left.emit(peer_id)

		"error":
			var message = parsed.get("message", "Unknown error")
			push_warning("RelayMultiplayerPeer: Relay error: %s" % message)
			if _connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
				room_join_failed.emit(message)

		"heartbeat_ack":
			pass  # Expected, no action needed


func _handle_room_created(code: String, peer_id: int) -> void:
	_room_code = code
	_my_peer_id = peer_id
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	room_created.emit(code)


func _handle_room_joined(peer_id: int) -> void:
	_my_peer_id = peer_id
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
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
