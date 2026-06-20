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
## The relay replied to a list_rooms request with the joinable public rooms.
signal rooms_list_received(rooms: Array)
## The connection was lost unexpectedly (WebSocket closed or heartbeat-ack timeout).
signal relay_connection_lost()
## An automatic rejoin of the same room has started.
signal relay_reconnecting()
## An automatic rejoin attempt failed (could not re-reach the relay/room).
signal relay_reconnect_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## The host dropped but the room is preserved server-side — guest should wait for rejoin.
signal host_paused()
## The host is present again: we rejoined as host, or (guest side) our host returned.
signal host_rejoined()
## Guest side: OUR OWN dropped connection was re-established (we rejoined the room with a fresh
## peer id). Godot's connected_to_server does NOT re-fire on the reused MultiplayerPeer, so this
## is the only signal that the guest reconnected — listeners must re-announce version+token, or
## the host kicks us on the version-handshake timeout.
signal relay_reconnected()
## A channel-1 command frame arrived from another peer (our hand-rolled protocol, below @rpc).
signal command_received(from_peer: int, data: PackedByteArray)

const HEARTBEAT_INTERVAL: float = 10.0

## If no heartbeat_ack arrives for this long the connection is treated as dead.
## Must exceed the relay's own 30 s heartbeat timeout to avoid false positives.
const HEARTBEAT_TIMEOUT: float = 35.0

## Give up an automatic rejoin if it hasn't succeeded within this long. MUST stay
## comfortably above the relay's HOST_REJOIN_WINDOW_SECONDS (20s, relay_server.py)
## plus a full TCP+TLS re-handshake — otherwise a host whose link recovers at
## second ~18 has already torn itself down while the relay would still restore the
## room, needlessly ending the session (RC5).
const RECONNECT_TIMEOUT: float = 25.0
## Forwarded game frames carry a 1-byte channel marker right after the [peer_id] header so the
## engine's @rpc traffic and our own command protocol can share the one relay connection. Channel 0
## is fed to SceneMultiplayer (unchanged); channel 1 is surfaced via command_received (no path-cache).
const FRAME_CHANNEL_RPC: int = 0
const FRAME_CHANNEL_COMMAND: int = 1

## Outgoing send rate cap — WALL-CLOCK, not per-frame. A per-_poll() cap is framerate-
## dependent (4 sends x 165 fps on a high-refresh display = 660 msg/s), which blew past the
## relay's 300 msg/s rolling-1s limit and tripped a 4429 "Rate limit exceeded" drop the moment
## a burst (e.g. two joining peers each triggering a full state sync) filled the queue. A token
## bucket refilled by real elapsed time keeps the rate constant regardless of fps.
const MAX_SENDS_PER_SECOND: float = 200.0
## Cap on accumulated tokens so a catch-up frame after a main-loop stall can't dump a huge burst
## (keeps any rolling 1s window = steady 200 + burst well under the relay's 300).
const SEND_BURST_MAX: float = 20.0

var _ws: WebSocketPeer = null
var _relay_url: String = ""
var _my_peer_id: int = 0
var _target_peer: int = 0
var _transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var _incoming_packets: Array[IncomingPacket] = []
var _outgoing_queue: Array[PackedByteArray] = []
var _send_tokens: float = SEND_BURST_MAX  # wall-clock send budget (see MAX_SENDS_PER_SECOND)
var _send_refill_ms: int = 0              # last token refill timestamp (0 = uninitialised)
var _tx_msg_count: int = 0                # frames actually sent since the last tx-rate log
var _tx_last_log_ms: int = 0              # last time the tx rate was logged (wall-clock ms)
# Heartbeat / drop detection use the WALL CLOCK (Time.get_ticks_msec), NOT a per-frame
# counter. A frame-based timer runs slow whenever the framerate drops or the main thread
# stalls (loading GLBs, R2 downloads, scene changes), so heartbeats went out too slowly
# in real time and the relay's 30 s timeout dropped the client — the main cause of the
# random disconnects. Wall-clock timing keeps the keepalive on schedule regardless of fps.
var _last_heartbeat_ms: int = 0  # when we last SENT a heartbeat
var _last_ack_ms: int = 0        # when we last RECEIVED a heartbeat_ack (alive marker)
var _last_poll_ms: int = 0       # for stall detection (large gaps delay heartbeats)
var _room_code: String = ""
var _ws_connected: bool = false
var _pending_action: String = ""  # "create", "join" or "list"
var _pending_code: String = ""
var _pending_public: bool = false  # for "create": list this room in the browser
## True while an automatic rejoin of the same room is in progress.
var _is_reconnecting: bool = false
## Wall-clock time (ms) the current reconnect attempt started; aborts past RECONNECT_TIMEOUT.
var _reconnect_start_ms: int = 0
## Guest side: set when the relay reports the host paused, cleared when peer 1 returns.
var _host_paused_seen: bool = false
## Transport ids SceneMultiplayer currently believes are connected (so we can detect a
## reconnect that REUSES an id and flush the stale RPC path-cache — see _emit_peer_connected).
var _known_peers: Dictionary = {}  # Dictionary[int, bool]


## Stores an incoming packet with its source peer ID.
class IncomingPacket:
	var from_peer: int
	var data: PackedByteArray

	func _init(p_from: int = 0, p_data: PackedByteArray = PackedByteArray()) -> void:
		from_peer = p_from
		data = p_data


# ===== Public API =====


## Connect to a relay server and create a new room (host flow). When `public` is
## true the room is listed in the room browser; otherwise it joins by code only.
func host_via_relay(url: String, public: bool = false) -> Error:
	_pending_action = "create"
	_pending_public = public
	return _connect_to_relay(url)


## Connect to a relay server and join an existing room (guest flow).
func join_via_relay(url: String, code: String) -> Error:
	_pending_action = "join"
	_pending_code = code.to_upper().strip_edges()
	return _connect_to_relay(url)


## Connect to a relay server, request the public room list and close. This peer
## is never assigned to multiplayer.multiplayer_peer; the caller polls it.
func list_via_relay(url: String) -> Error:
	_pending_action = "list"
	return _connect_to_relay(url)


## Get the current room code (available after room_created / room_joined).
func get_room_code() -> String:
	return _room_code


## Whether this peer is the room host (relay peer id 1).
func is_host_peer() -> bool:
	return _is_server_relay()


## Called when the link dies unexpectedly (socket closed or heartbeat-ack timeout).
## Emits relay_connection_lost so the app can notify the player + try to rejoin;
## the reconnect flow decides the final outcome.
## Test-only: force the relay socket closed to simulate a network blip. The next _poll()
## sees STATE_CLOSED and runs the normal reconnect path. Never called in normal play — only
## the headless MP soak harness (test/mp/) uses it.
func debug_force_close() -> void:
	if _ws:
		_ws.close()


func _on_connection_lost() -> void:
	if _is_reconnecting:
		return  # a rejoin is already in flight; the reconnect timer governs the outcome
	if _connection_status == MultiplayerPeer.CONNECTION_DISCONNECTED and not _ws_connected:
		return  # already handled
	# Diagnostics: a non-1000 close code (esp. 1006 = abnormal/proxy idle) points at the
	# network/relay; recent "main loop stalled" warnings above point at a client stall.
	# since_ack shows how long the link was silent before we gave up.
	var now := Time.get_ticks_msec()
	var since_ack := (now - _last_ack_ms) / 1000.0
	var close_code := _ws.get_close_code() if _ws else -1
	var close_reason := _ws.get_close_reason() if _ws else ""
	push_warning("[Relay] Connection lost (peer=%d room=%s): %.0fs since last ack, ws_close=%d '%s'" % [
		_my_peer_id, _room_code, since_ack, close_code, close_reason])
	_ws_connected = false
	_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	relay_connection_lost.emit()


## Rejoin the SAME room after a drop. We re-send join_room with the stored code; the
## relay decides between a normal guest rejoin (fresh peer id) and a HOST rehost
## (reclaim peer id 1) based on whether the room is host-paused. Either way the host
## re-syncs full state (version handshake -> _sync_state_to_peer), so nothing is lost.
## Guests get a fresh peer id; a host reclaims peer id 1 if it returns within the
## relay's rejoin window, else the attempt times out and the session ends.
func attempt_reconnect() -> Error:
	if _is_reconnecting:
		return OK
	if _room_code.is_empty():
		relay_reconnect_failed.emit("no room code")
		return ERR_UNAVAILABLE
	_is_reconnecting = true
	_reconnect_start_ms = Time.get_ticks_msec()
	relay_reconnecting.emit()
	if _ws:
		_ws.close()
		_ws = null
	_ws_connected = false
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

	var now_ms := Time.get_ticks_msec()

	# Stall detection: a long gap between polls means the main thread blocked (loading a
	# GLB, an R2 download, a scene change). During the gap no heartbeat is sent, and a
	# gap approaching the relay's 30 s timeout is the prime cause of "random" drops.
	if _ws_connected and _last_poll_ms > 0 and now_ms - _last_poll_ms > 5000:
		push_warning("[Relay] main loop stalled %.1fs — heartbeats delayed (can trigger a relay timeout)"
			% ((now_ms - _last_poll_ms) / 1000.0))
	_last_poll_ms = now_ms

	# Abort a stuck reconnect (relay unreachable / room gone, no response).
	if _is_reconnecting and now_ms - _reconnect_start_ms > int(RECONNECT_TIMEOUT * 1000.0):
		_is_reconnecting = false
		relay_reconnect_failed.emit("timed out")

	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_connected:
			_ws_connected = true
			_connection_status = MultiplayerPeer.CONNECTION_CONNECTING
			_last_ack_ms = now_ms       # fresh socket: reset the drop-detection clock
			_last_heartbeat_ms = now_ms
			_send_tokens = SEND_BURST_MAX  # fresh socket: reset the send budget too
			_send_refill_ms = now_ms

			# Execute pending action
			if _pending_action == "create":
				_send_json({"type": "create_room", "public": _pending_public})
			elif _pending_action == "join":
				# Send our stable identity token so the relay can hand a reconnecting guest its OLD
				# peer id back (stable transport id across a drop -> RPC routing survives the rejoin).
				_send_json({"type": "join_room", "code": _pending_code,
					"token": PlayerIdentity.get_or_create_client_token()})
			elif _pending_action == "list":
				_send_json({"type": "list_rooms"})
			_pending_action = ""

		# Process incoming messages. A control handler may close the socket
		# mid-loop (the rooms_list listing path), nulling _ws — re-check it
		# every iteration or this dereferences null.
		while _ws and _ws.get_available_packet_count() > 0:
			var packet = _ws.get_packet()
			if _ws.was_string_packet():
				_process_control_message(packet.get_string_from_utf8())
			else:
				_process_incoming_binary(packet)

		# Flush queued outgoing packets (rate-limited)
		_flush_outgoing_queue()

		# Heartbeat (wall-clock so it stays on schedule even at low fps / during stalls)
		if now_ms - _last_heartbeat_ms >= int(HEARTBEAT_INTERVAL * 1000.0):
			_last_heartbeat_ms = now_ms
			_send_json({"type": "heartbeat"})

		# Drop detection: the relay acks every heartbeat. No ack for HEARTBEAT_TIMEOUT
		# means the link is dead even if the socket hasn't reported CLOSED yet.
		if now_ms - _last_ack_ms > int(HEARTBEAT_TIMEOUT * 1000.0):
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

	var frame := _build_outgoing_frame(p_buffer, FRAME_CHANNEL_RPC, _target_peer)
	_outgoing_queue.append(frame)
	return OK


## Hand-rolled command protocol (below @rpc, no path-cache). Send a raw command payload to a peer
## (target 0 = broadcast to everyone else in the room). The receiver gets it via command_received.
func send_command(target_peer: int, data: PackedByteArray) -> Error:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	_outgoing_queue.append(_build_outgoing_frame(data, FRAME_CHANNEL_COMMAND, target_peer))
	return OK


func _get_available_packet_count() -> int:
	return _incoming_packets.size()


## Host-initiated kick (e.g. a peer that joined but never passed the version handshake).
## The relay protocol has NO host kick message, so we drop the peer LOCALLY: forget it and
## surface peer_disconnected so SceneMultiplayer stops routing to it and our bookkeeping clears.
## MUST be overridden — without it the engine errors ("_disconnect_peer must be overridden")
## and NetworkManager's handshake-timeout kick never completes, leaving a phantom peer that
## keeps the session in a degraded state. Never act on ourselves.
func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if p_peer == _my_peer_id or p_peer <= 0:
		return
	_known_peers.erase(p_peer)
	emit_signal("peer_disconnected", p_peer)


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
	_send_tokens = SEND_BURST_MAX
	_send_refill_ms = 0
	_tx_msg_count = 0
	_tx_last_log_ms = 0
	_known_peers.clear()
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
func _build_outgoing_frame(payload: PackedByteArray, channel: int, target: int) -> PackedByteArray:
	var frame = PackedByteArray()
	frame.resize(5)
	# [target_peer: big-endian int32][channel: 1 byte]
	frame[0] = (target >> 24) & 0xFF
	frame[1] = (target >> 16) & 0xFF
	frame[2] = (target >> 8) & 0xFF
	frame[3] = target & 0xFF
	frame[4] = channel & 0xFF
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

		"room_rejoined_host":
			var peer_id = int(parsed.get("peer_id", 1))
			_handle_room_rejoined_host(peer_id)

		"peer_connected":
			var peer_id = int(parsed.get("peer_id", 0))
			print("[Relay] Peer %d connected — emitting peer_connected signal" % peer_id)
			peer_joined.emit(peer_id)
			# Notify SceneMultiplayer so it adds the peer (flushing a stale cache on a reused-id
			# reconnect). Without this, all RPCs silently fail (both send and receive).
			_emit_peer_connected(peer_id)
			# Guest side: our paused host has returned (reclaimed peer id 1).
			if peer_id == 1 and _host_paused_seen:
				_host_paused_seen = false
				host_rejoined.emit()

		"host_paused":
			# Guest side: the host dropped but the room is preserved for a rejoin window.
			_host_paused_seen = true
			host_paused.emit()

		"peer_disconnected":
			var peer_id = int(parsed.get("peer_id", 0))
			print("[Relay] Peer %d disconnected — emitting peer_disconnected signal" % peer_id)
			_known_peers.erase(peer_id)
			peer_left.emit(peer_id)
			emit_signal("peer_disconnected", peer_id)

		"error":
			var message = parsed.get("message", "Unknown error")
			push_warning("RelayMultiplayerPeer: Relay error: %s" % message)
			if _is_reconnecting:
				# The room is gone (e.g. host left) — a rejoin is impossible.
				_is_reconnecting = false
				relay_reconnect_failed.emit(message)
			elif _connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
				room_join_failed.emit(message)

		"rooms_list":
			# Browser-only: deliver the list and close — this socket never joins.
			# Close DEFERRED: an inline _close() tears the socket down while
			# _poll's receive loop is still iterating over it (null deref, and a
			# half-destroyed TLS socket crashed the engine in testing).
			rooms_list_received.emit(parsed.get("rooms", []))
			_close.call_deferred()

		"heartbeat_ack":
			_last_ack_ms = Time.get_ticks_msec()  # connection is alive


func _handle_room_created(code: String, peer_id: int) -> void:
	_room_code = code
	_my_peer_id = peer_id
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	_is_reconnecting = false
	room_created.emit(code)


func _handle_room_joined(peer_id: int) -> void:
	var was_reconnecting := _is_reconnecting
	_my_peer_id = peer_id
	_room_code = _pending_code  # remember the code so we can rejoin after a drop
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	_is_reconnecting = false
	room_joined.emit(peer_id)
	if was_reconnecting:
		# A rejoin after our own drop: connected_to_server won't re-fire, so trigger the
		# re-announce explicitly (else the host version-handshake-timeout kicks us -> cascade).
		relay_reconnected.emit()


## The relay let us reclaim the host slot (peer id 1) for a room we owned after a drop.
## Restore host state; the relay then sends peer_connected for each waiting guest, which
## drives the normal version-handshake -> _sync_state_to_peer re-sync to each of them.
func _handle_room_rejoined_host(peer_id: int) -> void:
	_my_peer_id = peer_id
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	_is_reconnecting = false
	host_rejoined.emit()


## (Re)register a transport peer with SceneMultiplayer. If the id is ALREADY known, this is a
## reconnect that REUSED the id, and SceneMultiplayer's RPC path-cache for it is STALE — emit
## peer_disconnected first to purge it, then peer_connected to re-add, so RPCs route again
## instead of failing with "ID X not found in cache of peer Y" (= nothing syncs after a
## reconnect). NEVER flush peer 1: emitting peer_disconnected(1) on a CLIENT triggers
## server_disconnected and tears the session down (and on the host, id 1 is us and never arrives).
func _emit_peer_connected(peer_id: int) -> void:
	if _known_peers.has(peer_id) and peer_id != 1:
		print("[Relay] Peer %d reconnected (reused id) — flushing stale RPC cache" % peer_id)
		emit_signal("peer_disconnected", peer_id)
	_known_peers[peer_id] = true
	emit_signal("peer_connected", peer_id)


## Process an incoming binary game data frame from the relay.
## Format: [source_peer_id: 4 bytes int32 BE] [payload]
func _process_incoming_binary(frame: PackedByteArray) -> void:
	if frame.size() < 5:
		return  # need at least [source_peer: 4][channel: 1]

	# Decode source peer ID (big-endian int32) + the channel marker.
	var source_peer: int = (frame[0] << 24) | (frame[1] << 16) | (frame[2] << 8) | frame[3]
	var channel: int = frame[4]
	var payload = frame.slice(5)

	if channel == FRAME_CHANNEL_COMMAND:
		command_received.emit(source_peer, payload)  # our protocol, not SceneMultiplayer
		return

	var pkt = IncomingPacket.new()
	pkt.from_peer = source_peer
	pkt.data = payload
	_incoming_packets.append(pkt)


## Send queued outgoing frames, rate-limited by a WALL-CLOCK token bucket so the effective
## msg/s stays constant regardless of framerate (a per-frame cap scaled with fps and tripped
## the relay's 300/s limit on high-refresh displays — see MAX_SENDS_PER_SECOND).
func _flush_outgoing_queue() -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var now_ms := Time.get_ticks_msec()
	if _send_refill_ms == 0:
		_send_refill_ms = now_ms
	var elapsed_s := float(now_ms - _send_refill_ms) / 1000.0
	_send_refill_ms = now_ms
	_send_tokens = minf(SEND_BURST_MAX, _send_tokens + elapsed_s * MAX_SENDS_PER_SECOND)

	while not _outgoing_queue.is_empty() and _send_tokens >= 1.0:
		var frame: PackedByteArray = _outgoing_queue.pop_front()
		var err := _ws.send(frame)
		if err != OK:
			push_warning("[Relay] Send failed: error=%d frame_size=%d bytes" % [err, frame.size()])
			break
		_send_tokens -= 1.0
		_tx_msg_count += 1

	# Diagnostic: log the REAL outgoing message rate once per second. A correct client tops out
	# at ~220 msg/s (200 steady + 20 burst); if a live log shows tx far above the relay's limit,
	# the running binary is NOT this source (stale bytecode) — see the boot build line.
	if _tx_last_log_ms == 0:
		_tx_last_log_ms = now_ms
	elif now_ms - _tx_last_log_ms >= 1000:
		if _tx_msg_count > 0:
			print("[Relay] tx=%d msg/s queue=%d tokens=%.1f" % [_tx_msg_count, _outgoing_queue.size(), _send_tokens])
		_tx_msg_count = 0
		_tx_last_log_ms = now_ms
