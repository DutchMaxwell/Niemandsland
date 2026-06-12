class_name InternetLobby
extends Node
## Orchestrates the host/join flow for internet multiplayer via a relay server.
##
## Usage:
##   var lobby = InternetLobby.new()
##   add_child(lobby)
##   lobby.room_code_ready.connect(_on_room_code_ready)
##   lobby.host_internet_game("wss://niemandsland-relay.fly.dev")
##
## Once connected, set multiplayer.multiplayer_peer = lobby.relay_peer
## and all existing RPCs will work automatically.

signal room_code_ready(code: String)
signal internet_connected(peer_id: int)
signal internet_connection_failed(reason: String)
signal internet_disconnected()
## Connection dropped unexpectedly (relayed from the peer); a rejoin may follow.
signal relay_connection_lost()
## An automatic rejoin of the same room has started.
signal relay_reconnecting()
## An automatic rejoin attempt failed; the session is over.
signal relay_reconnect_failed(reason: String)
## Guest side: the host dropped but the room is preserved — waiting for the host to rejoin.
signal host_paused()
## The host is present again (we rejoined as host, or the host returned).
signal host_rejoined()
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## The relay returned the joinable public rooms for the room browser.
signal rooms_list_received(rooms: Array)
## A room-list request failed (relay unreachable, or it rejected list_rooms — e.g.
## an old relay that predates the command).
signal rooms_list_failed(reason: String)

const DEFAULT_RELAY_URL: String = "wss://niemandsland-relay.fly.dev"
## Room capacity shown in the browser; mirrors relay_server.MAX_PEERS_PER_ROOM.
const MAX_ROOM_PLAYERS: int = 8

var relay_peer: RelayMultiplayerPeer = null
var is_host: bool = false
var room_code: String = ""
var relay_url: String = DEFAULT_RELAY_URL


func _process(_delta: float) -> void:
	# Manually poll the WebSocket during the connecting phase.
	# The engine only calls _poll() when the peer is set as multiplayer.multiplayer_peer,
	# but we don't set it until AFTER room_created/room_joined — creating a deadlock.
	if relay_peer and multiplayer.multiplayer_peer != relay_peer:
		relay_peer._poll()


## Host a game via relay: connect to relay, create room, get code. When `public`
## is true the room is listed in the room browser; otherwise it joins by code only.
func host_internet_game(url: String = "", public: bool = false) -> Error:
	if url.is_empty():
		url = relay_url
	else:
		relay_url = url

	relay_peer = RelayMultiplayerPeer.new()
	relay_peer.room_created.connect(_on_room_created)
	relay_peer.relay_disconnected.connect(_on_relay_disconnected)
	relay_peer.peer_joined.connect(_on_peer_joined)
	relay_peer.peer_left.connect(_on_peer_left)
	_connect_recovery_signals()

	var err = relay_peer.host_via_relay(url, public)
	if err != OK:
		push_error("InternetLobby: Failed to connect to relay: %d" % err)
		relay_peer = null
		return err

	is_host = true
	print("=== HOSTING ONLINE via %s ===" % url)
	return OK


## Join a game via relay: connect to relay, join room with code.
func join_internet_game(code: String, url: String = "") -> Error:
	if url.is_empty():
		url = relay_url
	else:
		relay_url = url

	relay_peer = RelayMultiplayerPeer.new()
	relay_peer.room_joined.connect(_on_room_joined)
	relay_peer.room_join_failed.connect(_on_room_join_failed)
	relay_peer.relay_disconnected.connect(_on_relay_disconnected)
	relay_peer.peer_joined.connect(_on_peer_joined)
	relay_peer.peer_left.connect(_on_peer_left)
	_connect_recovery_signals()

	var err = relay_peer.join_via_relay(url, code)
	if err != OK:
		push_error("InternetLobby: Failed to connect to relay: %d" % err)
		relay_peer = null
		return err

	is_host = false
	print("=== JOINING ONLINE room %s via %s ===" % [code, url])
	return OK


## Request the joinable public rooms from the relay (room browser). Opens a
## short-lived listing connection that is never promoted to the multiplayer peer;
## it closes itself once the list arrives. Re-emits rooms_list_received.
func list_rooms(url: String = "") -> Error:
	if url.is_empty():
		url = relay_url
	else:
		relay_url = url

	# A listing connection is separate from any host/join peer; discard a stale one.
	if relay_peer:
		relay_peer._close()
	relay_peer = RelayMultiplayerPeer.new()
	relay_peer.rooms_list_received.connect(_on_rooms_list_received)
	# Surface the two listing failure modes: the relay never reachable
	# (relay_connection_lost) or it rejected list_rooms (room_join_failed — an old
	# relay replies with an "error" frame while the socket is still connecting).
	relay_peer.relay_connection_lost.connect(_on_list_failed.bind("Could not reach the relay."))
	relay_peer.room_join_failed.connect(_on_list_failed)
	# A synchronous connect failure (bad URL, socket error) emits nothing on the
	# peer — surface it ourselves and drop the dead peer, mirroring host/join.
	# Direct emit is safe: the browser wires rooms_list_failed before calling.
	var err := relay_peer.list_via_relay(url)
	if err != OK:
		push_error("InternetLobby: Failed to start room listing: %d" % err)
		relay_peer = null
		rooms_list_failed.emit("Could not reach the relay.")
		return err
	return OK


func _on_rooms_list_received(rooms: Array) -> void:
	rooms_list_received.emit(rooms)
	# The listing socket has closed itself; drop the peer so _process stops polling.
	relay_peer = null


func _on_list_failed(reason: String) -> void:
	rooms_list_failed.emit(reason)
	if relay_peer:
		relay_peer._close()
		relay_peer = null


## Disconnect from internet game and clean up.
func disconnect_internet_game() -> void:
	if relay_peer:
		relay_peer._close()
		relay_peer = null

	# Clear multiplayer peer if it was our relay
	if multiplayer and multiplayer.multiplayer_peer is RelayMultiplayerPeer:
		multiplayer.multiplayer_peer = null

	is_host = false
	room_code = ""
	internet_disconnected.emit()
	print("=== INTERNET DISCONNECTED ===")


func _on_room_created(code: String) -> void:
	room_code = code
	# Set as multiplayer peer - this activates RPCs
	multiplayer.multiplayer_peer = relay_peer
	room_code_ready.emit(code)
	print("=== ROOM CREATED: %s ===" % _format_code(code))


func _on_room_joined(peer_id: int) -> void:
	# Set as multiplayer peer - this activates RPCs
	multiplayer.multiplayer_peer = relay_peer
	internet_connected.emit(peer_id)
	print("=== JOINED ROOM as Peer %d ===" % peer_id)


func _on_room_join_failed(reason: String) -> void:
	internet_connection_failed.emit(reason)
	print("=== JOIN FAILED: %s ===" % reason)


func _on_relay_disconnected() -> void:
	internet_disconnected.emit()
	print("=== RELAY DISCONNECTED ===")


## Wire the drop-detection / reconnect signals from the peer (host + join flows).
func _connect_recovery_signals() -> void:
	relay_peer.relay_connection_lost.connect(_on_relay_connection_lost)
	relay_peer.relay_reconnecting.connect(_on_relay_reconnecting)
	relay_peer.relay_reconnect_failed.connect(_on_relay_reconnect_failed)
	relay_peer.host_paused.connect(_on_host_paused)
	relay_peer.host_rejoined.connect(_on_host_rejoined)


func _on_relay_connection_lost() -> void:
	relay_connection_lost.emit()
	print("=== RELAY CONNECTION LOST ===")


func _on_relay_reconnecting() -> void:
	relay_reconnecting.emit()
	print("=== RELAY RECONNECTING ===")


func _on_relay_reconnect_failed(reason: String) -> void:
	relay_reconnect_failed.emit(reason)
	print("=== RELAY RECONNECT FAILED: %s ===" % reason)


func _on_host_paused() -> void:
	host_paused.emit()


func _on_host_rejoined() -> void:
	host_rejoined.emit()


## Attempt to rejoin the same room after a drop. A guest gets a fresh peer id; a host
## reclaims peer id 1 if it returns within the relay's window. The (re)host re-syncs
## full state to the waiting peers, so no game state is lost. Returns OK if started.
func reconnect_to_room() -> Error:
	if relay_peer and not relay_peer.get_room_code().is_empty():
		return relay_peer.attempt_reconnect()
	return ERR_UNAVAILABLE


func _on_peer_joined(peer_id: int) -> void:
	peer_joined.emit(peer_id)
	print("=== PEER %d JOINED ===" % peer_id)


func _on_peer_left(peer_id: int) -> void:
	peer_left.emit(peer_id)
	print("=== PEER %d LEFT ===" % peer_id)


## Format room code for display: "ABC123" -> "ABC-123"
static func _format_code(code: String) -> String:
	if code.length() == 6:
		return code.substr(0, 3) + "-" + code.substr(3, 3)
	return code
