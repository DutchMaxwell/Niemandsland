extends GdUnitTestSuite
## Rules 3.6, fix S6: a Crossing Strike weapon's move-through attack is resolved like a shooting attack
## (army-book weapon rule, 3.6.0 books), and the Shred when Shooting rule grants Shred to the model's weapons
## when it shoots. So a Crossing Strike volley of a "Shred when Shooting" bearer deals the Shred extra wounds,
## and the battle log names the Shred rule (the core names it by the primitive on the move-through volley). The
## move-through volley used to skip the unit-level Shred stamp. Resolved through the rules core (one-core door):
## the core ports the table's stamp at EPOCH_75_TABLE_FIXES; epoch 72 replays the volley without the stamp.
## Instrument: a large volley into a Defense 6+ target on a seeded tray, read through the battle log's Shred line.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SHRED_LINE := " of 1 → +"   # the Shred family's save-step line ("<rule>: N Defense rolls of 1 → +N wounds")
const SHRED_NAMED := "Shred when Shooting: "   # the granting rule's name opens the ordinary volley's line
const SHRED_DOOR := "Shred: "   # the core names the same fact by its primitive on the move-through volley

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int
var _enforce0: bool


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_enforce0 = GraphicsSettings.enforce_movement_limit
	GraphicsSettings.enforce_movement_limit = false   # the aircraft's mandatory 30" flight is no drag cap
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	CoreActivation._env = -1
	GraphicsSettings.enforce_movement_limit = _enforce0
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()


func _unit(pid: int, unit_name: String, x: float, weapon_rules: Array, range_in: int, rules: Array,
		defense: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0.0, 0.0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = rules
	u.unit_properties["quality"] = 2
	u.unit_properties["defense"] = defense
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Strafe Guns"
	w.range_value = range_in
	w.attacks = 40
	w.special_rules.assign(weapon_rules)
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	for m in u.models:
		(m as ModelInstance).wounds_max = 400
		(m as ModelInstance).wounds_current = 400
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The move-through volley: the bearer flies a forced 30" lane over the target, then the rules core resolves the
## strike from the captured board and the flown trails.
func _strafe(range_in: int, epoch: int = AiActRecorder.EPOCH_75_TABLE_FIXES) -> String:
	AiActRecorder.rules_epoch = epoch
	var sc: SoloController = _main.solo_controller
	var bird := _unit(2, "Gunship", -28.0, ["Crossing Strike"], range_in, ["Shred when Shooting"], 4)
	_unit(1, "Wardens", -10.0, [], 0, [], 6)
	_main.seed_tray_rng(7)
	var h := CoreActivation.capture(_main)
	_main._solo_core_ai_h = h
	sc._aircraft_move(bird, Vector2(1, 0), 30.0)
	bird.unit_properties["moved_round"] = 1   # the planner's apply stamps the move the core sees
	var report := {"unit": bird, "moved": true, "action": AiDecision.Action.ADVANCE, "can_shoot": false, "core_through": true}
	var runs := CoreActivation.ai_runs
	await _main._solo_ai_core_call(bird, report, null, [])
	if _main._solo_core_ai_h != 0:
		sc._core_node_ready().release(_main._solo_core_ai_h)
		_main._solo_core_ai_h = 0
	assert_int(CoreActivation.ai_runs - runs).override_failure_message("the rules core did not resolve the strike").is_greater(0)
	return _log_text()


## CONTROL (instrument): the same bearer and gun WITHOUT Crossing Strike, fired as an ordinary volley through the
## rules core, shows the Shred line. Proves the reader sees the unit-level stamp when it is there.
func test_control_an_ordinary_volley_of_a_shred_when_shooting_bearer_shreds(timeout := 90000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_75_TABLE_FIXES
	var sc: SoloController = _main.solo_controller
	var gun := _unit(2, "Gunship", -28.0, [], 24, ["Shred when Shooting"], 4)
	_unit(1, "Wardens", -10.0, [], 0, [], 6)
	_main.seed_tray_rng(7)
	var h := CoreActivation.capture(_main, true)
	_main._solo_core_ai_h = h
	var runs := CoreActivation.ai_runs
	await _main._run_ai_shooting(ActIntent.blank_report(gun))
	if _main._solo_core_ai_h != 0:
		sc._core_node_ready().release(_main._solo_core_ai_h)
		_main._solo_core_ai_h = 0
	assert_int(CoreActivation.ai_runs - runs).override_failure_message("the rules core did not resolve the ordinary volley").is_greater(0)
	var text := _log_text()
	assert_str(text).override_failure_message("fixture: the ordinary volley must fire (log: %s)" % text) \
		.contains("Gunship fires Strafe Guns at Wardens")
	assert_str(text).override_failure_message("ordinary volley: no Shred line (log: %s)" % text) \
		.contains(SHRED_LINE)
	assert_str(text).override_failure_message("ordinary volley: the Shred line does not name its rule (log: %s)" % text) \
		.contains(SHRED_NAMED)
	await E2EBoot.settle(get_tree())


## S6 (ranged Crossing Strike weapon): the move-through volley must shred like any other shooting attack.
func test_s6_a_ranged_crossing_strike_volley_of_a_shred_when_shooting_bearer_shreds(timeout := 90000) -> void:
	var text := await _strafe(24)
	assert_str(text).override_failure_message("fixture: the move-through volley must fire (log: %s)" % text) \
		.contains("Gunship fires Strafe Guns at Wardens")
	assert_str(text).override_failure_message("S6: the Crossing Strike volley lost Shred (log: %s)" % text) \
		.contains(SHRED_LINE)
	assert_str(text).override_failure_message("S6: the Shred line does not name its rule (log: %s)" % text) \
		.contains(SHRED_DOOR)
	await E2EBoot.settle(get_tree())


## S6 (range-0 Crossing Strike weapon, the Drop Bombs shape): same rule, same expectation.
func test_s6_a_range_zero_crossing_strike_volley_of_a_shred_when_shooting_bearer_shreds(timeout := 90000) -> void:
	var text := await _strafe(0)
	assert_str(text).override_failure_message("fixture: the move-through volley must fire (log: %s)" % text) \
		.contains("Gunship fires Strafe Guns at Wardens")
	assert_str(text).override_failure_message("S6: the range-0 Crossing Strike volley lost Shred (log: %s)" % text) \
		.contains(SHRED_LINE)
	assert_str(text).override_failure_message("S6: the range-0 Shred line does not name its rule (log: %s)" % text) \
		.contains(SHRED_DOOR)
	await E2EBoot.settle(get_tree())


## Epoch 72 replays the volley as it was: it fires and rolls its saves, with no unit-level Shred stamp.
func test_s6_epoch_72_crossing_strike_volley_keeps_no_shred_stamp(timeout := 90000) -> void:
	var text := await _strafe(24, AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_str(text).override_failure_message("fixture: the move-through volley must fire (log: %s)" % text) \
		.contains("Gunship fires Strafe Guns at Wardens")
	assert_str(text).override_failure_message("epoch 72 grew a Shred line (log: %s)" % text) \
		.not_contains(SHRED_LINE)
	await E2EBoot.settle(get_tree())
