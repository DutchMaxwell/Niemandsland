extends GdUnitTestSuite
## Automodus 0.3.15 step 3.1: the Charge / Advance & Shoot / Rush verbs are offered wherever the
## engine resolves: co-op (an AI seat), an agreed online Automatic room (own units only), and a
## hotseat Automatic table (the side holding the turn). Manual tables never. The landing preview
## stays on the acting machine: it sends nothing. Pins solo_auto_eligible (the hide switch stays).

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
