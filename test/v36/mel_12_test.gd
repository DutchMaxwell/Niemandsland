extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-12: Regenerative Strength's tokens roll one die each for direct
## wounds (4+) once per round, before the strikes and never while Fatigued, instead of adding
## attacks. Epoch 72 keeps today's behaviour and rolls no token dice.
## Drives the real strike phase over main.tscn (the mel_11 / e2e_shaken_strikeback shape).

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


## One Q4 melee striker carrying `rule` with `tokens` markers, and a ten-model foe that outlives
## two strikes. `filter` 0 = SoloStrike.ALL, the unit's own melee turn.
func _strike(rules_epoch: int, fatigued: bool, strikes: int, rule: String, tokens: int) -> void:
	AiActRecorder.rules_epoch = rules_epoch
	var u := E2EBoot.make_unit(_main, 1, "Wardens", [Vector3.ZERO])
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
	u.unit_properties["special_rules"] = [rule]
	u.unit_properties["faction_folder"] = "alien_hives"   # a book that fields the rule (registry gate)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["growth_%s" % rule.to_snake_case()] = tokens
	u.is_fatigued = fatigued
	_main.opr_army_manager.game_units[u.unit_id] = u
	var spots: Array = []
	for i in range(10):
		spots.append(Vector3((0.5 + i) * INCH, 0, 0.5 * INCH))
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", spots)
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	for i in range(strikes):
		await _main._solo_melee_strike_phase(u, foe, false, 0)


func test_regenerative_strength_rolls_one_die_per_token_at_epoch_73() -> void:
	await _strike(AiActRecorder.EPOCH_73_V36, false, 1, "Regenerative Strength", 3)
	var text := _log_text()
	assert_int(text.count("Regenerative Strength: Wardens rolls 3 dice,")) \
		.override_failure_message("one token batch of 3 dice (log: %s)" % text).is_equal(1)
	await E2EBoot.settle(get_tree())


func test_a_fatigued_regenerative_strength_unit_rolls_no_token_dice_at_epoch_73() -> void:
	await _strike(AiActRecorder.EPOCH_73_V36, true, 1, "Regenerative Strength", 3)
	var text := _log_text()
	assert_int(text.count("Regenerative Strength: Wardens rolls 3 dice,")) \
		.override_failure_message("a Fatigued unit rolls no token dice (log: %s)" % text).is_equal(0)
	assert_str(text).override_failure_message("rules-must-log — the skip must name the rule") \
		.contains("Regenerative Strength: Wardens is Fatigued")
	await E2EBoot.settle(get_tree())


func test_a_second_activation_in_the_same_round_rolls_no_second_token_batch_at_epoch_73() -> void:
	await _strike(AiActRecorder.EPOCH_73_V36, false, 2, "Regenerative Strength", 3)
	var text := _log_text()
	assert_int(text.count("Regenerative Strength: Wardens rolls 3 dice,")) \
		.override_failure_message("once per round (log: %s)" % text).is_equal(1)
	assert_str(text).override_failure_message("rules-must-log — the second skip must name the rule") \
		.contains("Regenerative Strength: Wardens already rolled its dice this round")
	await E2EBoot.settle(get_tree())


func test_regenerative_strength_rolls_no_token_dice_at_epoch_72() -> void:
	await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, false, 1, "Regenerative Strength", 3)
	assert_int(_log_text().count("Regenerative Strength:")) \
		.override_failure_message("below 73 the rule is not played (log: %s)" % _log_text()).is_equal(0)
	await E2EBoot.settle(get_tree())


## CONTROL — a different Growth Markers rule keeps whatever payout it had: it never rolls the
## Regenerative Strength token dice, before or after this row.
func test_another_growth_markers_rule_rolls_no_token_dice_at_epoch_73() -> void:
	await _strike(AiActRecorder.EPOCH_73_V36, false, 1, "Piercing Growth", 3)
	assert_int(_log_text().count("Regenerative Strength:")) \
		.override_failure_message("no Regenerative Strength, no token dice (log: %s)" % _log_text()).is_equal(0)
	await E2EBoot.settle(get_tree())
