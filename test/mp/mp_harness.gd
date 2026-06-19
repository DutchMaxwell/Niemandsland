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
var _spawned := false
var _mini_ids: Array[int] = []
var _cursor_accum := 0.0
var _tick_accum := 0.0
var _cursor_phase := 0.0
const SPAWN_COUNT := 10

# Fault injection (guest side). Applied partway through the run.
var _fault_done := false
var _fault_announced := false
const FAULT_AT_FRACTION := 0.4
const FRAMEDROP_WINDOW_S := 10.0
const STALL_FREEZE_MS := 6000


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_args = _parse_args(OS.get_cmdline_user_args())
	_role = _args.get("role", "host")
	_duration = float(_args.get("duration", "60"))
	_workload = _args.get("workload", "synthetic")
	_fault = _args.get("fault", "none")
	var relay_url: String = _args.get("relay-url", "ws://127.0.0.1:8765")
	var code: String = _args.get("code", "")

	_log("start role=%s relay=%s duration=%.0f workload=%s fault=%s" % [
		_role, relay_url, _duration, _workload, _fault])

	# Stand in for the startup menu: tell main.gd to open a relay session, headless.
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	ProjectSettings.set_setting("niemandsland/player_name", "Harness-%s" % _role)
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

	# Inject the configured fault on the guest (the realistic laggy / dropping peer);
	# the host stays healthy as the authority.
	if _connected and _role == "guest" and _fault != "none":
		_maybe_inject_fault()

	# Drive the workload once both ends are present.
	if _connected and (_role != "host" or _peer_count > 0) and _workload == "synthetic":
		_drive_synthetic(delta)

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
				var peer = _main.internet_lobby.relay_peer if _main else null
				if peer and peer.has_method("debug_force_close"):
					peer.debug_force_close()
				else:
					_fail("blip: relay_peer has no debug_force_close()")


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
			_nm.broadcast_dice_roll([randi() % 6 + 1], {"context": "harness"})


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
	_log("SUMMARY role=%s ok=%s connected=%s peers=%d minis=%d reconnects=%d remaps=%d failures=%s" % [
		_role, str(ok), str(_connected), _peer_count, minis, _reconnects, _remaps,
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
