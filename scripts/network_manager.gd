extends Node
## Network Manager for Niemandsland Multiplayer
## Handles hosting, joining, and basic state synchronization

signal connected_to_server
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
## A decoded application command arrived over the hand-rolled command protocol (below @rpc, survives
## reconnects). Phase 1 of the netcode replatform; handlers subscribe and dispatch by `type`.
signal command_received(type: String, payload: Variant, from_peer: int)

## Emitted on the host once a joining peer has announced a matching game version.
## main.gd gates the full-state sync on this so mismatched peers never receive state.
signal peer_version_validated(peer_id: int)
## Emitted on a client when the host rejected us for a version mismatch.
signal version_rejected(host_version: String, my_version: String)
## Emitted on every peer when a returning identity token rebinds its canonical slot
## to a NEW transport peer_id. Consumers re-key their peer_id-keyed state old->new and
## evict-both the stale + eager presence BEFORE respawning (see main._on_peer_remapped).
signal peer_remapped(old_peer_id: int, new_peer_id: int, slot: int)
## Emitted on a guest when the host assigns/confirms our canonical slot.
signal slot_assigned(slot: int)

# Signals for remote state updates (emitted when RPCs arrive)
signal remote_wounds_updated(model: ModelInstance)
signal remote_activation_updated(game_unit: GameUnit)
signal remote_unit_marker_updated(game_unit: GameUnit, marker_name: String, add: bool, color: Color, value: int)
signal remote_model_marker_updated(model: ModelInstance, marker_name: String, add: bool, color: Color, value: int)
signal remote_unit_marker_value_updated(game_unit: GameUnit, marker_name: String, value: int)
signal remote_model_marker_value_updated(model: ModelInstance, marker_name: String, value: int)
signal remote_objective_owner_updated(index: int, owner: int)
signal remote_token_defined(token_name: String, color: Color, is_counter: bool, effect: String)
signal remote_token_edited(old_name: String, new_name: String, color: Color, effect: String)
signal remote_casts_updated(game_unit: GameUnit)
signal remote_sort_table_received
signal remote_unit_deleted(game_unit: GameUnit)
signal remote_round_advanced()

## Emitted when a player's display name becomes known/changes (peer_id -> name).
signal remote_player_name_updated(peer_id: int, player_name: String)
## Emitted on a guest when the host sends its chat message (peer_id -> text).
signal remote_chat_message(peer_id: int, text: String)


## How often (seconds) to poll connection health
const CONNECTION_POLL_INTERVAL: float = 2.0

## ProjectSettings key holding the release version (e.g. "0.3.0-alpha").
## Both ends must match exactly or the host refuses the join.
const VERSION_SETTING: String = "application/config/version"
## Grace period (seconds) for a joining peer to announce its version before the
## host kicks it. Covers a pre-handshake (old) client that never announces.
const VERSION_HANDSHAKE_TIMEOUT: float = 8.0

## Sentinel for slot_to_peer: the slot is RESERVED to its token but currently has no
## live peer (the occupant dropped; a rejoin with the same token reclaims it).
const SLOT_RESERVED_PEER: int = 0

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var connected_peers: Array[int] = []

## Peers (by id) that announced a matching version. Host-only.
var validated_peers: Dictionary = {}

## Display names by peer id. Host-authoritative: guests announce their own name to
## the host, the host owns the map and pushes the full roster to everyone.
var player_names: Dictionary = {}  # Dictionary[int, String]

# ===== Stable player identity (token -> slot) =====
# A SLOT is the durable identity (color, model ownership, network_id namespace all
# key off the slot, NOT the transport peer_id, which the relay re-issues on every
# guest rejoin). The host owns the authoritative maps; guests cache only their own
# assigned slot. Slots are monotonic and never recycled within a session, so an
# import-time opr_player_id stamp stays valid across a reconnect. A token's slot is
# RESERVED for the whole session (kept on disconnect) and cleared only on a genuine
# session end (disconnect_game), never on the auto-reconnect path.

## This client's stable identity token (cached from PlayerIdentity at _ready).
var _my_client_token: String = ""
## True only during a controlled peer-1 RPC-path re-handshake on a guest reconnect: suppresses the
## server_disconnected teardown + the peer-1 slot cleanup that the deliberate peer_disconnected(1)
## emit would otherwise trigger. See force_host_rpc_rehandshake().
var _reconnect_flush_active: bool = false
## Monotonic sequence number stamped on every outgoing command (for future ack/replay).
var _command_seq: int = 0
## Guest side: the slot the host assigned us (0 = not yet assigned).
var _my_assigned_slot: int = 0
## Host-only: token -> canonical slot (1..N). The stable identity.
var token_to_slot: Dictionary = {}   # Dictionary[String, int]
## Host-only: slot -> the peer_id that currently occupies it (SLOT_RESERVED_PEER = vacant).
var slot_to_peer: Dictionary = {}    # Dictionary[int, int]
## peer_id -> slot (host authoritative; mirrored on guests via remap). Reverse lookup
## for disconnect handling + ownership/colour resolution.
var peer_to_slot: Dictionary = {}    # Dictionary[int, int]
## Host-only: next slot for a never-before-seen token. Monotonic; never recycled.
var _next_slot: int = 2              # host is slot 1

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
	# Stable identity token, generated once per install and persisted (see PlayerIdentity).
	_my_client_token = PlayerIdentity.get_or_create_client_token()


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


## Disconnect from the current game
func disconnect_game() -> void:
	print("[Network] disconnect_game() called (rpc_errors=%d)" % _rpc_error_count)
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	validated_peers.clear()
	player_names.clear()
	# Genuine session end (NOT the auto-reconnect path, which goes through
	# internet_lobby.reconnect_to_room and never calls this): drop all identity maps so
	# a brand-new session starts clean and slots restart from 2.
	token_to_slot.clear()
	slot_to_peer.clear()
	peer_to_slot.clear()
	_next_slot = 2
	_my_assigned_slot = 0
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


## The stable player slot/identity for THIS client — color, model ownership and the
## army-import default key off THIS, not the raw transport peer_id (the relay re-issues
## a fresh peer id on every guest rejoin). The host is always slot 1; a guest returns
## its host-assigned slot. In an ACTIVE session before the slot is assigned it returns
## 0 (NOT the raw peer id) so callers can detect "pending" — the ownership gate fails
## open on 0, and slot-dependent user actions (army import) await assignment. Outside
## multiplayer (single-player) it falls back to the peer id, preserving prior behaviour.
func get_my_player_slot() -> int:
	if multiplayer.is_server():
		return 1
	if _my_assigned_slot > 0:
		return _my_assigned_slot
	if is_multiplayer_active():
		return 0  # slot assignment pending
	return get_my_peer_id()


## The canonical slot a given transport peer currently occupies (falls back to the
## peer id when unmapped, e.g. single-player or a pre-handshake peer).
func slot_for_peer(peer_id: int) -> int:
	return int(peer_to_slot.get(peer_id, peer_id))


## Host: claim slot 1 for ourselves (idempotent — also called on a rehost to restore
## our slot-1 binding). Keeps _next_slot past the host slot.
func seed_host_identity() -> void:
	if not multiplayer.is_server():
		return
	var host_peer := get_my_peer_id()  # 1
	token_to_slot[_my_client_token] = 1
	slot_to_peer[1] = host_peer
	peer_to_slot[host_peer] = 1
	if _next_slot < 2:
		_next_slot = 2


## Signal handlers
func _on_peer_connected(id: int) -> void:
	# Dedup: a relay host-rehost replay re-emits peer_connected for guests that
	# never left. Appending twice would put a phantom duplicate in connected_peers
	# (and the roster) — keep it a set (RC2).
	_bind_command_channel()  # host: bind the command stream when a peer appears
	var already := connected_peers.has(id)
	print("[Network] Player connected: Peer ID %d (total peers: %d, dup=%s)" % [id, connected_peers.size() + (0 if already else 1), already])
	if not already:
		connected_peers.append(id)
	player_connected.emit(id)
	# State sync is handled by main.gd via the player_connected signal — but only
	# after the version handshake. Arm the grace-period kick ONLY for a genuinely
	# new, unvalidated peer: re-arming it for an already-validated guest on a
	# rehost replay risks a spurious kick (RC6).
	if multiplayer.is_server() and not already and not is_peer_validated(id):
		get_tree().create_timer(VERSION_HANDSHAKE_TIMEOUT).timeout.connect(
			enforce_version_handshake_timeout.bind(id))


func _on_peer_disconnected(id: int) -> void:
	if _reconnect_flush_active and id == 1:
		return  # deliberate peer-1 cache flush on reconnect — not a real host disconnect
	push_warning("[Network] Player disconnected: Peer ID %d (remaining peers: %d, rpc_errors=%d)" % [id, connected_peers.size() - 1, _rpc_error_count])
	connected_peers.erase(id)
	validated_peers.erase(id)
	# Release the live transport binding but KEEP token_to_slot (that reservation is what
	# lets a rejoin reclaim the slot). Guard against a late stale old-socket close that
	# arrives AFTER a rebind already moved this slot to a newer peer — then drop nothing.
	if peer_to_slot.has(id):
		var slot: int = peer_to_slot[id]
		if int(slot_to_peer.get(slot, SLOT_RESERVED_PEER)) == id:
			slot_to_peer[slot] = SLOT_RESERVED_PEER  # vacant, still reserved to its token
			peer_to_slot.erase(id)
			player_names.erase(id)
	else:
		player_names.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_last_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	_bind_command_channel()  # guest: command stream is live as soon as the transport is
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
	if _reconnect_flush_active:
		return  # deliberate peer-1 cache flush on reconnect — keep the session alive
	push_warning("[Network] === SERVER DISCONNECTED === (rpc_errors=%d, was_host=%s)" % [_rpc_error_count, is_host])
	peer = null
	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	_last_connection_status = -1
	server_disconnected.emit()


# =============================================================================
# Version handshake
# =============================================================================
# Both ends must run the same release. On join the client announces its version
# to the host; the host rejects a mismatch (and a silent/old client after a
# timeout) so a 0.3.0 player can never share a table with a 0.3.1 player.

## The release string both ends compare (from project.godot config/version).
func get_game_version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, "unknown"))


## Whether a joining peer has passed the version handshake. Host-only.
func is_peer_validated(id: int) -> bool:
	return validated_peers.get(id, false)


## Client → host: announce our version right after connecting. The host replies
## by either validating us (state sync follows) or rejecting us.
## Guest reconnect: the relay handed us our OLD peer_id back, but SceneMultiplayer still holds the
## RPC path-id cache it negotiated with peer 1 (the host) over the now-dead socket. The host reset
## its side on our rejoin, so our next RPC (the re-announce) would carry a path id the host no longer
## knows ("ID not found in cache") and be dropped → version-kick. Force a re-negotiation by flushing
## peer 1 (a disconnect+connect that clears its cache), with the teardown + slot cleanup suppressed.
## Guest-only; must run right before the re-announce.
func force_host_rpc_rehandshake() -> void:
	if multiplayer.is_server():
		return
	var p = multiplayer.multiplayer_peer
	if p == null:
		return
	_reconnect_flush_active = true
	p.emit_signal("peer_disconnected", 1)
	p.emit_signal("peer_connected", 1)
	_reconnect_flush_active = false


# === Command protocol (Phase 1 — below @rpc, reconnect-safe) ===

## Idempotently connect to the relay peer's channel-1 command stream. Called from the connect
## handlers (both roles) + send_command, so the channel is live whenever a session is.
func _bind_command_channel() -> void:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp and mp.has_signal("command_received") and not mp.command_received.is_connected(_on_raw_command):
		mp.command_received.connect(_on_raw_command)


## Send an application command to `target_peer` (0 = broadcast to all other peers in the room).
## Routes over the relay's channel-1 frames, entirely below @rpc — no path-cache, survives a
## reconnect. Returns false if no relay transport is active. Payload must be plain Variant data.
func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or not mp.has_method("send_command"):
		return false
	_bind_command_channel()
	_command_seq += 1
	return mp.send_command(target_peer, MPCommand.encode(type, _command_seq, payload)) == OK


func _on_raw_command(from_peer: int, data: PackedByteArray) -> void:
	var env: Dictionary = MPCommand.decode(data)
	if env.is_empty():
		return
	var type: String = str(env.get("t", ""))
	# Built-in connectivity self-test (Phase 1 proof that the channel round-trips alongside @rpc;
	# harmless in production — a ping just gets a pong).
	if type == "cmd_ping":
		print("[CMD] ping from %d -> pong" % from_peer)
		send_command("cmd_pong", {}, from_peer)
		return
	if type == "cmd_pong":
		print("[CMD] pong from %d (command channel verified)" % from_peer)
		return
	command_received.emit(type, env.get("p", null), from_peer)


func announce_version_to_host() -> void:
	if multiplayer.is_server():
		return
	if not _validate_rpc_ready("announce_version"):
		return
	_rpc_announce_version.rpc_id(1, get_game_version(), _my_client_token)


## Host: kick a peer that never announced a (matching) version within the grace
## period. A pre-handshake client simply never calls _rpc_announce_version.
func enforce_version_handshake_timeout(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if is_peer_validated(peer_id):
		return
	if not connected_peers.has(peer_id):
		return  # already gone
	push_warning("[Network] Peer %d failed version handshake (no announce in %.0fs) — kicking" % [peer_id, VERSION_HANDSHAKE_TIMEOUT])
	_disconnect_peer_safe(peer_id)


## Disconnect a single peer if the active multiplayer peer supports it
## (ENet does; a relay peer may not — the client also self-disconnects on reject).
func _disconnect_peer_safe(id: int) -> void:
	var mp = multiplayer.multiplayer_peer
	if mp and mp.has_method("disconnect_peer"):
		mp.disconnect_peer(id)


## RPC (client → host): the joining peer announces its game version + stable identity
## token. The version check (and reject path) is unchanged and runs FIRST; only after
## validation do we resolve the token to a canonical slot. The client_token arg is
## optional so a pre-token (older) client still handshakes — it gets a fresh slot and
## is never eligible to reclaim/evict an existing one.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_announce_version(client_version: String, client_token: String = "") -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var host_version := get_game_version()
	if client_version != host_version:
		push_warning("[Network] Version mismatch: host=%s, peer %d=%s — rejecting" % [host_version, sender, client_version])
		_rpc_reject_version.rpc_id(sender, host_version)
		# Let the reject RPC flush, then drop the peer host-side.
		get_tree().create_timer(0.5).timeout.connect(_disconnect_peer_safe.bind(sender))
		return
	validated_peers[sender] = true
	# Resolve the stable slot SYNCHRONOUSLY (no await) so concurrent rejoins bind
	# atomically, BEFORE the state-sync that main.gd runs on peer_version_validated.
	var slot := _resolve_slot_for_token(client_token, sender)
	_rpc_assign_slot.rpc_id(sender, slot)  # guest caches it for get_my_player_slot()
	print("[Network] Peer %d passed handshake (%s) -> slot %d" % [sender, host_version, slot])
	peer_version_validated.emit(sender)


## RPC (host → client): the host refuses us because our versions differ.
@rpc("authority", "call_remote", "reliable")
func _rpc_reject_version(host_version: String) -> void:
	push_warning("[Network] Host rejected us: host=%s, we=%s" % [host_version, get_game_version()])
	version_rejected.emit(host_version, get_game_version())


## Host: map a client token to its canonical slot, (re)binding the transport peer_id.
## STRICTLY SYNCHRONOUS (no await) so each announce binds atomically even when two
## guests rejoin in the same burst. A KNOWN token REBINDS its slot to the new peer and
## broadcasts a remap (applied on every peer incl. the host) so all peer_id-keyed
## presence is re-keyed + evicted before the new avatar spawns. An empty/unknown token
## gets a fresh monotonic slot and can never rebind/evict an existing one. Slot 1 is
## the host's: a guest token (sender != 1) resolving to slot 1 is refused a fresh slot.
func _resolve_slot_for_token(token: String, new_peer: int) -> int:
	if token.is_empty():
		return _allocate_fresh_slot(new_peer)  # legacy/anonymous: no reconnect identity
	if token_to_slot.has(token):
		var slot: int = token_to_slot[token]
		if slot == 1 and new_peer != 1:
			# Never hand the host slot to a guest; RE-HOME this token to a fresh slot so it
			# stays stable across THIS guest's future rejoins (not refused slot 1 each time).
			token_to_slot.erase(token)
			return _allocate_fresh_slot(new_peer, token)
		var old_peer: int = int(slot_to_peer.get(slot, SLOT_RESERVED_PEER))
		slot_to_peer[slot] = new_peer
		if old_peer != SLOT_RESERVED_PEER:
			peer_to_slot.erase(old_peer)
		peer_to_slot[new_peer] = slot
		# Fire the remap whenever the transport id actually changed — INCLUDING a reclaim of
		# a reserved-vacant slot (old_peer == SLOT_RESERVED_PEER), the primary clean-
		# disconnect-then-rejoin path. _on_peer_remapped is the ONLY path that re-colours the
		# avatar off the slot on every observer, so suppressing it there left the reconnected
		# guest in its raw-peer_id colour. The handler tolerates a reserved/absent old peer;
		# the local self-spawn is guarded in main (avatars are remote-only).
		if old_peer != new_peer:
			if is_multiplayer_active():
				_rpc_remap_peer.rpc(old_peer, new_peer, slot)
			_rpc_remap_peer(old_peer, new_peer, slot)  # apply locally (host)
		return slot
	return _allocate_fresh_slot(new_peer, token)


## Host: hand the next monotonic slot to a never-seen (or anonymous) peer. A non-empty
## token reserves the slot for the whole session; an empty token does not (anonymous).
func _allocate_fresh_slot(new_peer: int, token: String = "") -> int:
	var slot := _next_slot
	_next_slot += 1
	if not token.is_empty():
		token_to_slot[token] = slot
	slot_to_peer[slot] = new_peer
	peer_to_slot[new_peer] = slot
	return slot


## RPC (host → one guest): the canonical slot the host assigned this token, cached so
## get_my_player_slot() answers locally.
@rpc("authority", "call_remote", "reliable")
func _rpc_assign_slot(slot: int) -> void:
	_my_assigned_slot = slot
	peer_to_slot[get_my_peer_id()] = slot
	slot_assigned.emit(slot)


## RPC (host → all): a returning token rebound its slot from old_peer to new_peer.
## Total + idempotent + self-healing: re-keys every peer_id-keyed dict old->new,
## tolerates old absent (late third-guest) and new unknown (records the binding only),
## and emits peer_remapped so main.gd evicts-both + respawns one presence.
@rpc("authority", "call_remote", "reliable")
func _rpc_remap_peer(old_peer: int, new_peer: int, slot: int) -> void:
	if old_peer == new_peer:
		return
	# Authoritative binding, regardless of prior local knowledge.
	peer_to_slot.erase(old_peer)
	peer_to_slot[new_peer] = slot
	slot_to_peer[slot] = new_peer
	if player_names.has(old_peer):
		player_names[new_peer] = player_names[old_peer]
		player_names.erase(old_peer)
	if validated_peers.has(old_peer):
		validated_peers[new_peer] = true
		validated_peers.erase(old_peer)
	connected_peers.erase(old_peer)
	# On the RETURNING guest new_peer == self, and connected_peers must exclude self —
	# only record the new id as a connected peer on observers (host + other guests).
	if new_peer != get_my_peer_id() and not connected_peers.has(new_peer):
		connected_peers.append(new_peer)
	peer_remapped.emit(old_peer, new_peer, slot)


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


## RPC: Spawn a free-placed sandbox terrain piece on remote clients (local already spawned).
## The object_id doubles as the cluster scatter seed, so forests/minefields build identically
## on every peer; move/rotate then reuse the generic network-id paths.
@rpc("any_peer", "call_remote", "reliable")
func spawn_sandbox_terrain_networked(prop_id: String, kind: int, pos_x: float, pos_y: float, pos_z: float, object_id: int) -> void:
	var object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager:
		object_manager.spawn_sandbox_terrain(prop_id, kind, Vector3(pos_x, pos_y, pos_z), false, object_id)


## Helper to broadcast a sandbox terrain spawn to all peers (local spawn already happened).
func broadcast_sandbox_terrain_spawn(prop_id: String, kind: int, pos: Vector3, object_id: int) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_sandbox_terrain_spawn"):
		return
	spawn_sandbox_terrain_networked.rpc(prop_id, kind, pos.x, pos.y, pos.z, object_id)


# === Persistent shared rulers (pinned measurements) ===
# Mirrors the spawn/clear pattern above: each RPC is reliable and resolved on
# /root/Main/PinnedRulers; the ruler is coloured by its OWNER on every client, so the
# opponent sees whose it is. Session-only (never written to the .nml save).

## Broadcast a pinned ruler to all peers (the owner already added it locally).
func broadcast_ruler_pin(id: int, owner_peer: int, from_pos: Vector3, to_pos: Vector3,
		distance_inches: float, blocked: bool) -> void:
	if not is_multiplayer_active() or not _validate_rpc_ready("broadcast_ruler_pin"):
		return
	pin_ruler_networked.rpc(id, owner_peer, from_pos.x, from_pos.y, from_pos.z,
			to_pos.x, to_pos.y, to_pos.z, distance_inches, blocked)


@rpc("any_peer", "call_remote", "reliable")
func pin_ruler_networked(id: int, owner_peer: int, fx: float, fy: float, fz: float,
		tx: float, ty: float, tz: float, distance_inches: float, blocked: bool) -> void:
	var pr := get_node_or_null("/root/Main/PinnedRulers")
	if pr:
		pr.add_ruler(id, owner_peer, Vector3(fx, fy, fz), Vector3(tx, ty, tz),
				distance_inches, blocked)


func broadcast_ruler_clear(id: int) -> void:
	if not is_multiplayer_active() or not _validate_rpc_ready("broadcast_ruler_clear"):
		return
	clear_ruler_networked.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func clear_ruler_networked(id: int) -> void:
	var pr := get_node_or_null("/root/Main/PinnedRulers")
	if pr:
		pr.remove_ruler(id)


func broadcast_ruler_clear_owner(owner_peer: int) -> void:
	if not is_multiplayer_active() or not _validate_rpc_ready("broadcast_ruler_clear_owner"):
		return
	clear_rulers_by_owner_networked.rpc(owner_peer)


@rpc("any_peer", "call_remote", "reliable")
func clear_rulers_by_owner_networked(owner_peer: int) -> void:
	var pr := get_node_or_null("/root/Main/PinnedRulers")
	if pr:
		pr.clear_owner(owner_peer)


func broadcast_ruler_clear_all() -> void:
	if not is_multiplayer_active() or not _validate_rpc_ready("broadcast_ruler_clear_all"):
		return
	clear_all_rulers_networked.rpc()


@rpc("any_peer", "call_remote", "reliable")
func clear_all_rulers_networked() -> void:
	var pr := get_node_or_null("/root/Main/PinnedRulers")
	if pr:
		pr.clear_all()


## Replay the host's current rulers to one freshly-joined peer (late-joiner sync).
func sync_rulers_to_peer(peer_id: int) -> void:
	if not is_multiplayer_active():
		return
	var pr := get_node_or_null("/root/Main/PinnedRulers")
	if pr == null:
		return
	for d in pr.serialize():
		pin_ruler_networked.rpc_id(peer_id, int(d["id"]), int(d["owner"]),
				float(d["fx"]), float(d["fy"]), float(d["fz"]),
				float(d["tx"]), float(d["ty"]), float(d["tz"]),
				float(d["dist"]), bool(d["blocked"]))


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
		remote_activation_updated.emit(game_unit)


## RPC: Sync round advancement (resets activations + adds caster points on this peer)
@rpc("any_peer", "call_remote", "reliable")
func sync_round_advance() -> void:
	if army_manager:
		army_manager.advance_round()
		remote_round_advanced.emit()


## RPC: Sync "Sort Table" (reset every unit to its import state + positions). The receiver re-runs
## the reset LOCALLY — each model's import_position is part of the synced game-unit state, so both
## peers land identically. A command (not a position batch) so the status/wound/marker reset
## mirrors too. The handler runs sort_table(broadcast=false) to avoid an echo loop.
@rpc("any_peer", "call_remote", "reliable")
func sync_sort_table() -> void:
	remote_sort_table_received.emit()


## Broadcast a Sort Table action to all peers.
func broadcast_sort_table() -> void:
	if is_multiplayer_active():
		sync_sort_table.rpc()


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
				# Regiments (AoF:R): close/re-open ranks to match the host.
				if model.node.has_meta("regiment_tray"):
					var _tray = model.node.get_meta("regiment_tray")
					if is_instance_valid(_tray) and _tray.has_method("reform_from_unit"):
						_tray.reform_from_unit(game_unit)

			remote_wounds_updated.emit(model)


## RPC: Sync model marker (add or remove). value >= 0 marks a counter and seeds it.
@rpc("any_peer", "call_remote", "reliable")
func sync_model_marker(unit_id: String, model_index: int, marker_name: String, add: bool, color: Color, value: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		var model = game_unit.get_model(model_index)
		if model:
			if add:
				model.add_marker(marker_name)
			else:
				model.remove_marker(marker_name)
			remote_model_marker_updated.emit(model, marker_name, add, color, value)


## RPC: Sync unit marker (add or remove from all models). value >= 0 = counter.
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_marker(unit_id: String, marker_name: String, add: bool, color: Color, value: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		if add:
			game_unit.add_marker_to_all(marker_name)
		else:
			game_unit.remove_marker_from_all(marker_name)
		remote_unit_marker_updated.emit(game_unit, marker_name, add, color, value)


## RPC: Sync a counter marker's value change on a single model.
@rpc("any_peer", "call_remote", "reliable")
func sync_model_marker_value(unit_id: String, model_index: int, marker_name: String, value: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		var model = game_unit.get_model(model_index)
		if model:
			remote_model_marker_value_updated.emit(model, marker_name, value)


## RPC: Sync a counter marker's value change on all models of a unit.
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_marker_value(unit_id: String, marker_name: String, value: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		remote_unit_marker_value_updated.emit(game_unit, marker_name, value)


## RPC: Sync a mission objective's owner (any peer can capture objectives).
@rpc("any_peer", "call_remote", "reliable")
func sync_objective_owner(index: int, owner_id: int) -> void:
	remote_objective_owner_updated.emit(index, owner_id)


## RPC: Sync a custom-token library definition (created or color/effect change).
@rpc("any_peer", "call_remote", "reliable")
func sync_token_define(token_name: String, color: Color, is_counter: bool, effect: String) -> void:
	remote_token_defined.emit(token_name, color, is_counter, effect)


## RPC: Sync a custom-token edit (rename and/or color/effect change).
@rpc("any_peer", "call_remote", "reliable")
func sync_token_edit(old_name: String, new_name: String, color: Color, effect: String) -> void:
	remote_token_edited.emit(old_name, new_name, color, effect)


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
	else:
		var target = army_manager.get_game_unit_by_id(target_id)
		if target:
			EquipmentDistributor.attach_hero_to_unit(hero, target)


## RPC: Sync unit casts
@rpc("any_peer", "call_remote", "reliable")
func sync_unit_casts(unit_id: String, casts_current: int) -> void:
	if not army_manager:
		return

	var game_unit = army_manager.get_game_unit_by_id(unit_id)
	if game_unit:
		game_unit.casts_current = casts_current
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
## peers render them correctly (ignored for built-in/state markers). value >= 0
## marks a counter marker and seeds its starting number on add.
func broadcast_model_marker(model: ModelInstance, marker_name: String, add: bool, color: Color = Color.WHITE, value: int = -1) -> void:
	if is_multiplayer_active() and model and model.unit:
		var game_unit = model.unit as GameUnit
		if game_unit:
			sync_model_marker.rpc(game_unit.unit_id, model.model_index, marker_name, add, color, value)


## Broadcast unit marker change (all models). color carries custom-marker colors.
func broadcast_unit_marker(game_unit: GameUnit, marker_name: String, add: bool, color: Color = Color.WHITE, value: int = -1) -> void:
	if is_multiplayer_active() and game_unit:
		sync_unit_marker.rpc(game_unit.unit_id, marker_name, add, color, value)


## Broadcast a counter marker's value change on a single model.
func broadcast_model_marker_value(model: ModelInstance, marker_name: String, value: int) -> void:
	if is_multiplayer_active() and model and model.unit:
		var game_unit = model.unit as GameUnit
		if game_unit:
			sync_model_marker_value.rpc(game_unit.unit_id, model.model_index, marker_name, value)


## Broadcast a counter marker's value change on all models of a unit.
func broadcast_unit_marker_value(game_unit: GameUnit, marker_name: String, value: int) -> void:
	if is_multiplayer_active() and game_unit:
		sync_unit_marker_value.rpc(game_unit.unit_id, marker_name, value)


## Broadcast a mission objective owner change (any peer may capture).
func broadcast_objective_owner(index: int, owner_id: int) -> void:
	if is_multiplayer_active():
		sync_objective_owner.rpc(index, owner_id)


## Broadcast a custom-token library definition (create / color / effect).
func broadcast_token_define(token_name: String, color: Color, is_counter: bool, effect: String) -> void:
	if is_multiplayer_active():
		sync_token_define.rpc(token_name, color, is_counter, effect)


## Broadcast a custom-token edit (rename and/or color/effect change).
func broadcast_token_edit(old_name: String, new_name: String, color: Color, effect: String) -> void:
	if is_multiplayer_active():
		sync_token_edit.rpc(old_name, new_name, color, effect)


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

## Signal emitted when a remote player rolls dice. `results` carries one face
## value per die; `context` is the roll-context Dictionary (DiceRules.CTX_*:
## success target, modifier, reroll mode/count) so every client renders the
## same success evaluation and log entry.
signal remote_dice_rolled(peer_id: int, results: Array, context: Dictionary)


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
func sync_dice_roll(results: Array, context: Dictionary) -> void:
	var sender = multiplayer.get_remote_sender_id()
	remote_dice_rolled.emit(sender, results, context)


## Broadcast cursor position to all peers
func broadcast_cursor_position(pos: Vector3) -> void:
	if is_multiplayer_active():
		sync_cursor_position.rpc(pos.x, pos.z)


## Broadcast camera direction to all peers
func broadcast_camera_direction(yaw: float, pitch: float) -> void:
	if is_multiplayer_active():
		sync_camera_direction.rpc(yaw, pitch)


## Broadcast dice roll to all peers
func broadcast_dice_roll(results: Array, context: Dictionary) -> void:
	if is_multiplayer_active():
		sync_dice_roll.rpc(results, context)


# ===== Player names (host-authoritative roster) =====

## RPC (guest → host): a peer announces its own display name. The host sanitizes
## it at the trust boundary (a guest sends a raw string), records it and
## re-publishes the full roster so every peer learns it.
@rpc("any_peer", "call_remote", "reliable")
func sync_player_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var clean := PlayerIdentity.sanitize(player_name)
	player_names[sender] = clean
	remote_player_name_updated.emit(sender, clean)
	_publish_roster()


## RPC (host → guest, authority): the host pushes the whole name roster. The guest
## adopts it and emits one update per entry so the UI refreshes.
@rpc("authority", "call_remote", "reliable")
func sync_player_roster(roster: Dictionary) -> void:
	for id: int in roster:
		player_names[id] = roster[id]
		remote_player_name_updated.emit(id, roster[id])


## Guest → host: announce our own name (no-op as host; the host seeds its own name
## locally). Sent right after the version handshake is ANNOUNCED (not yet confirmed):
## a version-mismatched peer's name is tolerated on the host and dropped with it on
## disconnect (player_names.erase in _on_peer_disconnected), so no cleanup is missed.
func broadcast_player_name(player_name: String) -> void:
	if multiplayer.is_server() or not is_multiplayer_active():
		return
	sync_player_name.rpc_id(1, player_name)


## Host: record our own name and (if peers are present) publish the roster.
func set_host_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	player_names[get_my_peer_id()] = player_name
	remote_player_name_updated.emit(get_my_peer_id(), player_name)
	_publish_roster()


## Host: send the full roster to one freshly validated peer (called from main.gd
## on peer_version_validated, alongside the state sync).
func push_roster_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not is_multiplayer_active():
		return
	sync_player_roster.rpc_id(peer_id, player_names)


## Host: re-publish the whole roster to every connected peer.
func _publish_roster() -> void:
	if not multiplayer.is_server() or not is_multiplayer_active():
		return
	sync_player_roster.rpc(player_names)


# ===== In-game chat =====

## Longest chat message kept; the rest is clipped. Guards the log + relay frame.
const MAX_CHAT_LEN: int = 200


## Strips control chars (keeps chat one-line) and clamps the length. Applied on
## both send and receive so a crafted peer can't overflow the log.
static func _clean_chat(text: String) -> String:
	var cleaned := ""
	for c: String in text:
		if c.unicode_at(0) >= 32:
			cleaned += c
	cleaned = cleaned.strip_edges()
	return cleaned.substr(0, MAX_CHAT_LEN)


## RPC: a player's chat message reaches every other peer (broadcast, reliable).
@rpc("any_peer", "call_remote", "reliable")
func sync_chat_message(text: String) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var cleaned := _clean_chat(text)
	if not cleaned.is_empty():
		remote_chat_message.emit(sender, cleaned)


## Broadcast a chat message to all peers and return the cleaned text, so the
## sender's local echo is identical to what every other peer receives.
func broadcast_chat_message(text: String) -> String:
	var cleaned := _clean_chat(text)
	if not cleaned.is_empty() and is_multiplayer_active():
		sync_chat_message.rpc(cleaned)
	return cleaned


# ===== Table Settings Synchronization =====

## Signal emitted when remote table settings change
signal remote_table_settings_changed(settings: Dictionary)


## RPC: Sync table settings (deployment type, visibility, biome, terrain layout,
## objectives, etc.). Accepted from any peer so guest-side map-layout edits also
## propagate — table configuration is collaborative, not host-only.
@rpc("any_peer", "call_remote", "reliable")
func sync_table_settings(settings: Dictionary) -> void:
	print("[Network] Received table settings: %s" % str(settings))
	remote_table_settings_changed.emit(settings)


## Broadcast table settings to all peers. Any participant may push table changes
## (matches the plain-broadcast pattern used by every other object sync).
func broadcast_table_settings(settings: Dictionary) -> void:
	if is_multiplayer_active():
		sync_table_settings.rpc(settings)


# ===== Generic Object Spawn / Visibility Synchronization =====

## RPC: Reconstruct a copied/pasted object on remote peers from its serialized
## form. Reuses SaveManager._deserialize_object so every supported object type
## (terrain, custom model, miniature, generated terrain, TTS) round-trips with
## the same network_id, keeping later move/delete syncs aligned.
@rpc("any_peer", "call_remote", "reliable")
func spawn_object_data_networked(obj_data: Dictionary) -> void:
	var main = get_node_or_null("/root/Main")
	if main == null or main.save_manager == null:
		return
	await main.save_manager._deserialize_object(obj_data)


## Broadcast a freshly created (pasted/duplicated) object to all peers.
func broadcast_object_data_spawn(obj_data: Dictionary) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_object_data_spawn"):
		return
	spawn_object_data_networked.rpc(obj_data)


## RPC: Mirror a generic object's visibility (delete = hide, undo = show) by
## network_id. OPR unit models keep using sync_model_wounds; this covers the
## plain nodes (terrain, custom minis, TTS) that the wounds path does not.
@rpc("any_peer", "call_remote", "reliable")
func sync_object_visibility(object_id: int, is_visible: bool) -> void:
	var object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager == null:
		return
	for child in object_manager.get_children():
		if child.has_meta("network_id") and int(child.get_meta("network_id")) == object_id:
			child.visible = is_visible
			child.set_meta("deleted", not is_visible)
			break


## Broadcast a generic object's visibility change to all peers.
func broadcast_object_visibility(object_id: int, is_visible: bool) -> void:
	if not is_multiplayer_active():
		return
	if not _validate_rpc_ready("broadcast_object_visibility"):
		return
	sync_object_visibility.rpc(object_id, is_visible)


# ===== Army Import Synchronization (Batched) =====

## Signals for batched army sync
signal remote_army_header_received(player_id: int, army_name: String, unit_count: int)
signal remote_army_unit_received(unit_data: Dictionary, objects_data: Array, player_id: int)
signal remote_army_complete_received(player_id: int, rule_descriptions: Dictionary)

## Delay between unit batch RPCs to pace large armies gracefully (the relay limit is
## 2000 msg/s, so this is comfort-pacing, not a hard requirement). The sender pauses
## presence broadcasts during sync.
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
func sync_army_complete(player_id: int, rule_descriptions: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	print("[Network] Army complete from peer %d (player_id=%d, %d rule descriptions)" % [sender, player_id, rule_descriptions.size()])
	remote_army_complete_received.emit(player_id, rule_descriptions)


## Broadcast army import in batches to all peers
func broadcast_army_batched(
	units_data: Array[Dictionary],
	objects_per_unit: Array[Array],
	player_id: int,
	army_name: String,
	rule_descriptions: Dictionary
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

	# 3. Complete — carries the army's rule descriptions so remote tooltips resolve.
	await get_tree().create_timer(ARMY_BATCH_DELAY_MS / 1000.0).timeout
	if _validate_rpc_ready("broadcast_army_complete"):
		sync_army_complete.rpc(player_id, rule_descriptions)


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
