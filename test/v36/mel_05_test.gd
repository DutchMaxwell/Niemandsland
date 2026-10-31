extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-05: from epoch 73 a Counter unit takes no Impact dice off a charger and
## only strikes first when it is neither Fatigued nor Shaken. Epoch 72 keeps the old cut and the
## unconditional strike-first. A unit without Counter is the control.

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


## `models` models of `tough` wounds each at `x` inches, one melee weapon carrying `weapon_rules`.
func _unit(pid: int, unit_name: String, x: float, models: int, weapon_rules: Array, rules: Array,
		defense: int, tough: int = 1) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	w.count = models
	w.special_rules.assign(weapon_rules)
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["special_rules"] = rules
	u.unit_properties["defense"] = defense
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _line_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## The dice count off the Impact roll's own battle-log line ("Charger: Impact(3) rolls 3 dice ...").
func _impact_dice() -> int:
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.contains("Impact(") and t.contains(" rolls "):
			return int(t.split(" rolls ")[1].split(" ")[0])
	return -1


## One AI charge: a one-model Impact(3) charger into a two-model defender whose melee weapon carries
## Counter when `counter`, with the defender Fatigued / Shaken as asked.
func _charge(epoch: int, counter: bool, fatigued: bool, shaken: bool) -> void:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 1, [], ["Impact(3)"], 4, 9)
	var defender := _unit(1, "Defender", 1.0, 2, (["Counter"] if counter else []), [], 4, 9)
	defender.is_fatigued = fatigued
	defender.is_shaken = shaken
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})


func test_counter_cuts_two_impact_dice_at_epoch_72(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true, false, false)
	assert_int(_impact_dice()).is_equal(1)
	assert_int(_line_of("Counter: -2 Impact dice")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_counter_cuts_no_impact_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, true, false, false)
	assert_int(_impact_dice()).is_equal(3)
	assert_int(_line_of("Counter: -")).is_equal(-1)
	await E2EBoot.settle(get_tree())


func test_a_fresh_counter_defender_strikes_first_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, true, false, false)
	assert_int(_line_of("Counter: Defender strikes first")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_fatigued_counter_defender_does_not_strike_first_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, true, true, false)
	assert_int(_line_of("Counter: Defender is Fatigued - no strike-first")).is_greater_equal(0)
	assert_int(_line_of("Counter: Defender strikes first")).is_equal(-1)
	await E2EBoot.settle(get_tree())


func test_a_shaken_counter_defender_does_not_strike_first_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, true, false, true)
	assert_int(_line_of("Counter: Defender is Fatigued - no strike-first")).is_greater_equal(0)
	assert_int(_line_of("Counter: Defender strikes first")).is_equal(-1)
	await E2EBoot.settle(get_tree())


func test_a_control_unit_without_counter_rolls_three_at_both_epochs(timeout := 180000) -> void:
	await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, false, false, false)
	assert_int(_impact_dice()).is_equal(3)
	await E2EBoot.settle(get_tree())
	await _charge(AiActRecorder.EPOCH_73_V36, false, false, false)
	assert_int(_impact_dice()).is_equal(3)
	await E2EBoot.settle(get_tree())


func test_counter_strikes_first_is_unchanged_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := _unit(1, "Defender", 1.0, 2, ["Counter"], [], 4)
	u.is_fatigued = true
	assert_bool(SoloController.counter_strikes_first(u)).is_true()


func test_counter_strikes_first_is_false_for_a_fatigued_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit(1, "Defender", 1.0, 2, ["Counter"], [], 4)
	u.is_fatigued = true
	assert_bool(SoloController.counter_strikes_first(u)).is_false()


func test_counter_strikes_first_is_false_for_a_shaken_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit(1, "Defender", 1.0, 2, ["Counter"], [], 4)
	u.is_shaken = true
	assert_bool(SoloController.counter_strikes_first(u)).is_false()


func test_counter_strikes_first_stays_true_for_a_fresh_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit(1, "Defender", 1.0, 2, ["Counter"], [], 4)
	assert_bool(SoloController.counter_strikes_first(u)).is_true()
