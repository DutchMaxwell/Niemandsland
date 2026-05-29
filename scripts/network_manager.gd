extends Node
## Network Manager for OpenTTS Multiplayer
## Handles hosting, joining, and basic state synchronization

signal connected_to_server
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

# Signals for remote state updates (emitted when RPCs arrive)
signal remote_wounds_updated(model: ModelInstance)
signal remote_activation_updated(game_unit: GameUnit)
signal remote_unit_marker_updated(game_unit: GameUnit, marker_name: String, add: bool, color: Color)
signal remote_model_marker_updated(model: ModelInstance, marker_name: String, add: bool, color: Color)
signal remote_casts_updated(game_unit: GameUnit)
signal remote_unit_deleted(game_unit: GameUnit)
signal remote_round_advanced()

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 8

## How often (seconds) to poll connection health
const CONNECTION_POLL_INTERVAL: float = 2.0

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var connected_peers: Array[int] = []

## Connection health tracking
var _last_connection_status: int = -1
var _poll_timer: float = 0.0
var _rpc_error_count: int = 0


func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	var mp = multiplayer.multiplayer_peer
	if not mp or not mp is MultiplayerPeer:
		return

	_poll_timer += delta
	if _poll_timer < CONNECTION_POLL_INTERVAL:
		return
	_poll_timer = 0.0

	var status = mp.get_connection_status()
	if status != _last_connection_status:
		var status_name = _connection_status_name(status)
		var old_name = _connection_status_name(_last_connection_status)
		push_warning("[Network] Connection status changed: %s -> %s" % [old_name, status_name])
		_last_connection_status = status

		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			push_warning("[Network] Peer reports DISCONNECTED (rpc_errors=%d, peers=%s)" % [_rpc_error_count, str(connected_peers)])


func _connection_status_name(status: int) -> String:
	match status:
		MultiplayerPeer.CONNECTION_DISCONNECTED: return "DISCONNECTED"
		MultiplayerPeer.CONNECTION_CONNECTING: return "CONNECTING"
		MultiplayerPeer.CONNECTION_CONNECTED: return "CONNECTED"
		_: return "UNKNOWN(%d)" % status


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
	_last_connection_status = peer.get_connection_status()
	_rpc_error_count = 0

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
	_last_connection_status = peer.get_connection_status()
	_rpc_error_count = 0

	print("=== CONNECTING to %s:%d ===" % [address, port])
	return OK


## Disconnect from the current game
func disconnect_game() -> void:
	print("[Network] disconnect_game() called (rpc_errors=%d)" % _rpc_error_count)
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	_last_connection_status = -1
	print("[Network] === DISCONNECTED ===")


## Validate that the peer is still connected before sending an RPC.
## Returns false and logs a warning if the connection is no longer usable.
## Uses multiplayer.multiplayer_peer (not the local `peer` var) so it works
## for both ENet (LAN) and RelayMultiplayerPeer (internet) connections.
func _validate_rpc_ready(context: String = "") -> bool:
	var mp = multiplayer.multiplayer_peer
	if not mp or not mp is MultiplayerPeer:
		_rpc_error_count += 1
		if _rpc_error_count <= 5 or _rpc_error_count % 50 == 0:
			push_warning("[Network] RPC blocked (%s): no multiplayer peer (error #%d)" % [context, _rpc_error_count])
		return false

	var status = mp.get_connection_status()
	if status != MultiplayerPeer.CONNECTION_CONNECTED:
		_rpc_error_count += 1
		if _rpc_error_count <= 5 or _rpc_error_count % 50 == 0:
			push_warning("[Network] RPC blocked (%s): status=%s (error #%d)" % [context, _connection_status_name(status), _rpc_error_count])
		return false

	return true


## Check if we're currently in a multiplayer session (works for ENet and Relay)
func is_multiplayer_active() -> bool:
	var mp = multiplayer.multiplayer_peer
	return mp != null and mp is MultiplayerPeer and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Get our peer ID
func get_my_peer_id() -> int:
	if multiplayer.multiplayer_peer:
		return multiplayer.get_unique_id()
	return 0


## Signal handlers
func _on_peer_connected(id: int) -> void:
	print("[Network] Player connected: Peer ID %d (total peers: %d)" % [id, connected_peers.size() + 1])
	connected_peers.append(id)
	player_connected.emit(id)
	# State sync is handled by main.gd via the player_connected signal


func _on_peer_disconnected(id: int) -> void:
	push_warning("[Network] Player disconnected: Peer ID %d (remaining peers: %d, rpc_errors=%d)" % [id, connected_peers.size() - 1, _rpc_error_count])
	connected_peers.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_last_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	print("[Network] === CONNECTED TO SERVER ===")
	print("[Network] My Peer ID: %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	push_warning("[Network] === CONNECTION FAILED === (rpc_errors=%d)" % _rpc_error_count)
	peer = null
	multiplayer.multiplayer_peer = null
	_last_connection_status = -1
	connection_failed.emit()


func _on_server_disconnected() -> void:
	push_warning("[Network] === SERVER DISCONNECTED === (rpc_errors=%d, was_host=%s)" % [_rpc_error_count, is_host])
	peer = null
	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	_last_connection_status = -1
	server_disconnected.emit()


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
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_spawn"):
		return
	spawn_object_networked.rpc(object_type, pos.x, pos.y, pos.z, object_id)


## Helper to broadcast movement to all peers
func broadcast_move(object_id: int, pos: Vector3) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_move"):
		return
	move_object_networked.rpc(object_id, pos.x, pos.y, pos.z)


## Helper to broadcast multiple object movements in a single RPC
func broadcast_move_batch(batch: Array) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_move_batch"):
		return
	move_objects_batch_networked.rpc(batch)


## RPC: Move multiple objects in one message. Format: [id, x, y, z, id, x, y, z, ...]
@rpc("any_peer", "call_remote", "unreliable_ordered")
func move_objects_batch_networked(batch: Array) -> void:
	var om := get_node_or_null("/root/Main/ObjectManager")
	if not om:
		return
	# Build lookup once for efficiency
	var id_to_node: Dictionary = {}
	for child in om.get_children():
		if child.has_meta("network_id"):
			id_to_node[int(child.get_meta("network_id"))] = child
	# Apply positions: batch = [id, x, y, z, id, x, y, z, ...]
	var i := 0
	while i + 3 < batch.size():
		var obj_id := int(batch[i])
		var node: Node3D = id_to_node.get(obj_id)
		if node:
			node.global_position = Vector3(float(batch[i + 1]), float(batch[i + 2]), float(batch[i + 3]))
		i += 4


## Helper to broadcast clear to all peers
func broadcast_clear() -> void:
	if is_multiplayer_active():
		clear_objects_networked.rpc()


# ===== GameUnit State Synchronization =====

## Reference to army manager (set by main.gd)
var army_manager: OPRArmyManager = null


## RPC: Sync unit activation state
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_activation(unit_id: String, activated: bool, activation_round: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		game_unit.is_activated = activated
		game_unit.activation_round = activation_round
		print("[Network] Unit %s activation: %s (round %d)" % [game_unit.get_name(), activated, activation_round])
		remote_activation_updated.emit(game_unit)


## RPC: Sync round advancement (resets activations + adds caster points on this peer)
@rpc("any_peer", "call_remote", "reliable")
func sync_round_advance() -> void:
	if army_manager:
		army_manager.advance_round()
		remote_round_advanced.emit()


## RPC: Sync model wounds
@rpc("any_peer", "call_remote", "reliable")
func sync_model_wounds(unit_id: String, model_index: int, wounds: int, is_alive: bool) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		var model = game_unit.get_model(model_index)
		if model:
			model.wounds_current = wounds
			model.is_alive = is_alive

			# Update node visibility
			if model.node and is_instance_valid(model.node):
				model.node.visible = is_alive

			print("[Network] Model %d wounds: %d/%d (alive: %s)" % [model_index + 1, wounds, model.wounds_max, is_alive])
			remote_wounds_updated.emit(model)


## RPC: Sync model marker (add or remove)
@rpc("any_peer", "call_remote", "reliable")
func sync_model_marker(unit_id: String, model_index: int, marker_name: String, add: bool, color: Color) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		var model = game_unit.get_model(model_index)
		if model:
			if add:
				model.add_marker(marker_name)
				print("[Network] Model %d: +marker '%s'" % [model_index + 1, marker_name])
			else:
				model.remove_marker(marker_name)
				print("[Network] Model %d: -marker '%s'" % [model_index + 1, marker_name])
			remote_model_marker_updated.emit(model, marker_name, add, color)


## RPC: Sync unit marker (add or remove from all models)
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_marker(unit_id: String, marker_name: String, add: bool, color: Color) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		if add:
			game_unit.add_marker_to_all(marker_name)
			print("[Network] Unit %s: +marker '%s'" % [game_unit.get_name(), marker_name])
		else:
			game_unit.remove_marker_from_all(marker_name)
			print("[Network] Unit %s: -marker '%s'" % [game_unit.get_name(), marker_name])
		remote_unit_marker_updated.emit(game_unit, marker_name, add, color)


## RPC: Sync hero attachment
@rpc("any_peer", "call_remote", "reliable")
func sync_hero_attachment(hero_id: String, target_id: String) -> void:
	if not army_manager:
		return

	var hero = army_manager.get_game_unit_by_id(hero_id)
	if not hero:
		return

	if target_id.is_empty():
		# Detach hero
		EquipmentDistributor.detach_hero(hero)
		print("[Network] Hero %s detached" % hero.get_name())
	else:
		var target = army_manager.get_game_unit_by_id(target_id)
		if target:
			EquipmentDistributor.attach_hero_to_unit(hero, target)
			print("[Network] Hero %s attached to %s" % [hero.get_name(), target.get_name()])


## RPC: Sync unit casts
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_casts(unit_id: String, casts_current: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		game_unit.casts_current = casts_current
		print("[Network] Unit %s casts: %d" % [game_unit.get_name(), casts_current])
		remote_casts_updated.emit(game_unit)


## RPC: Sync unit deletion (mark all models dead)
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_delete(unit_id: String) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		for model in game_unit.models:
			model.is_alive = false
			model.wounds_current = 0
			if model.node and is_instance_valid(model.node):
				model.node.queue_free()
		print("[Network] Unit %s deleted" % game_unit.get_name())
		remote_unit_deleted.emit(game_unit)


## RPC: Sync object rotation (unreliable for performance)
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rotate_object_networked(object_id: int, rot_y: float) -> void:
	var object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager:
		for child in object_manager.get_children():
			if child.has_meta("network_id") and child.get_meta("network_id") == object_id:
				child.rotation.y = rot_y
				break


## RPC: Rotate multiple objects in one message. Format: [id, rot_y, id, rot_y, ...]
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rotate_objects_batch_networked(batch: Array) -> void:
	var om := get_node_or_null("/root/Main/ObjectManager")
	if not om:
		return
	var id_to_node: Dictionary = {}
	for child in om.get_children():
		if child.has_meta("network_id"):
			id_to_node[int(child.get_meta("network_id"))] = child
	var i := 0
	while i + 1 < batch.size():
		var obj_id := int(batch[i])
		var node: Node3D = id_to_node.get(obj_id)
		if node:
			node.rotation.y = float(batch[i + 1])
		i += 2


# ===== Broadcast Helpers for GameUnit State =====

## Broadcast unit activation change
## Broadcast a round advancement so every peer shares the same round.
func broadcast_round_advance() -> void:
	if is_multiplayer_active():
		sync_round_advance.rpc()


func broadcast_unit_activation(game_unit: GameUnit) -> void:
	if is_multiplayer_active() and game_unit:
		sync_unit_activation.rpc(game_unit.unit_id, game_unit.is_activated, game_unit.activation_round)


## Broadcast model wounds change
func broadcast_model_wounds(model: ModelInstance) -> void:
	if is_multiplayer_active() and model and model.unit:
		var game_unit = model.unit as GameUnit
		if game_unit:
			sync_model_wounds.rpc(game_unit.unit_id, model.model_index, model.wounds_current, model.is_alive)


## Broadcast model marker change. color carries custom-marker colors so remote
## peers render them correctly (ignored for built-in/state markers).
func broadcast_model_marker(model: ModelInstance, marker_name: String, add: bool, color: Color = Color.WHITE) -> void:
	if is_multiplayer_active() and model and model.unit:
		var game_unit = model.unit as GameUnit
		if game_unit:
			sync_model_marker.rpc(game_unit.unit_id, model.model_index, marker_name, add, color)


## Broadcast unit marker change (all models). color carries custom-marker colors.
func broadcast_unit_marker(game_unit: GameUnit, marker_name: String, add: bool, color: Color = Color.WHITE) -> void:
	if is_multiplayer_active() and game_unit:
		sync_unit_marker.rpc(game_unit.unit_id, marker_name, add, color)


## Broadcast unit casts change
func broadcast_unit_casts(game_unit: GameUnit) -> void:
	if is_multiplayer_active() and game_unit:
		sync_unit_casts.rpc(game_unit.unit_id, game_unit.casts_current)


## Broadcast unit deletion
func broadcast_unit_delete(game_unit: GameUnit) -> void:
	if is_multiplayer_active() and game_unit:
		sync_unit_delete.rpc(game_unit.unit_id)


## Broadcast object rotation
func broadcast_rotation(object_id: int, rot_y: float) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_rotation"):
		return
	rotate_object_networked.rpc(object_id, rot_y)


## Broadcast multiple object rotations in a single RPC
func broadcast_rotation_batch(batch: Array) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_rotation_batch"):
		return
	rotate_objects_batch_networked.rpc(batch)


## Broadcast hero attachment change
func broadcast_hero_attachment(hero: GameUnit, target: GameUnit) -> void:
	if is_multiplayer_active() and hero:
		var target_id = target.unit_id if target else ""
		sync_hero_attachment.rpc(hero.unit_id, target_id)


# ===== Player Presence Synchronization =====

## Signal emitted when a remote player's cursor position is received
signal remote_cursor_updated(peer_id: int, pos_x: float, pos_z: float)

## Signal emitted when a remote player's camera direction is received
signal remote_camera_updated(peer_id: int, yaw: float, pitch: float)

## Signal emitted when a remote player rolls dice
signal remote_dice_rolled(peer_id: int, dice_count: int, results: Array, total: int)


## RPC: Sync cursor position on table surface (high frequency, unreliable)
@rpc("any_peer", "call_remote", "unreliable")
func sync_cursor_position(pos_x: float, pos_z: float) -> void:
	var sender = multiplayer.get_remote_sender_id()
	remote_cursor_updated.emit(sender, pos_x, pos_z)


## RPC: Sync camera look direction (low frequency, unreliable)
@rpc("any_peer", "call_remote", "unreliable")
func sync_camera_direction(yaw: float, pitch: float) -> void:
	var sender = multiplayer.get_remote_sender_id()
	remote_camera_updated.emit(sender, yaw, pitch)


## RPC: Sync dice roll event (reliable — everyone must see the result)
@rpc("any_peer", "call_remote", "reliable")
func sync_dice_roll(dice_count: int, results: Array, total: int) -> void:
	var sender = multiplayer.get_remote_sender_id()
	print("[Network] Peer %d rolled %dd6: %s = %d" % [sender, dice_count, str(results), total])
	remote_dice_rolled.emit(sender, dice_count, results, total)


## Broadcast cursor position to all peers
func broadcast_cursor_position(pos: Vector3) -> void:
	if is_multiplayer_active():
		sync_cursor_position.rpc(pos.x, pos.z)


## Broadcast camera direction to all peers
func broadcast_camera_direction(yaw: float, pitch: float) -> void:
	if is_multiplayer_active():
		sync_camera_direction.rpc(yaw, pitch)


## Broadcast dice roll to all peers
func broadcast_dice_roll(dice_count: int, results: Array, total: int) -> void:
	if is_multiplayer_active():
		sync_dice_roll.rpc(dice_count, results, total)


# ===== Table Settings Synchronization =====

## Signal emitted when remote table settings change
signal remote_table_settings_changed(settings: Dictionary)


## RPC: Sync table settings (deployment type, visibility, etc.)
@rpc("authority", "call_remote", "reliable")
func sync_table_settings(settings: Dictionary) -> void:
	print("[Network] Received table settings: %s" % str(settings))
	remote_table_settings_changed.emit(settings)


## Broadcast table settings to all peers (host only)
func broadcast_table_settings(settings: Dictionary) -> void:
	if is_multiplayer_active() and multiplayer.is_server():
		sync_table_settings.rpc(settings)


# ===== Army Import Synchronization (Batched) =====

## Signals for batched army sync
signal remote_army_header_received(player_id: int, army_name: String, unit_count: int)
signal remote_army_unit_received(unit_data: Dictionary, objects_data: Array, player_id: int)
signal remote_army_complete_received(player_id: int)

## Delay between unit batch RPCs to stay under relay rate limit (120 msg/s).
## Must be high enough so that Godot's internal RPC fragmentation + this delay
## stays well below the limit. Presence broadcasts are paused during sync.
const ARMY_BATCH_DELAY_MS: int = 250


## RPC: Army sync header — announces incoming army import
@rpc("any_peer", "call_remote", "reliable")
func sync_army_header(player_id: int, army_name: String, unit_count: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	print("[Network] Army header from peer %d: '%s' (%d units, player_id=%d)" % [sender, army_name, unit_count, player_id])
	remote_army_header_received.emit(player_id, army_name, unit_count)


## RPC: Army sync unit — one unit + its model objects
@rpc("any_peer", "call_remote", "reliable")
func sync_army_unit(unit_data: Dictionary, objects_data: Array, player_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var unit_name: String = unit_data.get("unit_properties", {}).get("name", "?")
	print("[Network] Army unit from peer %d: '%s' (%d objects)" % [sender, unit_name, objects_data.size()])
	remote_army_unit_received.emit(unit_data, objects_data, player_id)


## RPC: Army sync complete — all units sent
@rpc("any_peer", "call_remote", "reliable")
func sync_army_complete(player_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	print("[Network] Army complete from peer %d (player_id=%d)" % [sender, player_id])
	remote_army_complete_received.emit(player_id)


## Broadcast army import in batches to all peers
func broadcast_army_batched(
	units_data: Array[Dictionary],
	objects_per_unit: Array[Array],
	player_id: int,
	army_name: String
) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_army_header"):
		return

	# 1. Header
	sync_army_header.rpc(player_id, army_name, units_data.size())

	# 2. Units with delay between each
	for i in range(units_data.size()):
		await get_tree().create_timer(ARMY_BATCH_DELAY_MS / 1000.0).timeout
		if not _validate_rpc_ready("broadcast_army_unit_%d" % i):
			return
		var objs: Array = objects_per_unit[i] if i < objects_per_unit.size() else []
		sync_army_unit.rpc(units_data[i], objs, player_id)

	# 3. Complete
	await get_tree().create_timer(ARMY_BATCH_DELAY_MS / 1000.0).timeout
	if _validate_rpc_ready("broadcast_army_complete"):
		sync_army_complete.rpc(player_id)


# ===== TTS Terrain Synchronization =====

## Signal emitted when a remote player spawns TTS terrain
signal remote_tts_terrain_spawned(mesh_url: String, diffuse_url: String,
	scale_x: float, scale_y: float, scale_z: float,
	pos_x: float, pos_y: float, pos_z: float, terrain_name: String)


## RPC: Sync TTS terrain spawn
@rpc("any_peer", "call_remote", "reliable")
func sync_tts_terrain_spawn(mesh_url: String, diffuse_url: String,
	scale_x: float, scale_y: float, scale_z: float,
	pos_x: float, pos_y: float, pos_z: float, terrain_name: String) -> void:
	var sender = multiplayer.get_remote_sender_id()
	print("[Network] Received TTS terrain spawn from peer %d: %s" % [sender, terrain_name])
	remote_tts_terrain_spawned.emit(mesh_url, diffuse_url,
		scale_x, scale_y, scale_z, pos_x, pos_y, pos_z, terrain_name)


## Broadcast TTS terrain spawn to all peers
func broadcast_tts_terrain_spawn(mesh_url: String, diffuse_url: String,
	scale: Vector3, pos: Vector3, terrain_name: String) -> void:
	if is_multiplayer_active():
		sync_tts_terrain_spawn.rpc(mesh_url, diffuse_url,
			scale.x, scale.y, scale.z, pos.x, pos.y, pos.z, terrain_name)



# ===== Camera Position Synchronization =====

## Signal emitted when a remote player's camera position is received
signal remote_camera_position_updated(peer_id: int, pos_x: float, pos_y: float, pos_z: float)


## RPC: Sync camera position (unreliable for performance)
@rpc("any_peer", "call_remote", "unreliable")
func sync_camera_position(pos_x: float, pos_y: float, pos_z: float) -> void:
	var sender = multiplayer.get_remote_sender_id()
	remote_camera_position_updated.emit(sender, pos_x, pos_y, pos_z)


## Broadcast camera position to all peers
func broadcast_camera_position(pos: Vector3) -> void:
	if is_multiplayer_active():
		sync_camera_position.rpc(pos.x, pos.y, pos.z)
