extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AIG-G2 row R3 (fault 2): the move-through volley of a Crossing Strike weapon is
## aimed at the unit the bearer flew over, so the weapon's printed range does not apply to it. A range-0
## weapon (Zeppelins' Drop Bombs) used to answer "no models in range or sight" and roll nothing. From
## EPOCH_73_V36 the volley rolls; epoch 72 replays the silence. Twin of
## core/nml-core/src/tests/sim/v36_shoot_rows/aig_g2_r3_reach.rs. The flight is the real straight-lane mover
## (_aircraft_move, and _act_aircraft for the AI's own heading), the trigger the real _solo_apply_strafing.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const LINE := "Crossing Strike: Zeppelins passes over Warriors"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x: float, weapon_name: String, weapon_rules: Array, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0.0, 0.0)])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = range_in
	w.attacks = 4
	w.special_rules.assign(weapon_rules)
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["defense"] = 4
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The bomber at -28", the enemy ON its lane at -10"; the lane is flown by the real mover (`ai_lane` false:
## a forced 30" run along +x) or picked by the AI's own heading logic (`ai_lane` true), then the trigger runs.
func _fly(epoch: int, range_in: int, ai_lane: bool) -> void:
	AiActRecorder.rules_epoch = epoch
	var sc: SoloController = _main.solo_controller
	sc.human_slot = 1
	var bird := _unit(2, "Zeppelins", -28.0, "Drop Bombs", ["Crossing Strike"], range_in)
	_unit(1, "Warriors", -10.0, "Spear", [], 0)
	_main.seed_tray_rng(7)
	if ai_lane:
		sc._act_aircraft(bird, {})
	else:
		sc._aircraft_move(bird, Vector2(1, 0), 30.0)
	await _main._solo_apply_strafing(bird)


func test_a_range_zero_crossing_strike_weapon_rolls_on_a_forced_lane_at_epoch_73(timeout := 90000) -> void:
	await _fly(AiActRecorder.EPOCH_73_V36, 0, false)
	assert_str(_log_text()).contains(LINE)
	assert_str(_log_text()).override_failure_message("the move-through volley stayed silent").not_contains("Drop Bombs silent")
	assert_str(_log_text()).contains("Zeppelins fires Drop Bombs at Warriors")
	await E2EBoot.settle(get_tree())


func test_a_range_zero_crossing_strike_weapon_rolls_on_the_ais_own_lane_at_epoch_73(timeout := 90000) -> void:
	await _fly(AiActRecorder.EPOCH_73_V36, 0, true)
	assert_str(_log_text()).contains(LINE)
	assert_str(_log_text()).override_failure_message("the move-through volley stayed silent").not_contains("Drop Bombs silent")
	assert_str(_log_text()).contains("Zeppelins fires Drop Bombs at Warriors")
	await E2EBoot.settle(get_tree())


## Epoch 72 replays today's silence: the trigger fires, the volley rolls nothing.
func test_a_range_zero_crossing_strike_weapon_stays_silent_at_epoch_72(timeout := 90000) -> void:
	await _fly(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 0, false)
	assert_str(_log_text()).contains(LINE)
	assert_str(_log_text()).contains("Drop Bombs silent")
	await E2EBoot.settle(get_tree())


## Controls: a weapon with a printed range that covers the crossed unit rolls at both epochs.
func test_a_ranged_crossing_strike_weapon_rolls_at_epoch_72(timeout := 90000) -> void:
	await _fly(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 24, false)
	assert_str(_log_text()).contains("Zeppelins fires Drop Bombs at Warriors")
	await E2EBoot.settle(get_tree())


func test_a_ranged_crossing_strike_weapon_rolls_at_epoch_73(timeout := 90000) -> void:
	await _fly(AiActRecorder.EPOCH_73_V36, 24, false)
	assert_str(_log_text()).contains("Zeppelins fires Drop Bombs at Warriors")
	await E2EBoot.settle(get_tree())
