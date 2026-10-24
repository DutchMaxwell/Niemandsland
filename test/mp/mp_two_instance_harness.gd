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
const AI_STRIKER_UNIT := "mp2_aistrike"
const SAVE_DEFENDER_UNIT := "mp2_defend"
const SAVE_WEAPON := "Harness Blade"
const SPELL_NAME := "Harness Round Buff"
const GROWTH_KEY := "growth_piercing_growth"
const P1A_UNIT := "mp2_p1a"
const P1B_UNIT := "mp2_p1b"
const P1C_UNIT := "mp2_p1c"
const P2A_UNIT := "mp2_p2a"

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
var _remote_save_wounds := -1   # result of the in-flight remote save batch (-1 = none yet)
var _last_refusal := ""         # 3.6: the last off-turn refusal text, for the alternation gate
var _was_ready := false         # the session was up once (a deliberate leave ends it later)
var _left: Dictionary = {}      # bugs 9+10: what the scene after End Battle inherits (host)
var _start_q_up := false        # the host's start question was on screen last snapshot
var _start_q_count := 0         # how many times it appeared (asked once per room)
var _host_left_at := 0.0        # bugs 9+10: unix time the guest's "host left" notice appeared
var _net_status_seen: Array = []  # bug 4: every network status text shown, in order (the hiccup notice)


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
		if not _failed and not _args.has("leave"):
			_fail("internet session disconnected"))
	_write_state()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var net_label = _main.get("network_status_label") if is_instance_valid(_main) else null
	if net_label is Label and (_net_status_seen.is_empty() or _net_status_seen[-1] != net_label.text):
		_net_status_seen.append(net_label.text)
	_was_ready = _was_ready or _session_ready()
	if not _failed and not _was_ready \
			and float(now - _started_ms) / 1000.0 > CONNECT_TIMEOUT_S:
		_fail("two occupied slots not ready within %.0fs" % CONNECT_TIMEOUT_S)
	if now - _last_state_ms >= int(STATE_WRITE_INTERVAL_S * 1000.0):
		_last_state_ms = now
		_write_state()
	if not _command_busy:
		_poll_command()


func _session_ready() -> bool:
	if not is_instance_valid(_main):
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
	if action not in ["quit", "snapshot", "leave_to_menu"] and not _session_ready():
		ok = false
		error = "session is not ready"
	elif action not in ["setup", "quit", "snapshot", "leave_to_menu", "close_window", "answer_start_question", "answer_rules_card"] and not _fixture_ready:
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
	elif action == "designate_ai":
		# #673: the production designation is the AI checkbox on the army import (a real import
		# cannot run in the fixture) — the designation set + the production broadcast are what
		# the checkpoint proves.
		_main.solo_ai_slots = {3: true}
		_main._solo_broadcast_ai_slots()
	elif action == "remote_save_attack":
		# #673: the host (slot 1) resolves an attack whose saves belong to the guest's unit —
		# the exact production save-batch entry the melee/shooting resolver funnels into.
		# Fire-and-forget: the batch stays in-flight (the driver watches the state file) until
		# the owner's faces come back.
		ok = _require_role("host", action)
		if ok:
			_run_remote_save_attack()
	elif action == "confirm_save":
		ok = _confirm_save_prompt()
	elif action == "vfx_burst":
		# Combat effects in co-op: the resolving peer emits one cue of every kind through the production
		# path (_vfx_emit); each peer must draw each exactly once (headless draws nothing, but counts).
		ok = _require_role("host", action)
		if ok:
			var sid: int = _main._vfx_emit({"k": "seal", "at": Vector3.ZERO, "r": 0.3, "kind": "buff"})
			_main._vfx_emit({"k": "seal_dim", "sid": sid})
			_main._vfx_emit({"k": "volley", "f": 1, "pairs": [[Vector3.ZERO, Vector3(0, 0, 0.3)]]})
			_main._vfx_emit({"k": "pip", "t": 1, "at": Vector3(0, 0.03, 0.3), "n": 1})
			_main._vfx_emit({"k": "seal_end", "sid": sid, "o": 0})
	elif action == "answer_start_question" or action == "answer_rules_card":
		var card := _find_card("Play with rules automation?" if action == "answer_start_question" \
				else "Turn on automatic rules?")
		ok = card != null
		if ok:
			card.resolve(bool(payload.get("yes", false)))
	elif action == "set_automatic":
		_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
		_main._hotseat_turn = null
	elif action == "activate":
		await _activate(str(payload.get("unit", "")), int(payload.get("slot", 0)))
	elif action == "leave_to_menu":
		ok = await _leave_to_menu()
	elif action == "snapshot":
		pass
	elif action == "close_window":
		_args["leave"] = "true"   # a deliberate leave: the disconnect that follows is not a failure
		# What closing the window does (headless has none to click): the close request reaches every node,
		# then the engine quits (auto-accept quit).
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		_write_ack(seq, true, "")
		get_tree().quit()
		return
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


func _find_card(card_title: String) -> PromptCard:
	if not is_instance_valid(_main):
		return null
	for c in _main.get_children():
		if c is PromptCard and (c as PromptCard).title == card_title:
			return c as PromptCard
	return null


func _setup_fixture() -> bool:
	if _fixture_ready:
		return true
	_main.solo_ai_slots = {}
	# The save scenario is the harness's first TRAY roll — seed the tray's own RNG here (the
	# arena reseeds it only post-deploy, which never happens in the harness), or run 2's dice
	# differ from run 1's and the determinism compare goes red.
	_main.seed_tray_rng(int(_args.get("seed", "240904")))
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
		[AI_STRIKER_UNIT, 3, "AI Striker", Vector3(0.30, 0.0, -0.25)],
		[SAVE_DEFENDER_UNIT, 2, "Guest Guard", Vector3(0.42, 0.0, -0.25)],
	]
	var net_id := 9100
	if not _args.has("rules-online"):
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
	# 3.6: three P1 units and one P2 unit so the rules-online gate can drive a full exchange, an
	# out-of-turn refusal, a TAIL (P1 keeps activating once P2 is spent) and one round end.
	if _args.has("rules-online"):
		for spec in [
			[P1A_UNIT, 1, "P1 Alpha", Vector3(-0.30, 0.0, 0.15)],
			[P1B_UNIT, 1, "P1 Bravo", Vector3(-0.20, 0.0, 0.15)],
			[P1C_UNIT, 1, "P1 Charlie", Vector3(-0.10, 0.0, 0.15)],
			[P2A_UNIT, 2, "P2 Alpha", Vector3(0.20, 0.0, 0.15)],
		]:
			var online := _spawn_unit(str(spec[0]), int(spec[1]), str(spec[2]), spec[3], net_id)
			net_id += 1
			if online == null:
				return false
			_main.opr_army_manager.game_units[online.unit_id] = online
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
	# No fabricated SoloController here (#675 item 1): a plain human-vs-human room has
	# solo_controller == null, and the production hover path now draws the LOS line from pure
	# geometry anyway. Lending one would fake the exact state this checkpoint must judge.
	_main._solo_target_mode = {"unit": attacker, "melee": false}
	_main._solo_update_los_line(point)
	_los_result = {
		"visible": _main._solo_los_line != null and _main._solo_los_line.visible,
		"label_visible": _main._solo_los_label != null and _main._solo_los_label.visible,
		"text": _main._solo_los_label.text if _main._solo_los_label != null else "",
	}
	return bool(_los_result.visible) and bool(_los_result.label_visible)


## Bugs 9+10: leave through the production End Battle path, then record what the next scene inherits:
## the relay peer, the SceneTree's multiplayer peer and a fresh SaveManager's load gate.
func _leave_to_menu() -> bool:
	var relay: RelayMultiplayerPeer = _main.internet_lobby.relay_peer
	UpdateChecker.set_enabled(false)   # the menu scene must not reach the network from a test
	_main.call("_on_end_battle_confirmed")
	var deadline := Time.get_ticks_msec() + 20000
	while is_instance_valid(_main) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var nm: Node = load("res://scripts/network_manager.gd").new()
	var sm := SaveManager.new()
	sm.network_manager = nm
	add_child(nm)
	add_child(sm)
	var gate: int = await sm.load_game("user://mp2_no_such_save.nml")
	_left = {"left": not is_instance_valid(_main), "load_gate": gate,
		"relay_connected": relay.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		"mp_peer_relay": get_tree().get_multiplayer().multiplayer_peer is RelayMultiplayerPeer}
	sm.queue_free()   # nm stays: the next scene's NetworkManager, listening to whatever peer survived
	_log("left to the menu: %s" % JSON.stringify(_left))
	return bool(_left.left)


func _unit(unit_id: String) -> GameUnit:
	if _main == null or _main.get("opr_army_manager") == null:
		return null
	return _main.opr_army_manager.get_game_unit_by_id(unit_id)


## #673: the guest must answer the remote save prompt like a human would — the production
## dialog (`_solo_prompt_saves`) is confirmed exactly as its Roll button would.
func _run_remote_save_attack() -> void:
	var wounds: int = await _main._solo_save_batch(_unit(AI_STRIKER_UNIT),
		_unit(SAVE_DEFENDER_UNIT), SAVE_WEAPON, 3, 4, 0,
		{"name": SAVE_WEAPON}, true, false)
	_remote_save_wounds = wounds


func _confirm_save_prompt() -> bool:
	var dlg := _visible_save_prompt()
	if dlg == null:
		_failure = "no visible save prompt to confirm"
		return false
	dlg.ok_button.pressed.emit()
	return true


func _visible_save_prompt() -> PromptCard:
	if _main == null:
		return null
	for child in _main.get_children():
		if child is PromptCard and (child as PromptCard).visible \
				and (child as PromptCard).title == "Incoming fire!":
			return child
	return null


func _require_role(required: String, action: String) -> bool:
	if _role == required:
		return true
	_failure = "%s is only valid on %s" % [action, required]
	return false


## 3.6: the production activation door, exactly as the radial Activate does — an off-turn side is
## refused and the refusal is logged (nothing on the wire), else the unit is marked, the activation
## is recorded (which hands the token over / ends the round) and the flag is broadcast.
func _activate(unit_id: String, slot: int) -> void:
	var unit := _unit(unit_id)
	if unit == null:
		_fail("activate: unknown unit %s" % unit_id)
		return
	var refusal := str(_main.call("hotseat_turn_refusal", slot)) if _main.has_method("hotseat_turn_refusal") else ""
	if refusal != "":
		_main.call("hotseat_log_refusal", refusal)
		_last_refusal = refusal
		return
	_last_refusal = ""
	unit.activate(opr_round())
	await _main.call("hotseat_record_activation", slot)
	_main.network_manager.broadcast_unit_activation(unit)


func opr_round() -> int:
	return int(_main.opr_army_manager.current_round) if _main != null else 1


func _snapshot() -> Dictionary:
	if not is_instance_valid(_main):
		return {"role": _role, "failed": _failed, "failure": _failure, "left_state": _left}
	if _host_left_at == 0.0 and _main.get_children().any(
			func(c: Node) -> bool: return c is PromptCard and (c as PromptCard).title == "Host left"):
		_host_left_at = Time.get_unix_time_from_system()
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
		"rules": int(_main.opr_army_manager.rules_automation) if _main != null else -1,
		"turn": int(_main.call("_hotseat_side_on_turn")) \
			if _main != null and _main.has_method("_hotseat_side_on_turn") else -1,
		"last_refusal": _last_refusal,
		"units": {},
		"los": _los_result.duplicate(true),
		"ai_slots": [],
		"remote_save_wounds": _remote_save_wounds,
		"save_prompt_visible": false,
		"battle_log_tail": [],
		"vfx_cues": (_main._vfx_seen as Dictionary).size() if _main != null else 0,
		"host_left_at": _host_left_at,
		"start_question_visible": false,
		"start_question_count": _start_q_count,
		"rules_card_visible": _find_card("Turn on automatic rules?") != null,
		# Bug 4 (silence scenario): our transport id, the relay's takeover capability, the host's peer -> slot
		# map (a phantom seat shows up here), the table objects by network id (a duplicate shows up here) and
		# the status texts shown so far.
		"peer_id": lobby.relay_peer.get_unique_id() if lobby != null and lobby.relay_peer != null else 0,
		"relay_takeover": lobby != null and lobby.relay_peer != null \
			and lobby.relay_peer.get("_relay_takeover") == true,
		"peers": {},
		"objects": [],
		"net_status_seen": _net_status_seen.duplicate(),
	}
	if _main != null and _main.get("object_manager") != null:
		for child in _main.object_manager.get_children():
			if child is Node3D and child.has_meta("network_id") and not child.is_queued_for_deletion():
				state.objects.append(int(child.get_meta("network_id")))
		state.objects.sort()
	var sq_up := _find_card("Play with rules automation?") != null
	if sq_up and not _start_q_up:
		_start_q_count += 1
	_start_q_up = sq_up
	state.start_question_visible = sq_up
	state.start_question_count = _start_q_count
	if nm != null:
		var slots: Array[int] = []
		for peer_id in nm.peer_to_slot:
			var slot := int(nm.peer_to_slot[peer_id])
			if not slots.has(slot):
				slots.append(slot)
		slots.sort()
		state.occupied_slots = slots
		for peer_id in nm.peer_to_slot:
			state.peers[str(peer_id)] = int(nm.peer_to_slot[peer_id])
	if _fixture_ready:
		var ai_slots: Array = []
		for slot in _main.solo_ai_slots:
			ai_slots.append(int(slot))
		ai_slots.sort()
		state.ai_slots = ai_slots
		state.save_prompt_visible = _visible_save_prompt() != null
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
