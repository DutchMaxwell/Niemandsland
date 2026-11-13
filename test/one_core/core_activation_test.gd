extends GdUnitTestSuite
## One-core P3 step 19: the table skeleton `CoreActivation` and its three predicates (lifecycle, core, move-path).
## Step 20: the driver loop `CoreActivation.drive` on the batch tray.
## Real: the main scene, its network manager class (transport swapped out, the e2e_mp_auto_verbs_test pattern),
## the NmlCore extension. Constructed: bare units from E2EBoot.make_unit with an OPRUnit profile of one weapon.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {}
	CoreActivation._env = 1   # the flag ON for every case; the default case resets it itself


func after_test() -> void:
	CoreActivation.reset_all(_main)   # the session store is static: no case leaks an open activation into the next
	CoreActivation._env = -1
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


## A REAL NetworkManager with only the transport swapped out (pattern: e2e_mp_auto_verbs_test).
func _fake_session(my_slot: int) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn %d\n" % my_slot
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = true
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net


func _unit(pid: int, uname: String, unit_rules: Array = [], weapon_rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, uname, [Vector3(0.3 * pid, 0.0, 0.0)])
	u.unit_properties["special_rules"] = unit_rules
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.special_rules.assign(weapon_rules)
	src.weapons.append(w)
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_enabled_is_false_by_default() -> void:
	CoreActivation._env = -1
	assert_bool(CoreActivation.enabled()).is_false()


func test_a_bare_unit_with_one_plain_weapon_is_plain() -> void:
	assert_bool(CoreActivation.is_plain(_unit(1, "Rifles"))).is_true()


func test_a_special_rule_makes_a_unit_not_plain() -> void:
	assert_bool(CoreActivation.is_plain(_unit(1, "Rifles", ["Furious"]))).is_false()


func test_a_weapon_rule_makes_a_unit_not_plain() -> void:
	assert_bool(CoreActivation.is_plain(_unit(1, "Rifles", [], ["Blast(3)"]))).is_false()


func test_an_attached_hero_makes_a_unit_not_plain() -> void:
	var host := _unit(1, "Rifles")
	var hero := _unit(1, "Captain")
	hero.unit_properties["attached_to"] = host
	assert_bool(CoreActivation.is_plain(hero)).override_failure_message("the joined hero").is_false()
	host.unit_properties["attached_heroes"] = [hero]
	assert_bool(CoreActivation.is_plain(host)).override_failure_message("the host with a hero").is_false()


func test_applies_is_false_with_the_flag_off() -> void:
	_main.solo_ai_slots = {2: true}
	CoreActivation._env = 0
	assert_bool(CoreActivation.applies(_main)).is_false()


func test_applies_is_false_without_an_ai_seat_and_without_a_room() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	assert_bool(CoreActivation.applies(_main)).is_false()


func test_applies_is_true_with_an_ai_seat() -> void:
	_main.solo_ai_slots = {2: true}
	assert_bool(CoreActivation.applies(_main)).is_true()


func test_applies_is_true_in_an_agreed_automatic_room() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_fake_session(1)
	var applies := CoreActivation.applies(_main)
	_end_session()
	assert_bool(applies).is_true()


func test_applies_is_false_in_a_manual_room() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_fake_session(1)
	var applies := CoreActivation.applies(_main)
	_end_session()
	assert_bool(applies).is_false()


func test_a_human_unit_with_a_non_movement_rule_is_lifecycle_but_not_core_nor_move_path() -> void:
	_main.solo_ai_slots = {2: true}
	var u := _unit(1, "Rifles", ["Furious"])
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).override_failure_message("lifecycle").is_true()
	assert_bool(CoreActivation.is_core_unit(_main, u)).override_failure_message("core").is_false()
	assert_bool(CoreActivation.on_move_path(_main, u)).override_failure_message("move path").is_false()


func test_a_plain_human_unit_is_lifecycle_core_and_move_path() -> void:
	_main.solo_ai_slots = {2: true}
	var u := _unit(1, "Rifles")
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).is_true()
	assert_bool(CoreActivation.is_core_unit(_main, u)).is_true()
	assert_bool(CoreActivation.on_move_path(_main, u)).is_true()


func test_an_ai_unit_is_none_of_the_three() -> void:
	_main.solo_ai_slots = {2: true}
	var u := _unit(2, "Drones")
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).is_false()
	assert_bool(CoreActivation.is_core_unit(_main, u)).is_false()
	assert_bool(CoreActivation.on_move_path(_main, u)).is_false()


func test_a_unit_another_slot_owns_is_none_of_the_three() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_fake_session(1)
	var u := _unit(2, "Raiders")
	var got := [CoreActivation.is_lifecycle_unit(_main, u), CoreActivation.is_core_unit(_main, u),
		CoreActivation.on_move_path(_main, u)]
	_end_session()
	assert_array(got).is_equal([false, false, false])


func test_no_unit_is_lifecycle_before_the_game_is_playing() -> void:
	_main.solo_ai_slots = {2: true}
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	assert_bool(CoreActivation.is_lifecycle_unit(_main, _unit(1, "Rifles"))).is_false()


func test_capture_returns_a_live_core_handle_and_zero_without_a_controller() -> void:
	_main.solo_ai_slots = {2: true}
	_unit(1, "Rifles")
	_unit(2, "Drones")
	_main.solo_controller = null
	assert_int(CoreActivation.capture(_main)).override_failure_message("no controller").is_equal(0)
	_main._ensure_solo_controller()
	assert_int(CoreActivation.capture(_main)).override_failure_message("with a controller").is_not_equal(0)


## Step 20 fixture: 10 AI riflemen (Rifle 24", A1) vs 5 human models 12" away; batch tray, so no save prompt.
func _volley_units() -> Array:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true
	var side := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
		"faction_folder": "robot_legions", "rules": []}
	var att := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
	var foe := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 5, "x_in": 12.0}), {})
	return [att, foe]


func test_drive_runs_a_plain_hold_and_shoot_activation_to_done() -> void:
	var units := _volley_units()
	var foe: GameUnit = units[1]
	_main.seed_tray_rng(7)
	var rng_before: int = _main._tray_rng.state
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), units[0], t, true)
	assert_str(str(r["step"])).override_failure_message("the core's answer: %s" % r).is_equal("done")
	assert_int(int(r["steps"])).is_greater_equal(2)
	assert_int(_main._tray_rng.state).override_failure_message("the tray threw no die").is_not_equal(rng_before)


## Step 19b: the first capture sends the game header (once per game, shared with the AI's search), so the core reads
## the game's rules epoch. Probe rule (step_activation_binding_test's): Speed Feat (epoch 7) gives its bearer an 8"
## Advance in the last round; at epoch 0 (no header) the core reads the printed 6".
func test_capture_sends_the_game_header_so_the_core_reads_the_game_epoch() -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	var sc: SoloController = _main.solo_controller
	sc.game_rounds = 4
	_main.opr_army_manager.current_round = 4
	var u := ParityTable._make_unit(_main, {"player": 1, "name": "Boyz", "models": 3, "x_in": 0.0, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "orc_marauders",
		"rules": ["Speed Feat"]}, {})
	assert_bool(sc._core_header_done).is_false()
	var h := CoreActivation.capture(_main)
	assert_bool(sc._core_header_done).override_failure_message("no game header sent").is_true()
	var a: Dictionary = sc._core_node_ready().move_allowance(h, u.unit_id)
	assert_float(float(a.get("advance", 0.0))).override_failure_message("Speed Feat at the game epoch: %s" % a) \
		.is_equal(8.0)


## Step 21: the fixture's units off the table again (the next seed rebuilds them).
func _clear(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()


## Step 21 (O4 b): the per-step landings leave the table where the core is - which models died (survivor positions
## in capture order), Shaken - and the dead are gone before the morale die is thrown.
func test_drive_lands_each_step_as_the_core_resolved_it() -> void:
	var bad: Array = []
	var morale_throws := 0
	for s in 50:
		var units := _volley_units()
		var foe: GameUnit = units[1]
		_main.seed_tray_rng(s)
		var throws: Array = []   # [kind, the target's alive count] at each throw
		var on_throw := func(kind: String, _index: int) -> void: throws.append([kind, foe.get_alive_count()])
		var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
		var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), units[0], t, true, on_throw)
		var cu: Dictionary = _main.solo_controller._core_node_ready().plain_of(int(r["handle"]))["units"][foe.unit_id]
		var table: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
		var core: Array = (cu["positions"] as Array).map(func(p: Array) -> Vector3: return Vector3(p[0], p[1], p[2]))
		if table != core or foe.is_shaken != bool(cu["shaken"]):
			bad.append("seed %d: table %s shaken %s | core %s shaken %s" % [s, table, foe.is_shaken, core, cu["shaken"]])
		var saved := false
		for th in throws:   # every throw after the save throw (the morale test) sees the final survivors
			if saved and int(th[1]) != foe.get_alive_count():
				bad.append("seed %d: %d alive at the morale throw, %d after" % [s, th[1], foe.get_alive_count()])
			morale_throws += 1 if saved else 0
			saved = saved or str(th[0]) == "defense"
		_clear(units)
	assert_int(morale_throws).override_failure_message("no seed threw a morale die").is_greater(0)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 10))).is_empty()


## Step 21: a wound that does not kill shows on the existing red wound marker at once.
func test_a_landed_wound_shows_on_the_wound_marker() -> void:
	var foe := ParityTable._make_unit(_main, {"player": 1, "name": "Ogres", "models": 3, "x_in": 12.0, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 3, "game_system": "gf", "faction_folder": "robot_legions", "rules": []}, {})
	var m: ModelInstance = foe.models[1]
	var landing := [{"unit": foe.unit_id, "models": [{"at": m.node.global_position, "wounds_left": 1, "dead": false}]}]
	await CoreActivation.land_step(_main, foe, landing, CoreActivation._start_models(_main), {})
	assert_int(m.wounds_current).is_equal(1)
	assert_object(m.node.get_node_or_null("WoundMarker")).override_failure_message("no wound marker").is_not_null()


## Step 28 fixture: a human unit of two models on an AI-seat table; each node carries its network id and its
## ModelInstance, as spawned models do (the move ledger keys its models by the id, the trail radius reads the model).
func _human(uname: String, rules: Array = []) -> GameUnit:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	var u := ParityTable._make_unit(_main, {"player": 1, "name": uname, "models": 2, "x_in": 0.0, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "robot_legions", "rules": rules},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 2, "rules": []})
	for i in u.models.size():
		(u.models[i] as ModelInstance).node.set_meta("network_id", 901 + i)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
	return u


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Screen point whose y=0 table-plane ray hit is (wx, wz) (e2e_retrace_hand_band_test's helper).
func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


## Step 28: a plain unit's open activation drags on the core's bands, and for a plain unit they are the table's.
func test_an_open_plain_unit_drags_on_the_core_bands() -> void:
	var u := _human("Rifles")
	var node: Node3D = (u.models[0] as ModelInstance).node
	assert_bool(CoreActivation.open_session(_main, u)).is_true()
	assert_dict(CoreActivation.bands(_main, u)).override_failure_message("no core bands").is_not_empty()
	var got: Dictionary = _main.object_manager._human_bands(node)
	var table: Dictionary = _main.object_manager.movement_range_controller.bands_for_model(node)
	for k in ["advance", "rush", "charge"]:
		assert_float(float(got.get(k, -1))).override_failure_message("%s: %s" % [k, got]) \
			.is_equal({"advance": 6.0, "rush": 12.0, "charge": 12.0}[k])
		assert_float(float(got[k])).override_failure_message("%s vs the table: %s" % [k, table]).is_equal(float(table[k]))


## Step 28: the start snapshot is where the move ledger puts the activation's start after the first drop (XZ); a second
## open keeps the first snapshot.
func test_the_snapshot_is_the_ledger_start_and_a_second_open_keeps_it() -> void:
	var u := _human("Rifles")
	var a: Node3D = (u.models[0] as ModelInstance).node
	var b: Node3D = (u.models[1] as ModelInstance).node
	assert_bool(CoreActivation.open_session(_main, u)).is_true()
	var om: Node3D = _main.object_manager
	om._selected_objects.append_array([a, b])
	om._start_dragging(_screen(a.global_position.x, a.global_position.z))
	om._update_drag(_screen(a.global_position.x + 2.0 * 0.0254, a.global_position.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(2)
	var s: Dictionary = CoreActivation._sessions[u.unit_id]
	var starts: Dictionary = _main.move_trails.ledger.round_starts_for_unit(u.unit_id, 1)
	assert_int(starts.size()).override_failure_message("ledger starts: %s" % starts).is_equal(2)
	for i in 2:
		assert_float(_xz(s["start_pos"][i]).distance_to(starts.get(901 + i, Vector2.INF))).is_less(0.0001)
	assert_float(_xz(a.global_position).distance_to(_xz(s["start_pos"][0]))).override_failure_message("no drag") \
		.is_greater(0.02)
	var pos_before: Array = (s["start_pos"] as Array).duplicate()
	var rot_before: Array = (s["start_rot"] as Array).duplicate()
	a.rotation.y += 1.0
	assert_bool(CoreActivation.open_session(_main, u)).override_failure_message("a second open").is_false()
	assert_array(CoreActivation._sessions[u.unit_id]["start_pos"]).is_equal(pos_before)
	assert_array(CoreActivation._sessions[u.unit_id]["start_rot"]).is_equal(rot_before)


## Step 28 (O14 (1b)): a unit with a non-movement rule opens a session too, but keeps the table's bands.
func test_a_furious_unit_opens_a_session_without_core_bands() -> void:
	var u := _human("Berserkers", ["Furious"])
	assert_bool(CoreActivation.open_session(_main, u)).is_true()
	assert_bool(CoreActivation.session_open(u.unit_id)).is_true()
	assert_dict(CoreActivation.bands(_main, u)).is_empty()


func test_no_session_opens_with_the_flag_off() -> void:
	var u := _human("Rifles")
	CoreActivation._env = 0
	assert_bool(CoreActivation.open_session(_main, u)).is_false()
	assert_bool(CoreActivation.session_open(u.unit_id)).is_false()


## R6: a unit that comes back moved but not activated (an MP rejoin) starts where the ledger says its round began, not
## where it stands, so a new Start cannot launder the move.
func test_a_unit_that_moved_this_round_starts_at_its_ledger_start() -> void:
	var u := _human("Rifles")
	var from: Array = []
	for i in 2:
		var n: Node3D = (u.models[i] as ModelInstance).node
		from.append(_xz(n.global_position))
		var to: Vector2 = from[i] + Vector2(5.0 * 0.0254, 0.0)
		_main.move_trails.ledger.record(1, u.unit_id, u.get_name(), 901 + i, PackedVector2Array([from[i], to]), 1)
		n.global_position = Vector3(to.x, n.global_position.y, to.y)
	u.unit_properties["moved_round"] = 1
	assert_bool(CoreActivation.open_session(_main, u)).is_true()
	var got: Array = (CoreActivation._sessions[u.unit_id]["start_pos"] as Array).map(_xz)
	assert_array(got).is_equal(from)


## R4 hand-off: reset_all closes every session and releases its core handle (the game lifecycle calls it).
func test_reset_all_closes_every_session() -> void:
	var a := _human("Alpha")
	var b := _human("Bravo")
	CoreActivation.open_session(_main, a)
	CoreActivation.open_session(_main, b)
	assert_str(CoreActivation.open_unit_name(_main, b)).is_equal("Alpha")
	var h := int(CoreActivation._sessions[a.unit_id]["handle"])
	CoreActivation.reset_all(_main)
	assert_bool(CoreActivation.session_open(a.unit_id) or CoreActivation.session_open(b.unit_id)).is_false()
	assert_str(CoreActivation.open_unit_name(_main, null)).is_empty()
	assert_dict(_main.solo_controller._core_node_ready().move_allowance(h, a.unit_id)).is_empty()


## Step 29: the REAL NetworkManager with only its transport swapped out; it records every wire frame (pattern:
## e2e_mp_log_channel_test's FakeNet). Seat 1 is this table's.
class FakeNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:
		sent.append({"m": method, "a": args})
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


func _recording_net() -> FakeNet:
	var net := FakeNet.new()
	net.army_manager = _main.opr_army_manager
	_net = net
	_main.network_manager = net
	return net


func _log_lines(text: String) -> Array:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text)


func _toasts(text: String) -> Array:
	return _main.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == text)


## Step 29 (O9, O14 (1b), O15 (2)): every door that starts-and-ends in one press today - the card's Activate, the
## Activated chip, the radial toggle - STARTS the activation of a lifecycle unit, a "Furious" one too: a session, the unit
## not activated, no unit_activated, one log line, and that line is the start's only wire frame.
func test_activate_starts_the_activation_through_every_door() -> void:
	var rmc: Node = _main.radial_menu_controller
	var doors := {
		"card": func(u: GameUnit) -> void: await rmc.card_start_activation(u),
		"chip": func(u: GameUnit) -> void: await rmc.card_toggle_activation(u),
		"radial": func(u: GameUnit) -> void: await rmc._on_action_selected("toggle_activate", {"game_unit": u}),
	}
	var activated: Array = []
	rmc.unit_activated.connect(func(gu: GameUnit) -> void: activated.append(gu.get_name()))
	var bad: Array = []
	for door in doors:
		var u := _human("Berserkers_%s" % door, ["Furious"])
		var net := _recording_net()
		await (doors[door] as Callable).call(u)
		var sentence := "%s begins its activation." % u.get_name()
		if not CoreActivation.session_open(u.unit_id) or u.is_activated:
			bad.append("%s: session %s, activated %s" % [door, CoreActivation.session_open(u.unit_id), u.is_activated])
		if _log_lines(sentence).size() != 1:
			bad.append("%s: %d log lines" % [door, _log_lines(sentence).size()])
		var frames: Array = net.sent.map(func(f: Dictionary) -> String: return "%s %s" % [f["m"], f["a"][1]])
		if frames != ["sync_log_event %s" % sentence]:
			bad.append("%s: frames %s" % [door, frames])
		CoreActivation.reset_all(_main)   # the next door's unit is not locked by this one
		_end_session()
	assert_array(activated).override_failure_message("unit_activated: %s" % [activated]).is_empty()
	assert_array(bad).override_failure_message("\n".join(bad)).is_empty()


## Step 29 (O5): while A's activation is open, Activate on B says the O5 sentence (toast and log line), opens nothing.
func test_activate_while_another_activation_is_open_names_it() -> void:
	var a := _human("Alpha")
	var b := _human("Bravo")
	await _main.radial_menu_controller.card_start_activation(a)
	await _main.radial_menu_controller.card_start_activation(b)
	assert_bool(CoreActivation.session_open(b.unit_id) or b.is_activated).is_false()
	assert_int(_log_lines("Finish Alpha's activation first.").size()).is_equal(1)
	assert_int(_toasts("Finish Alpha's activation first.").size()).is_equal(1)


## Step 29: the room's turn gate stays in front of the Start door - an agreed room with the token on the other side.
func test_activate_off_turn_in_an_agreed_room_starts_nothing() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_recording_net()
	_main._ensure_solo_controller()
	var u := _unit(1, "Rifles", ["Furious"])
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).override_failure_message("precondition").is_true()
	_main._apply_turn_token(2)
	await _main.radial_menu_controller.card_start_activation(u)
	assert_int(_log_lines("It is P2's turn").size()).is_equal(1)
	assert_bool(CoreActivation.session_open(u.unit_id) or u.is_activated).is_false()
	_end_session()


## Step 29: with the flag off the door activates as today. A second human unit keeps the round open, and the frames let
## the AI's owed reply finish before the table is freed.
func test_with_the_flag_off_activate_activates_as_today() -> void:
	var u := _human("Rifles")
	_human("Reserves")
	CoreActivation._env = 0
	await _main.radial_menu_controller.card_start_activation(u)
	assert_bool(u.is_activated).is_true()
	assert_bool(CoreActivation.session_open(u.unit_id)).is_false()
	await _runner.simulate_frames(10)


## Step 30: a real drag start of `objs` (the object_manager_test pattern); the objects it lifted. A started drag is
## cancelled again, so the models stand where they stood.
func _lifted(objs: Array) -> Array:
	var om: Node3D = _main.object_manager
	om._selected_objects.clear()
	for o in objs:
		om._selected_objects.append(o)
	om._start_dragging(Vector2.ZERO)
	var lifted: Array = om._drag_start_positions.keys() if om._is_dragging else []
	om._cancel_drag()
	return lifted


func _drag_starts(objs: Array) -> bool:
	return not _lifted(objs).is_empty()


func _node(u: GameUnit, i: int = 0) -> Node3D:
	return (u.models[i] as ModelInstance).node


## Step 30 (O9, O15 (1)): a lifecycle unit that was not started cannot be dragged: nothing lifts, one toast and one log
## line; after the Start the same drag lifts.
func test_a_unit_that_was_not_started_cannot_be_dragged() -> void:
	var u := _human("Rifles")
	var at := _node(u).global_position
	assert_bool(_drag_starts([_node(u)])).override_failure_message("dragged without a Start").is_false()
	assert_vector(_node(u).global_position).is_equal(at)
	assert_int(_log_lines("Activate Rifles first.").size()).is_equal(1)
	assert_int(_toasts("Activate Rifles first.").size()).is_equal(1)
	CoreActivation.open_session(_main, u)
	assert_bool(_drag_starts([_node(u)])).override_failure_message("no drag after the Start").is_true()


## Step 30 (O5): with A's activation open, a model of B says the O5 sentence.
func test_a_drag_while_another_activation_is_open_names_it() -> void:
	var a := _human("Alpha")
	var b := _human("Bravo")
	CoreActivation.open_session(_main, a)
	assert_bool(_drag_starts([_node(b)])).is_false()
	assert_int(_log_lines("Finish Alpha's activation first.").size()).is_equal(1)


## Step 30 (O14 (1b)): a "Furious" unit is blocked the same way; terrain is never blocked; a joined hero moves with its
## started host; with the flag off every unit drags.
func test_the_drag_gate_covers_every_lifecycle_unit_and_nothing_else() -> void:
	var furious := _human("Berserkers", ["Furious"])
	assert_bool(_drag_starts([_node(furious)])).override_failure_message("Furious dragged").is_false()
	var terrain: Node3D = _main.object_manager.spawn_terrain(Vector3(1.0, 0.0, 1.0), false)
	assert_bool(_drag_starts([terrain])).override_failure_message("terrain refused").is_true()
	var host := _human("Rifles")
	var hero := _human("Captain")
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	CoreActivation.open_session(_main, host)
	assert_array(_lifted([_node(host), _node(hero)])).override_failure_message("hero left behind") \
		.contains_exactly_in_any_order([_node(host), _node(hero)])
	CoreActivation.reset_all(_main)
	CoreActivation._env = 0
	assert_bool(_drag_starts([_node(furious)])).override_failure_message("flag off").is_true()
