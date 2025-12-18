extends Node
## Network Manager for OpenTTS Multiplayer
## Handles hosting, joining, and basic state synchronization

signal connected_to_server
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 8

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var connected_peers: Array[int] = []


func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Host a new game server
func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)

	if error != OK:
		print("Failed to create server: ", error)
		return error

	multiplayer.multiplayer_peer = peer
	is_host = true
	connected_peers.append(1)  # Server is always peer ID 1

	print("=== SERVER STARTED on port %d ===" % port)
	print("Waiting for players to connect...")
	print("Other instances can join with: localhost:%d" % port)
	return OK


## Join an existing game
func join_game(address: String = "localhost", port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)

	if error != OK:
		print("Failed to create client: ", error)
		return error

	multiplayer.multiplayer_peer = peer
	is_host = false

	print("=== CONNECTING to %s:%d ===" % [address, port])
	return OK


## Disconnect from the current game
func disconnect_game() -> void:
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	print("=== DISCONNECTED ===")


## Check if we're currently in a multiplayer session
func is_multiplayer_active() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Get our peer ID
func get_my_peer_id() -> int:
	if multiplayer.multiplayer_peer:
		return multiplayer.get_unique_id()
	return 0


## Signal handlers
func _on_peer_connected(id: int) -> void:
	print("Player connected: Peer ID %d" % id)
	connected_peers.append(id)
	player_connected.emit(id)

	# If we're the host, send current game state to new player
	if is_host:
		_sync_state_to_peer.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: Peer ID %d" % id)
	connected_peers.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("=== CONNECTED TO SERVER ===")
	print("My Peer ID: %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	print("=== CONNECTION FAILED ===")
	peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("=== SERVER DISCONNECTED ===")
	peer = null
	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	server_disconnected.emit()


## Sync current game state to a newly connected peer
@rpc("authority", "call_local", "reliable")
func _sync_state_to_peer() -> void:
	# This will be called on the new client
	# The host will send object data via other RPCs
	print("Receiving game state sync...")


## RPC: Spawn object on remote clients only (local already spawned)
@rpc("any_peer", "call_remote", "reliable")
func spawn_object_networked(object_type: String, pos_x: float, pos_y: float, pos_z: float, object_id: int) -> void:
	var pos = Vector3(pos_x, pos_y, pos_z)
	var object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager:
		match object_type:
			"miniature":
				# Pass broadcast=false to prevent re-broadcasting
				var obj = object_manager.spawn_miniature(pos, false, object_id)
				if obj:
					obj.set_meta("network_id", object_id)
			"terrain":
				# Pass broadcast=false to prevent re-broadcasting
				var obj = object_manager.spawn_terrain(pos, false, object_id)
				if obj:
					obj.set_meta("network_id", object_id)


## RPC: Move object on remote clients only (local already moved)
@rpc("any_peer", "call_remote", "unreliable_ordered")
func move_object_networked(object_id: int, pos_x: float, pos_y: float, pos_z: float) -> void:
	var object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager:
		for child in object_manager.get_children():
			if child.has_meta("network_id") and child.get_meta("network_id") == object_id:
				child.global_position = Vector3(pos_x, pos_y, pos_z)
				break


## RPC: Clear all objects on remote clients only (local already cleared)
@rpc("any_peer", "call_remote", "reliable")
func clear_objects_networked() -> void:
	var object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager:
		# Pass broadcast=false to prevent re-broadcasting
		object_manager.clear_all_objects(false)


## Helper to broadcast spawn to all peers (local spawn already happened)
func broadcast_spawn(object_type: String, pos: Vector3, object_id: int) -> void:
	if is_multiplayer_active():
		spawn_object_networked.rpc(object_type, pos.x, pos.y, pos.z, object_id)
	# No else needed - local spawn already happened before this is called


## Helper to broadcast movement to all peers
func broadcast_move(object_id: int, pos: Vector3) -> void:
	if is_multiplayer_active():
		move_object_networked.rpc(object_id, pos.x, pos.y, pos.z)


## Helper to broadcast clear to all peers
func broadcast_clear() -> void:
	if is_multiplayer_active():
		clear_objects_networked.rpc()
