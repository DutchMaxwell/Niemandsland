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
