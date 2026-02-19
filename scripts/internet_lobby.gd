class_name InternetLobby
extends Node
## Orchestrates the host/join flow for internet multiplayer via a relay server.
##
## Usage:
##   var lobby = InternetLobby.new()
##   add_child(lobby)
##   lobby.room_code_ready.connect(_on_room_code_ready)
##   lobby.host_internet_game("wss://opentts-relay.fly.dev")
##
## Once connected, set multiplayer.multiplayer_peer = lobby.relay_peer
## and all existing RPCs will work automatically.

signal room_code_ready(code: String)
signal internet_connected(peer_id: int)
signal internet_connection_failed(reason: String)
signal internet_disconnected()
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const DEFAULT_RELAY_URL: String = "wss://opentts-relay.fly.dev"

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


## Host a game via relay: connect to relay, create room, get code.
func host_internet_game(url: String = "") -> Error:
	if url.is_empty():
		url = relay_url
	else:
		relay_url = url

	relay_peer = RelayMultiplayerPeer.new()
	relay_peer.room_created.connect(_on_room_created)
	relay_peer.relay_disconnected.connect(_on_relay_disconnected)
	relay_peer.peer_joined.connect(_on_peer_joined)
	relay_peer.peer_left.connect(_on_peer_left)

	var err = relay_peer.host_via_relay(url)
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

	var err = relay_peer.join_via_relay(url, code)
	if err != OK:
		push_error("InternetLobby: Failed to connect to relay: %d" % err)
		relay_peer = null
		return err

	is_host = false
	print("=== JOINING ONLINE room %s via %s ===" % [code, url])
	return OK


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
