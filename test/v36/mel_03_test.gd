extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-03: a charger's Impact dice roll before EITHER side strikes, so from epoch 73
## the defender's Counter weapons strike after Impact, on both table melee paths (the AI's charge and
## yours), with the Impact stage card ahead of the Counter card. Epoch 72 keeps Counter first. An Impact
## roll that wipes the defender leaves nobody to strike first.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const COUNTER_AFTER_IMPACT_LINE := "strikes first, after the Impact dice (rules 3.6)"

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


## `models` models of `tough` wounds each at `x` inches, one melee weapon, the given unit rules and Defense.
func _unit(pid: int, unit_name: String, x: float, models: int, weapon: String, rules: Array, defense: int,
		tough: int = 1) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon
	w.range_value = 0
	w.attacks = 1
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["special_rules"] = rules + (["Tough(%d)" % tough] if tough > 1 else [])
	u.unit_properties["defense"] = defense
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Battle-log index of the first line holding `needle`, -1 when none does.
func _line_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## The AI charges a Counter defender: 2 chargers x Impact(4) minus 2 Counter models = 6 Impact dice.
## Tough(9) on both sides means no model can fall in either order, so neither leg depends on the dice.
func _ai_charge(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 2, "Blade", ["Impact(4)"], 4, 9)
	var defender := _unit(1, "Defender", 1.0, 2, "Spikes", ["Counter"], 4, 9)
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})


func test_impact_rolls_before_the_counter_strike_at_epoch_73(timeout := 90000) -> void:
	await _ai_charge(AiActRecorder.EPOCH_73_V36)
	var impact := _line_of("Impact(4) rolls")
	var counter := _line_of("strikes with Spikes")
	assert_bool(impact >= 0 and counter >= 0) \
		.override_failure_message("both the Impact roll and the Counter strike must be logged (%d, %d)" % [impact, counter]) \
		.is_true()
	assert_bool(impact < counter) \
		.override_failure_message("rules 3.6: Impact rolls before the Counter strike (Impact line %d, Counter line %d)" % [impact, counter]) \
		.is_true()
	assert_int(_line_of(COUNTER_AFTER_IMPACT_LINE)) \
		.override_failure_message("the log must say that Counter struck after the Impact dice") \
		.is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_counter_strikes_before_impact_at_epoch_72(timeout := 90000) -> void:
	await _ai_charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var impact := _line_of("Impact(4) rolls")
	var counter := _line_of("strikes with Spikes")
	assert_bool(counter >= 0 and counter < impact) \
		.override_failure_message("epoch 72 keeps Counter first (Counter line %d, Impact line %d)" % [counter, impact]) \
		.is_true()
	assert_int(_line_of(COUNTER_AFTER_IMPACT_LINE)).is_equal(-1)
	await E2EBoot.settle(get_tree())


## 2 chargers x Impact(6) minus 1 Counter model = 11 dice into one model saving on 6+: Impact wipes it.
func test_an_impact_wipe_leaves_no_counter_strike_at_epoch_73(timeout := 90000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var charger := _unit(2, "Charger", 0.0, 2, "Blade", ["Impact(6)"], 4)
	var defender := _unit(1, "Defender", 1.0, 1, "Spikes", ["Counter"], 6)
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	assert_int(_main._solo_combined_alive(defender)).is_equal(0)
	assert_int(_line_of("strikes with Spikes")) \
		.override_failure_message("a defender wiped by Impact has nobody left to strike first") \
		.is_equal(-1)
	await E2EBoot.settle(get_tree())


## Your charge: the AI defender's Counter strike and its stage card both follow the Impact card.
func test_your_charge_rolls_impact_before_the_counter_card_at_epoch_73(timeout := 90000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var charger := _unit(1, "Charger", 0.0, 2, "Blade", ["Impact(4)"], 4, 9)
	var defender := _unit(2, "Defender", 1.0, 2, "Spikes", ["Counter"], 4, 9)
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	_main.seed_tray_rng(7)
	await _main._run_human_melee(charger, defender)
	var impact := _line_of("Impact(4) rolls")
	var counter := _line_of("strikes with Spikes")
	assert_bool(impact >= 0 and impact < counter) \
		.override_failure_message("rules 3.6: Impact rolls before the Counter strike (Impact line %d, Counter line %d)" % [impact, counter]) \
		.is_true()
	assert_int(_line_of(COUNTER_AFTER_IMPACT_LINE)).is_greater_equal(0)
	var titles: Array = []
	for ph in _main.combat_stage._phases:
		titles.append(str((ph as Dictionary)["title"]))
	assert_bool(titles.has("Impact") and titles.find("Impact") < titles.find("Counter")) \
		.override_failure_message("the Impact card must come before the Counter card (got: %s)" % str(titles)) \
		.is_true()
	await E2EBoot.settle(get_tree())
