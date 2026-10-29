extends GdUnitTestSuite
## Automodus 0.3.15 step 3.1: the Charge / Advance & Shoot / Rush verbs are offered wherever the
## engine resolves: co-op (an AI seat), an agreed online Automatic room (own units only), and a
## hotseat Automatic table (the side holding the turn). Manual tables never. The landing preview
## stays on the acting machine: it sends nothing. Pins solo_auto_eligible, the rule under the switch.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

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


func after_test() -> void:
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


## A REAL NetworkManager with only the transport swapped out (pattern: e2e_rules_online_round_host_test).
func _fake_session(my_slot: int, host: bool) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn %d\n" % my_slot \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:\n" \
		+ "\tsent.append({\"m\": method, \"a\": args})\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append({\"cmd\": type, \"a\": [payload, target_peer]})\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = host
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net


func _pair() -> Array:
	var a := E2EBoot.make_unit(_main, 1, "Rifles", [Vector3(-0.3, 0.0, 0.0)])
	var b := E2EBoot.make_unit(_main, 2, "Raiders", [Vector3(0.3, 0.0, 0.0)])
	_main.opr_army_manager.game_units[a.unit_id] = a
	_main.opr_army_manager.game_units[b.unit_id] = b
	return [a, b]


func _level(level: int) -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = level
	_main._hotseat_turn = null


func test_verbs_offered_to_own_units_in_an_automatic_room() -> void:
	var u := _pair()
	_level(RulesAutomation.Level.AUTOMATIC)
	_fake_session(1, true)
	assert_bool(_main.solo_auto_eligible(u[0])) \
		.override_failure_message("3.1 - an own unit in an Automatic room is offered the verbs").is_true()
	assert_bool(_main.solo_auto_eligible(u[1])) \
		.override_failure_message("3.1 - a foreign unit is never offered").is_false()
	_level(RulesAutomation.Level.MANUAL)
	assert_bool(_main.solo_auto_eligible(u[0])) \
		.override_failure_message("3.1 - a Manual room offers nothing").is_false()
	_end_session()


func test_verbs_offered_in_co_op() -> void:
	var u := _pair()
	_level(RulesAutomation.Level.MANUAL)
	_main.solo_ai_slots = {3: true}
	_fake_session(1, true)
	var ai := E2EBoot.make_unit(_main, 3, "Drones", [Vector3(0.5, 0.0, 0.0)])
	_main.opr_army_manager.game_units[ai.unit_id] = ai
	assert_bool(_main.solo_auto_eligible(u[0])) \
		.override_failure_message("3.1 - co-op: own unit is offered").is_true()
	assert_bool(_main.solo_auto_eligible(u[1])) \
		.override_failure_message("3.1 - co-op: the other human's unit is not mine").is_false()
	_end_session()


func test_hotseat_automatic_offers_the_side_on_turn() -> void:
	var u := _pair()
	_level(RulesAutomation.Level.AUTOMATIC)
	assert_bool(_main.solo_auto_eligible(u[0])) \
		.override_failure_message("3.1 - hotseat: the side on turn (P1 opens) is offered").is_true()
	assert_bool(_main.solo_auto_eligible(u[1])) \
		.override_failure_message("3.1 - hotseat: the other side is not offered").is_false()
	_level(RulesAutomation.Level.MANUAL)
	assert_bool(_main.solo_auto_eligible(u[0])) \
		.override_failure_message("3.1 - a Manual hotseat table offers nothing").is_false()


func test_preview_stays_local() -> void:
	var u := _pair()
	_level(RulesAutomation.Level.AUTOMATIC)
	_fake_session(1, true)
	await _main.solo_begin_auto(u[0], AiDecision.Action.CHARGE)
	await _runner.simulate_frames(2)
	_main._solo_end_targeting()
	var sent: Array = []
	for e in _net.sent:   # the live cursor ping is background traffic, not the preview
		if str((e as Dictionary).get("m", "")) != "sync_cursor_position":
			sent.append(e)
	assert_int(sent.size()) \
		.override_failure_message("3.1 - the preview sends nothing: %s" % str(sent)).is_equal(0)
	_end_session()


## A one-model unit with one 12" rifle (pattern: e2e_auto_preview_test.gd _shooter).
func _rifle_unit(pid: int, unit_name: String, x_m: float) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_m, 0.0, 0.0)])
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 12
	w.attacks = 10   # with Quality 2+ a volley never misses entirely: the defender's saves always roll
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["quality"] = 2
	u.models[0].node.set_meta("network_id", 7100 + pid)   # real spawned models carry one; batches key on it
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Automodus 3.2 (OD 9): the ACTING player runs its own verb, like every online action today. The guest's
## click moves the guest's models on the guest; the host only receives the move batch (the landing) and the
## activation sync, never a request to run the intent (the host has no such handler), and the attack dice
## roll on the guest's tray through the existing volley path (sync_dice_roll).
func test_guest_verb_runs_on_the_guest_and_replicates(timeout := 60000) -> void:
	_level(RulesAutomation.Level.AUTOMATIC)
	var inch := 0.0254
	var hosts := _rifle_unit(1, "Guards", 0.2 - 16.0 * inch)   # the host's unit, 16" away
	var mine := _rifle_unit(2, "Raiders", 0.2)
	_fake_session(2, false)
	_net.peer_to_slot = {1: 1}   # the host (peer 1) holds slot 1
	var radial_net: Node = _main.radial_menu_controller.network_manager
	_main.radial_menu_controller.network_manager = _net   # the activation sync goes out through the radial (same object in play)
	_main._owner_roll_timeout_s = 0.3
	_main._solo_fast = true
	_main._hotseat_turn = TwoHumanTurn.new()   # the online turn token (3.3a): it is the guest's turn
	_main._hotseat_turn.side_on_turn = 2
	var start: Vector3 = mine.models[0].node.global_position
	await _main.solo_begin_auto(mine, AiDecision.Action.ADVANCE)
	var log_text := ""
	for e in _main.battle_log.entries():
		log_text += str((e as Dictionary)["text"]) + " | "
	assert_array(_main._solo_target_mode.get("auto_valid", [])).override_failure_message(
		"the guest's verb lit nothing (log: %s)" % log_text).contains_exactly([hosts])
	if _main._solo_target_mode.has("auto_verb"):   # a closed mode must fail below, not crash the run
		await _main._solo_auto_click(hosts)
	await E2EBoot.settle(get_tree())
	var end: Vector3 = mine.models[0].node.global_position
	assert_float(MoveIntent.distance_inches(start, end)).override_failure_message(
		"the guest's models did not move on the guest").is_greater(5.0)
	var batches: Array = []
	var activations: Array = []
	var cmds: Array = []
	var dice := 0
	for e in _net.sent:
		var m := str((e as Dictionary).get("m", ""))
		dice += int(m == "sync_dice_roll")
		if m == "move_objects_batch_networked":
			batches.append(e)
		elif m == "sync_unit_activation" and str((e["a"] as Array)[0]) == mine.unit_id:
			activations.append(e)
		elif (e as Dictionary).has("cmd"):
			cmds.append(str(e["cmd"]))
	assert_int(batches.size()).override_failure_message("no move batch went to the host").is_greater(0)
	var batch: Array = (batches[0]["a"] as Array)[0] if not batches.is_empty() else []
	var at := batch.find(7102)   # [network_id, x, y, z, ...]: the guest's model at its landing
	assert_int(at).override_failure_message("the move batch does not carry the guest's model").is_greater_equal(0)
	if at >= 0:
		assert_vector(Vector3(batch[at + 1], batch[at + 2], batch[at + 3])).is_equal_approx(end, Vector3.ONE * 1e-4)
	assert_int(activations.size()).override_failure_message("no activation sync for the guest's unit").is_greater(0)
	assert_bool(mine.is_activated).is_true()
	assert_int(dice).override_failure_message("the guest's attack dice never synced out").is_greater(0)
	assert_int(cmds.size()).override_failure_message("the guest asked the host for more than its roll: %s" % str(cmds)) \
		.is_equal(cmds.count("request_roll"))
	_main.radial_menu_controller.network_manager = radial_net
	_end_session()
