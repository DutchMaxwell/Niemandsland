extends Node
## Deterministic, command-driven peer used by run_two_instance.py.
## Test control travels through files; game state travels through the real relay.

const CONNECT_TIMEOUT_S := 40.0
const STATE_WRITE_INTERVAL_S := 0.10
const SPELL_UNIT := "mp2_spell"
const FATIGUE_UNIT := "mp2_fatigue"
const GROWTH_UNIT := "mp2_growth"
const HOST_LOS_UNIT := "mp2_los_host"
const GUEST_LOS_UNIT := "mp2_los_guest"
const CARGO_UNIT := "mp2_cargo"
const TRANSPORT_UNIT := "mp2_transport"
const SPELL_NAME := "Harness Round Buff"
const GROWTH_KEY := "growth_piercing_growth"

var _args: Dictionary = {}
var _main: Node = null
var _role := "host"
var _run_dir := ""
var _command_path := ""
var _state_path := ""
var _ack_path := ""
var _started_ms := 0
var _last_state_ms := 0
var _last_seq := 0
var _command_busy := false
var _fixture_ready := false
var _failed := false
var _failure := ""
var _room_code := ""
var _los_result: Dictionary = {"visible": false, "label_visible": false, "text": ""}


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_args = _parse_args(OS.get_cmdline_user_args())
	_role = str(_args.get("role", "host"))
	_run_dir = str(_args.get("run-dir", ""))
	if _run_dir.is_empty():
		_fail("--run-dir is required")
		get_tree().quit(2)
		return
	_command_path = _run_dir.path_join("%s.command.json" % _role)
	_state_path = _run_dir.path_join("%s.state.json" % _role)
	_ack_path = _run_dir.path_join("%s.ack.json" % _role)
	seed(int(_args.get("seed", "240904")))

	var relay_url := str(_args.get("relay-url", "ws://127.0.0.1:8765"))
	var code := str(_args.get("code", ""))
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	ProjectSettings.set_setting("niemandsland/player_name", "MP2-%s" % _role)
	ProjectSettings.set_setting("niemandsland/identity_token_override", "mp2-token-%s" % _role)
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", _role == "host")
	ProjectSettings.set_setting("niemandsland/internet_relay_url", relay_url)
	ProjectSettings.set_setting("niemandsland/internet_public", false)
	if _role == "guest":
		ProjectSettings.set_setting("niemandsland/internet_room_code", code)

	_log("start relay=%s seed=%s" % [relay_url, str(_args.get("seed", "240904"))])
	_main = load("res://scenes/main.tscn").instantiate()
	_main.name = "Main"
	get_tree().root.call_deferred("add_child", _main)
	call_deferred("_wire_signals")


func _wire_signals() -> void:
	get_tree().current_scene = _main
	var lobby = _main.get("internet_lobby") if _main != null else null
	if lobby == null:
		_fail("main has no internet_lobby")
		return
	lobby.room_code_ready.connect(func(code: String) -> void:
		_room_code = code
		_log("CODE %s" % code))
	lobby.internet_connected.connect(func(_peer_id: int) -> void:
		_room_code = str(lobby.room_code)
		_log("joined room %s" % _room_code))
	lobby.internet_connection_failed.connect(func(reason: String) -> void:
		_fail("connection failed: %s" % reason))
	lobby.relay_reconnect_failed.connect(func(reason: String) -> void:
		_fail("reconnect failed: %s" % reason))
	lobby.internet_disconnected.connect(func() -> void:
		if not _failed:
			_fail("internet session disconnected"))
	_write_state()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not _failed and not _session_ready() \
			and float(now - _started_ms) / 1000.0 > CONNECT_TIMEOUT_S:
		_fail("two occupied slots not ready within %.0fs" % CONNECT_TIMEOUT_S)
	if now - _last_state_ms >= int(STATE_WRITE_INTERVAL_S * 1000.0):
		_last_state_ms = now
		_write_state()
	if not _command_busy:
		_poll_command()


func _session_ready() -> bool:
	if _main == null:
		return false
	var nm = _main.get("network_manager")
	var lobby = _main.get("internet_lobby")
	if nm == null or lobby == null or not nm.is_multiplayer_active():
		return false
	if str(lobby.room_code).is_empty() or nm.get_my_player_slot() <= 0:
		return false
	var occupied: Dictionary = {}
	for peer_id in nm.peer_to_slot:
		occupied[int(nm.peer_to_slot[peer_id])] = true
	return occupied.has(1) and occupied.has(2)


func _poll_command() -> void:
	if not FileAccess.file_exists(_command_path):
		return
	var data := _read_json(_command_path)
	var seq := int(data.get("seq", 0))
	if seq <= _last_seq:
		return
	_last_seq = seq
	_command_busy = true
	_run_command(seq, str(data.get("action", "")), data.get("args", {}))


func _run_command(seq: int, action: String, payload: Dictionary) -> void:
	var ok := true
	var error := ""
	if action != "quit" and action != "snapshot" and not _session_ready():
		ok = false
		error = "session is not ready"
	elif action != "setup" and action != "quit" and action != "snapshot" and not _fixture_ready:
		ok = false
		error = "fixture is not ready"
	elif action == "setup":
		ok = await _setup_fixture()
		if not ok:
			error = "fixture setup failed"
	elif action == "place_spell":
		ok = _require_role("host", action)
		if ok:
			_main._solo_place_spell_tokens(SPELL_NAME, [_unit(SPELL_UNIT)], {
				"grants_rule": "Poison", "once": false, "duration": "round",
				"modifier": {"def_mod": 1, "advance_in": 4, "rush_in": 4},
			})
	elif action == "set_fatigue":
		ok = _require_role("host", action)
		if ok:
			_main.radial_menu_controller.card_toggle_fatigued(_unit(FATIGUE_UNIT))
	elif action == "enable_growth":
		var growth := _unit(GROWTH_UNIT)
		growth.unit_properties["ambush_reserve"] = false
		growth.unit_properties[GROWTH_KEY] = 0
	elif action == "advance_round":
		ok = _require_role("host", action)
		if ok:
			await _main._do_next_round()
	elif action == "hover_los":
		ok = await _hover_los()
		if not ok:
			error = "could not ray-pick the opposing unit"
	elif action == "embark":
		ok = _require_role("host", action)
		if ok:
			_main.radial_menu_controller._embark_unit({
				"game_unit": _unit(CARGO_UNIT), "embark_target": _unit(TRANSPORT_UNIT)})
	elif action == "disembark":
		ok = _require_role("host", action)
		if ok:
			_main.radial_menu_controller._disembark_unit(_unit(CARGO_UNIT))
	elif action == "snapshot":
		pass
	elif action == "quit":
		_write_ack(seq, true, "")
		_write_state()
		_log("quit")
		get_tree().quit(0 if not _failed else 1)
		return
	else:
		ok = false
		error = "unknown action: %s" % action
	if not ok and error.is_empty():
		error = "%s command rejected" % action
	_write_ack(seq, ok, error)
	_write_state()
	_command_busy = false


func _setup_fixture() -> bool:
	if _fixture_ready:
		return true
	_main.solo_ai_slots = {}
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	var specs := [
		[SPELL_UNIT, 1, "Spell Guard", Vector3(-0.35, 0.0, -0.25)],
		[FATIGUE_UNIT, 1, "Fatigue Guard", Vector3(-0.15, 0.0, -0.25)],
		[GROWTH_UNIT, 1, "Growth Guard", Vector3(0.05, 0.0, -0.25)],
		[HOST_LOS_UNIT, 1, "Host Scout", Vector3(-0.12, 0.0, 0.20)],
		[GUEST_LOS_UNIT, 2, "Guest Scout", Vector3(0.18, 0.0, 0.20)],
		[CARGO_UNIT, 1, "Cargo", Vector3(-0.25, 0.0, 0.0)],
		[TRANSPORT_UNIT, 1, "Carrier", Vector3(-0.18, 0.0, 0.0)],
	]
	var net_id := 9100
	for spec in specs:
		var unit := _spawn_unit(str(spec[0]), int(spec[1]), str(spec[2]), spec[3], net_id)
		net_id += 1
		if unit == null:
			return false
		_main.opr_army_manager.game_units[unit.unit_id] = unit
	var growth := _unit(GROWTH_UNIT)
	growth.unit_properties["game_system"] = "gf"
	growth.unit_properties["faction_folder"] = "alien_hives"
	growth.unit_properties["special_rules"] = ["Piercing Growth"]
	growth.unit_properties["ambush_reserve"] = true
	_unit(TRANSPORT_UNIT).unit_properties["special_rules"] = ["Transport(2)"]
	for unit in _main.opr_army_manager.get_all_game_units():
		_main.radial_menu_controller.initialize_status_markers_for_unit(unit)
	await get_tree().physics_frame
	await get_tree().process_frame
	# Connection/bootstrap lines race independently of the scripted scenario. Start the captured
	# tail at the deterministic fixture boundary; all later entries come from scenario actions.
	if _main.battle_log != null:
		_main.battle_log.clear()
	_fixture_ready = true
	_log("fixture ready (%d units)" % _main.opr_army_manager.game_units.size())
	return true


func _spawn_unit(unit_id: String, player_id: int, display_name: String, pos: Vector3,
		network_id: int) -> GameUnit:
	var node: Node3D = _main.object_manager.spawn_miniature(pos, false, network_id)
	if node == null:
		return null
	var unit := GameUnit.new()
	unit.unit_id = unit_id
	unit.unit_properties = {
		"player_id": player_id, "name": display_name, "quality": 4, "defense": 4,
		"network_id": unit_id, "size": 1, "special_rules": [],
	}
	var model := ModelInstance.new()
	model.unit = unit
	model.node = node
	model.model_index = 0
	model.is_alive = true
	model.wounds_current = 1
	model.wounds_max = 1
	unit.models.append(model)
	node.set_meta("game_unit", unit)
	node.set_meta("model_instance", model)
	return unit


func _hover_los() -> bool:
	var attacker_id := HOST_LOS_UNIT if _role == "host" else GUEST_LOS_UNIT
	var target_id := GUEST_LOS_UNIT if _role == "host" else HOST_LOS_UNIT
	var attacker := _unit(attacker_id)
	var target := _unit(target_id)
	var camera: Camera3D = _main.get_viewport().get_camera_3d()
	if attacker == null or target == null or camera == null:
		return false
	await get_tree().physics_frame
	var target_node: Node3D = target.models[0].node
	var point := camera.unproject_position(target_node.global_position + Vector3(0.0, 0.016, 0.0))
	if _main._solo_pick_unit_at(point) != target:
		return false
	# The LOS helper uses SoloController's pure geometry helpers through an instance. Plain MP
	# intentionally has no persistent solo controller, so lend it one for this audited UI seam only.
	var temporary_controller := false
	if _main.solo_controller == null:
		_main.solo_controller = SoloController.new()
		_main.add_child(_main.solo_controller)
		temporary_controller = true
	_main._solo_target_mode = {"unit": attacker, "melee": false}
	_main._solo_update_los_line(point)
	_los_result = {
		"visible": _main._solo_los_line != null and _main._solo_los_line.visible,
		"label_visible": _main._solo_los_label != null and _main._solo_los_label.visible,
		"text": _main._solo_los_label.text if _main._solo_los_label != null else "",
	}
	if temporary_controller:
		var controller: Node = _main.solo_controller
		_main.solo_controller = null
		controller.queue_free()
	return bool(_los_result.visible) and bool(_los_result.label_visible)


func _unit(unit_id: String) -> GameUnit:
	if _main == null or _main.get("opr_army_manager") == null:
		return null
	return _main.opr_army_manager.get_game_unit_by_id(unit_id)


func _require_role(required: String, action: String) -> bool:
	if _role == required:
		return true
	_failure = "%s is only valid on %s" % [action, required]
	return false


func _snapshot() -> Dictionary:
	var lobby = _main.get("internet_lobby") if _main != null else null
	var nm = _main.get("network_manager") if _main != null else null
	var state := {
		"role": _role,
		"room": str(lobby.room_code) if lobby != null else _room_code,
		"session_ready": _session_ready(),
		"fixture_ready": _fixture_ready,
		"failed": _failed,
		"failure": _failure,
		"slot": int(nm.get_my_player_slot()) if nm != null else 0,
		"occupied_slots": [],
		"round": int(_main.opr_army_manager.current_round) if _main != null else 0,
		"units": {},
		"los": _los_result.duplicate(true),
		"battle_log_tail": [],
	}
	if nm != null:
		var slots: Array[int] = []
		for peer_id in nm.peer_to_slot:
			var slot := int(nm.peer_to_slot[peer_id])
			if not slots.has(slot):
				slots.append(slot)
		slots.sort()
		state.occupied_slots = slots
	if _fixture_ready:
		var ids: Array = _main.opr_army_manager.game_units.keys()
		ids.sort()
		for unit_id in ids:
			var unit: GameUnit = _main.opr_army_manager.game_units[unit_id]
			var markers: Array = []
			for model in unit.models:
				var names: Array[String] = []
				for marker_name in (model as ModelInstance).markers:
					# Standard status tokens are derived from the unit flags on the acting peer.
					# The receive path also retains their wire marker name in ModelInstance.markers.
					if marker_name not in ["FatiguedMarker", "ShakenMarker", "ActivatedMarker"]:
						names.append(marker_name)
				names.sort()
				markers.append(names)
			var transport = _main.opr_army_manager.transport_of(unit)
			var records: Array = _main._solo_spell_mods.get(unit.get_instance_id(), [])
			state.units[str(unit_id)] = {
				"player_id": int(unit.unit_properties.get("player_id", 0)),
				"activated": unit.is_activated,
				"activation_round": unit.activation_round,
				"fatigued": unit.is_fatigued,
				"status_markers": {
					"activated": unit.is_activated,
					"fatigued": unit.is_fatigued,
					"shaken": unit.is_shaken,
				},
				"growth": int(unit.unit_properties.get(GROWTH_KEY, 0)),
				"in_reserve": SoloController.unit_in_reserve(unit),
				"markers": markers,
				"spell_records": records.size(),
				"spell_move_mod": unit.unit_properties.get("spell_move_mod", null),
				"transport": transport.unit_id if transport != null else "",
			}
	if _main != null and _main.get("battle_log") != null:
		var entries: Array = _main.battle_log.entries()
		for i in range(maxi(0, entries.size() - 8), entries.size()):
			state.battle_log_tail.append(str((entries[i] as Dictionary).get("text", "")))
	return state


func _write_state() -> void:
	if _state_path.is_empty():
		return
	_write_json_atomic(_state_path, _snapshot())


func _write_ack(seq: int, ok: bool, error: String) -> void:
	_write_json_atomic(_ack_path, {"seq": seq, "ok": ok, "error": error})


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _write_json_atomic(path: String, value: Dictionary) -> void:
	var tmp := "%s.tmp.%d" % [path, OS.get_process_id()]
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_failure = message
	push_error("MP2: %s" % message)
	_write_state()


func _log(message: String) -> void:
	print("MP2: %s %s" % [_role, message])


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < argv.size():
		var arg := argv[i]
		if arg.begins_with("--"):
			var key := arg.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				out[key] = argv[i + 1]
				i += 2
			else:
				out[key] = "true"
				i += 1
		else:
			i += 1
	return out
