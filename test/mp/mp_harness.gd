extends Node
## Headless multiplayer soak / fault harness (test-only; not shipped).
##
## Launched as the main scene, one process per client:
##   godot --headless --path . res://test/mp/mp_harness.tscn -- \
##       --role host  --relay-url ws://127.0.0.1:8765 --duration 60
##   godot --headless --path . res://test/mp/mp_harness.tscn -- \
##       --role guest --relay-url ws://127.0.0.1:8765 --code ABC123 --duration 60
##
## It sets the ProjectSettings the startup menu normally would, boots
## scenes/main.tscn straight onto a live table (via niemandsland/harness_mode),
## then prints structured `MP_HARNESS:` lines that the orchestrator (run_soak.py)
## parses for pass/fail. The orchestrator scrapes `MP_HARNESS: CODE <code>` from the
## host's stdout and passes it to the guest.

const CONNECT_TIMEOUT_S := 30.0

var _args: Dictionary = {}
var _main: Node = null
var _role := "host"
var _duration := 60.0
var _workload := "synthetic"
var _fault := "none"

var _elapsed := 0.0
var _start_ms := 0
var _connected := false
var _peer_count := 0
var _failures: Array[String] = []
var _reconnects := 0
var _remaps := 0
var _done := false

# Synthetic workload state.
var _nm = null
var _om = null
var _oam = null
var _spawned := false
var _opr_imported := false
var _army_link := ""
var _mini_ids: Array[int] = []
# Stress workload (both sides: army + terrain + bidirectional movement).
var _own_ids: Array[int] = []
var _terrain_done := false
var _stress_imported := false
var _move_accum := 0.0
var _round_accum := 0.0
var _cmd_selftest_sent := false
var _cursor_accum := 0.0
var _tick_accum := 0.0
var _dice_accum := 0.0
var _cursor_phase := 0.0
const SPAWN_COUNT := 10

# Fault injection (guest side). Applied partway through the run.
var _fault_done := false
var _fault_announced := false
var _last_churn := 0.0
var _last_blip := 0.0
var _last_leak := 0.0
var _nodes_base := 0
const FAULT_AT_FRACTION := 0.4
const FRAMEDROP_WINDOW_S := 10.0
const STALL_FREEZE_MS := 6000
const CHURN_INTERVAL_S := 30.0    # reconnect-churn: drop + rejoin this often
const CHAOS_BLIP_INTERVAL_S := 45.0
const LEAK_SAMPLE_S := 15.0
const LEAK_SETTLE_S := 45.0       # capture the node-count baseline only after armies+terrain settle


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_args = _parse_args(OS.get_cmdline_user_args())
	_role = _args.get("role", "host")
	_duration = float(_args.get("duration", "60"))
	_workload = _args.get("workload", "synthetic")
	_fault = _args.get("fault", "none")
	_army_link = _args.get("army", "")
	var relay_url: String = _args.get("relay-url", "ws://127.0.0.1:8765")
	var code: String = _args.get("code", "")

	_log("start role=%s relay=%s duration=%.0f workload=%s fault=%s" % [
		_role, relay_url, _duration, _workload, _fault])

	# Stand in for the startup menu: tell main.gd to open a relay session, headless.
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	ProjectSettings.set_setting("niemandsland/player_name", "Harness-%s" % _role)
	# Distinct identity token per process: both clients share one machine's user:// (same
	# persisted token), which would mask the real reconnect slot-remap path. Real players on
	# separate installs have distinct tokens, so give each role its own here.
	ProjectSettings.set_setting("niemandsland/identity_token_override", "harness-token-%s" % _role)
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", _role == "host")
	ProjectSettings.set_setting("niemandsland/internet_relay_url", relay_url)
	ProjectSettings.set_setting("niemandsland/internet_public", false)
	if _role != "host":
		ProjectSettings.set_setting("niemandsland/internet_room_code", code)

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	get_tree().current_scene = _main
	# internet_lobby is created synchronously in main._ready; wire it before the
	# deferred host/join call fires next frame.
	call_deferred("_wire_signals")


func _wire_signals() -> void:
	var lobby = _main.get("internet_lobby") if _main else null
	if lobby == null:
		_fail("main has no internet_lobby")
		_finish()
		return
	# Host side: room_code_ready means the relay link is up and we are hosting.
	lobby.room_code_ready.connect(func(c: String):
		_connected = true
		_log("CODE %s" % c))
	# Guest side: internet_connected means we joined the host's room.
	lobby.internet_connected.connect(func(pid: int):
		_connected = true
		_log("connected peer_id=%d" % pid))
	lobby.internet_connection_failed.connect(func(r: String): _fail("connect_failed: %s" % r))
	lobby.peer_joined.connect(func(pid: int):
		_peer_count += 1
		_connected = true
		_log("peer_joined %d (peers=%d)" % [pid, _peer_count]))
	lobby.peer_left.connect(func(pid: int): _log("peer_left %d" % pid))
	lobby.relay_reconnecting.connect(func():
		_reconnects += 1
		_log("RECONNECTING (#%d)" % _reconnects))
	lobby.relay_reconnect_failed.connect(func(r: String): _fail("reconnect_failed: %s" % r))
	lobby.internet_disconnected.connect(func(): _log("disconnected"))
	# Slot remaps (guest reconnect identity) — count them via the network manager.
	var nm = _main.get("network_manager") if _main else null
	if nm and nm.has_signal("peer_remapped"):
		nm.peer_remapped.connect(func(_a = 0, _b = 0, _c = 0): _remaps += 1)
	_log("wired")


func _process(delta: float) -> void:
	if _done:
		return
	# Wall-clock elapsed: the engine clamps `delta` under heavy lag (framedrop fault), so
	# accumulating delta would lag real time and the run would never reach its deadline.
	_elapsed = float(Time.get_ticks_msec() - _start_ms) / 1000.0

	# Connection watchdog.
	if not _connected and _elapsed > CONNECT_TIMEOUT_S:
		_fail("no connection within %.0fs" % CONNECT_TIMEOUT_S)
		_finish()
		return

	# Leak watch: sample the live SceneTree node count periodically. _nodes_base is captured
	# once the session is up (post-connect); growth from there flags a slow leak.
	if _connected and _elapsed - _last_leak >= LEAK_SAMPLE_S:
		_last_leak = _elapsed
		var nc := get_tree().get_node_count()
		if _nodes_base == 0 and _elapsed >= LEAK_SETTLE_S:
			_nodes_base = nc  # baseline only once armies + terrain have finished spawning
		_log("NODES %d minis %d" % [nc, get_tree().get_nodes_in_group("miniature").size()])

	# Phase-1 command-channel proof: the guest pings the host once over the channel-1 protocol;
	# the host's built-in handler replies, the guest logs "[CMD] pong ... verified".
	if _role == "guest" and _connected and not _cmd_selftest_sent:
		if _nm == null:
			_nm = _main.get("network_manager")
		if _nm and _nm.has_method("send_command"):
			_cmd_selftest_sent = true
			_nm.send_command("cmd_ping", {}, 1)
			_log("CMD selftest ping sent to host")

	# Inject the configured fault on the guest (the realistic laggy / dropping peer);
	# the host stays healthy as the authority.
	if _connected and _role == "guest" and _fault != "none":
		_maybe_inject_fault()

	# Drive the workload once both ends are present.
	if _connected and (_role != "host" or _peer_count > 0):
		if _workload == "synthetic":
			_drive_synthetic(delta)
		elif _workload == "opr":
			_drive_opr(delta)
		elif _workload == "stress":
			_drive_stress(delta)

	if _elapsed >= _duration:
		_finish()


## Reproduce a sporadic-disconnect cause on demand, partway through the run.
## stall   = one long main-loop freeze (the stall detector should fire, no drop).
## framedrop = sustained low FPS (heartbeat cadence/send queue degrade; should survive).
## blip    = force a socket close (the reconnect path should recover cleanly).
func _maybe_inject_fault() -> void:
	var start := _duration * FAULT_AT_FRACTION
	if _elapsed < start:
		return
	match _fault:
		"framedrop":
			var fps := int(_args.get("target-fps", "5"))
			if fps <= 0:
				fps = 5
			if _elapsed < start + FRAMEDROP_WINDOW_S:
				if not _fault_announced:
					_fault_announced = true
					_log("FAULT framedrop ~%d fps for %.0fs" % [fps, FRAMEDROP_WINDOW_S])
				OS.delay_msec(int(1000.0 / float(fps)))  # block the frame -> low FPS
		"stall":
			if not _fault_done:
				_fault_done = true
				_log("FAULT stall %dms freeze" % STALL_FREEZE_MS)
				OS.delay_msec(STALL_FREEZE_MS)
		"blip":
			if not _fault_done:
				_fault_done = true
				_log("FAULT blip force-close")
				_force_close()
		"churn":
			# Repeatedly drop + reconnect while both armies are on the table.
			if _elapsed - _last_churn >= CHURN_INTERVAL_S:
				_last_churn = _elapsed
				_log("FAULT churn force-close (#%d)" % (_reconnects + 1))
				_force_close()
		"chaos":
			# Interleave a sustained framedrop window with periodic blips, under full load.
			if fmod(_elapsed - start, 30.0) < 8.0:
				OS.delay_msec(int(1000.0 / 5.0))  # ~5 fps for 8s of every 30s
			if _elapsed - _last_blip >= CHAOS_BLIP_INTERVAL_S:
				_last_blip = _elapsed
				_log("FAULT chaos blip force-close")
				_force_close()


## Force-close the relay socket (drives the reconnect path); used by blip / churn / chaos.
func _force_close() -> void:
	var peer = _main.internet_lobby.relay_peer if _main else null
	if peer and peer.has_method("debug_force_close"):
		peer.debug_force_close()


## Synthetic workload: realistic relay traffic without needing army assets.
## - Host seeds a small "army" once both ends are present (spawn-sync, like an import).
## - Both ends stream cursor presence at ~15 Hz (the high-rate channel that spikes tx).
## - Host periodically moves a model + rolls dice (reliable RPC traffic).
func _drive_synthetic(delta: float) -> void:
	if _nm == null:
		_nm = _main.get("network_manager")
		_om = _main.get("object_manager")
	if _nm == null:
		return

	if _role == "host" and not _spawned and _om != null:
		_spawned = true
		for i in range(SPAWN_COUNT):
			var pos := Vector3(-0.4 + 0.08 * i, 0.0, 0.0)
			var m = _om.spawn_miniature(pos, true)
			if m and m.has_meta("network_id"):
				_mini_ids.append(int(m.get_meta("network_id")))
		_log("spawned %d minis" % _mini_ids.size())

	_cursor_accum += delta
	if _cursor_accum >= 1.0 / 15.0:
		_cursor_accum = 0.0
		_cursor_phase += 0.1
		_nm.broadcast_cursor_position(Vector3(sin(_cursor_phase) * 0.5, 0.0, cos(_cursor_phase) * 0.5))

	if _role == "host":
		_tick_accum += delta
		if _tick_accum >= 0.5:
			_tick_accum = 0.0
			if not _mini_ids.is_empty():
				var oid: int = _mini_ids[randi() % _mini_ids.size()]
				_nm.broadcast_move(oid, Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)))
		# Dice rolls append to the in-game roll LOG, so roll at a REALISTIC cadence (~every 4s);
		# the old 2/s rate ballooned the log and read as a node leak (it isn't — a log grows).
		_dice_accum += delta
		if _dice_accum >= 4.0:
			_dice_accum = 0.0
			_nm.broadcast_dice_roll([randi() % 6 + 1], {"context": "harness"})


## OPR workload: the host imports a REAL Army Forge army (downloads its GLBs from R2 and syncs
## them to the guest — the realistic army-sync burst + GLB-download stall path). Both ends stream
## cursor presence. Requires --army <share-link>.
func _drive_opr(delta: float) -> void:
	if _nm == null:
		_nm = _main.get("network_manager")
		_oam = _main.get("opr_army_manager")
	if _nm == null:
		return
	if _role == "host" and not _opr_imported and _oam != null and _oam.get("api_client") != null:
		_opr_imported = true
		_import_army()  # async coroutine; the flag guards re-entry
	_cursor_accum += delta
	if _cursor_accum >= 1.0 / 15.0:
		_cursor_accum = 0.0
		_cursor_phase += 0.1
		_nm.broadcast_cursor_position(Vector3(sin(_cursor_phase) * 0.5, 0.0, cos(_cursor_phase) * 0.5))


func _import_army() -> void:
	if _army_link.is_empty():
		_fail("opr workload needs --army <share-link>")
		return
	_log("importing army: %s" % _army_link)
	var army = await _oam.api_client.import_from_share_link(_army_link)
	if army == null:
		_fail("army import failed (api / network?)")
		return
	# Run the REAL in-game import handler: spawn + on-demand GLB download from R2 + buff
	# tokens + MP broadcast to the guest — identical to a player importing in a live session.
	await _main._on_opr_army_imported(army, 1)
	_log("opr import done; host minis=%d" % get_tree().get_nodes_in_group("miniature").size())


## Stress workload: BOTH sides import an army (each to its own slot), the host auto-generates a
## full terrain layout (synced), and each side continuously moves ITS OWN models — heavy
## bidirectional traffic (two army-syncs + terrain + two-way movement) on a populated field.
func _drive_stress(delta: float) -> void:
	if _nm == null:
		_nm = _main.get("network_manager")
		_oam = _main.get("opr_army_manager")
		_om = _main.get("object_manager")
	if _nm == null:
		return
	if _role == "host" and not _terrain_done:
		_terrain_done = true
		_generate_terrain()
	# Host imports first; the guest waits until the host's army has arrived (staggered, like real
	# players) so the two mid-session imports don't race head-on at the same instant.
	if not _stress_imported and _oam != null and _oam.get("api_client") != null:
		var simul: bool = _args.get("simul", "false") == "true"
		var do_import := false
		if simul:
			# True simultaneity: BOTH sides fire at the same settled time (connection RPC-ready),
			# so this tests the concurrent-build race, not an unrealistic first-frame import.
			do_import = _elapsed >= 10.0
		elif _role == "host":
			do_import = true
		else:
			# Staggered (realistic): the guest imports once the host's army has arrived.
			do_import = get_tree().get_nodes_in_group("miniature").size() > 0
		if do_import:
			_stress_imported = true
			_import_own_army()  # async coroutine; the flag guards re-entry
	_cursor_accum += delta
	if _cursor_accum >= 1.0 / 15.0:
		_cursor_accum = 0.0
		_cursor_phase += 0.1
		_nm.broadcast_cursor_position(Vector3(sin(_cursor_phase) * 0.5, 0.0, cos(_cursor_phase) * 0.5))
	# Host advances the round periodically (exercises the round-sync RPC over the long run).
	if _role == "host":
		_round_accum += delta
		if _round_accum >= 5.0:
			_round_accum = 0.0
			if _nm.has_method("broadcast_round_advance"):
				_nm.broadcast_round_advance()
	# Move a few of our OWN models each tick (local move + broadcast = two-way movement traffic).
	_move_accum += delta
	if _move_accum >= 0.4 and not _own_ids.is_empty():
		_move_accum = 0.0
		for _i in range(mini(3, _own_ids.size())):
			var oid: int = _own_ids[randi() % _own_ids.size()]
			var pos := Vector3(randf_range(-0.55, 0.55), 0.0, randf_range(-0.35, 0.35))
			if _om and _om.has_method("find_by_network_id"):
				var node = _om.find_by_network_id(oid)
				if node:
					node.global_position = pos
			_nm.broadcast_move(oid, pos)
		# Combat-like state churn on one own model/unit (no count change -> convergence holds).
		var cnode = _om.find_by_network_id(_own_ids[randi() % _own_ids.size()]) if (_om and _om.has_method("find_by_network_id")) else null
		if cnode and cnode.has_meta("model_instance"):
			var cmi = cnode.get_meta("model_instance")
			if cmi != null:
				if cmi.get("wounds_max") != null and int(cmi.wounds_max) > 1:
					cmi.wounds_current = (int(cmi.wounds_current) - 1) if int(cmi.wounds_current) > 1 else int(cmi.wounds_max)
					if _nm.has_method("broadcast_model_wounds"):
						_nm.broadcast_model_wounds(cmi)
				var cgu = cmi.get("unit")
				if cgu != null and _nm.has_method("broadcast_unit_activation"):
					_nm.broadcast_unit_activation(cgu)


func _generate_terrain() -> void:
	var ed = _main.get("map_layout_editor")
	if ed and ed.has_method("_on_autogen_pressed") and ed.has_method("_emit_layout_update"):
		ed._on_autogen_pressed()
		ed._emit_layout_update()
		_log("terrain auto-generated + synced")
	else:
		_log("terrain: map_layout_editor unavailable (skipped)")


func _import_own_army() -> void:
	if _army_link.is_empty():
		_fail("stress workload needs --army <share-link>")
		return
	var slot: int = _nm.get_my_player_slot()
	if slot <= 0:
		slot = 1 if _role == "host" else 2
	_log("importing army for slot %d" % slot)
	var army = await _oam.api_client.import_from_share_link(_army_link)
	if army == null:
		_fail("army import failed (api / network?)")
		return
	army.player_id = slot  # tag ownership (the import dialog sets this; we bypass it)
	# Snapshot existing models so we can identify OURS (the ones this import adds).
	var before := {}
	for m in get_tree().get_nodes_in_group("miniature"):
		if m.has_meta("network_id"):
			before[int(m.get_meta("network_id"))] = true
	await _main._on_opr_army_imported(army, slot)
	for m in get_tree().get_nodes_in_group("miniature"):
		if m.has_meta("network_id"):
			var nid := int(m.get_meta("network_id"))
			if not before.has(nid):
				_own_ids.append(nid)
	var lo: int = int(_own_ids.min()) if not _own_ids.is_empty() else -1
	var hi: int = int(_own_ids.max()) if not _own_ids.is_empty() else -1
	_log("imported slot %d: own=%d total minis=%d own_ids=[%d..%d]" % [
		slot, _own_ids.size(), get_tree().get_nodes_in_group("miniature").size(), lo, hi])


# === Result handling ===

func _fail(msg: String) -> void:
	_failures.append(msg)
	_log("FAIL %s" % msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	var ok := _failures.is_empty() and _connected
	if not _connected:
		_failures.append("never connected")
	var minis := get_tree().get_nodes_in_group("miniature").size()
	var nodes := get_tree().get_node_count()
	_log("SUMMARY role=%s ok=%s connected=%s peers=%d minis=%d reconnects=%d remaps=%d nodes=%d nodes_base=%d failures=%s" % [
		_role, str(ok), str(_connected), _peer_count, minis, _reconnects, _remaps, nodes, _nodes_base,
		"|".join(_failures) if not _failures.is_empty() else "none"])
	get_tree().quit(0 if ok else 1)


# === Helpers ===

func _log(msg: String) -> void:
	print("MP_HARNESS: %s" % msg)


## Parse `--key value` / `--flag` pairs from the user args after `--`.
func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				out[key] = argv[i + 1]
				i += 2
			else:
				out[key] = "true"
				i += 1
		else:
			i += 1
	return out
