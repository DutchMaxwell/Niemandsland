extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-11: Ravage rolls once per round, before the unit attacks, and never while
## the unit is Fatigued (a Shaken strike-back counts). Epoch 72 keeps the old roll on every strike.
## Drives the real strike phase over main.tscn (the e2e_shaken_strikeback shape).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## How many Ravage pools the log shows rolled.
func _ravage_rolls() -> int:
	return _log_text().count("Ravage(2): Maulers rolls")


## One Q4 Ravage(2) model with a plain melee weapon, and a ten-model foe that outlives two strikes.
func _strike(rules_epoch: int, fatigued: bool, strikes: int) -> void:
	AiActRecorder.rules_epoch = rules_epoch
	var u := E2EBoot.make_unit(_main, 1, "Maulers", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Club"
	w.range_value = 0
	w.attacks = 1
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["special_rules"] = ["Ravage(2)"]
	u.unit_properties["faction_folder"] = "alien_hives"   # a book that fields Ravage (registry gate)
	u.is_fatigued = fatigued
	_main.opr_army_manager.game_units[u.unit_id] = u
	var spots: Array = []
	for i in range(10):
		spots.append(Vector3((0.5 + i) * INCH, 0, 0.5 * INCH))
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", spots)
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	for i in range(strikes):
		await _main._solo_melee_strike_phase(u, foe, false, 0)   # 0 = SoloStrike.ALL, a strike-back


func test_a_fatigued_ravager_still_rolls_ravage_at_epoch_72() -> void:
	await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true, 1)
	assert_int(_ravage_rolls()).override_failure_message("the old leg rolls Ravage while Fatigued (log: %s)" % _log_text()) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_a_fatigued_ravager_rolls_no_ravage_at_epoch_73() -> void:
	await _strike(AiActRecorder.EPOCH_73_V36, true, 1)
	assert_int(_ravage_rolls()).override_failure_message("a Fatigued unit rolls no Ravage (log: %s)" % _log_text()) \
		.is_equal(0)
	assert_str(_log_text()).override_failure_message("rules-must-log — the skip must name Ravage") \
		.contains("Ravage: Maulers is Fatigued")
	await E2EBoot.settle(get_tree())


func test_a_second_strike_in_a_round_rolls_ravage_again_at_epoch_72() -> void:
	await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, false, 2)
	assert_int(_ravage_rolls()).override_failure_message("the old leg rolls Ravage on every strike (log: %s)" % _log_text()) \
		.is_equal(2)
	await E2EBoot.settle(get_tree())


func test_a_second_strike_in_a_round_rolls_no_ravage_at_epoch_73() -> void:
	await _strike(AiActRecorder.EPOCH_73_V36, false, 2)
	assert_int(_ravage_rolls()).override_failure_message("Ravage rolls once per round (log: %s)" % _log_text()) \
		.is_equal(1)
	assert_str(_log_text()).override_failure_message("rules-must-log — the second skip must name Ravage") \
		.contains("Ravage: Maulers already used it this round")
	await E2EBoot.settle(get_tree())


## The EV twin: 6 Ravage dice are worth one wound (6 x 1/6), and nothing for a Fatigued attacker at 73.
func test_a_fatigued_attacker_still_prices_ravage_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_float(AiEv.ravage_ev({"ravage": 2, "models": 3, "fatigued": true}, {})).is_equal_approx(1.0, 0.000001)


func test_a_fatigued_attacker_prices_no_ravage_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_float(AiEv.ravage_ev({"ravage": 2, "models": 3, "fatigued": true}, {})).is_equal(0.0)
	assert_float(AiEv.ravage_ev({"ravage": 2, "models": 3}, {})).is_equal_approx(1.0, 0.000001)
