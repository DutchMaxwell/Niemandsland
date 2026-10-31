extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-07c: from rules epoch 73 (the core's EPOCH_73_V36) a defender's
## Parry(X) cancels STRIKE hits after the strike's hit rolls and before any save. Each 6+
## cancels the highest-worth hit, so AP/Rending decides the order, not the die's batch. Epoch
## 72 keeps today's behaviour (no Parry die). The core's twin is
## core/nml-core/src/tests/dice/v36_melee.rs, `mod mel_07c`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 7

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
	_main._solo_dice_trace_enabled = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models at `x` inches with one melee weapon, `rules` and Defense `defense`; Tough(9)
## keeps every model alive so the saves never decide the strike.
func _unit(pid: int, unit_name: String, x: float, models: int, rules: Array, attacks: int,
		quality: int = 4, defense: int = 4) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = attacks
	w.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["special_rules"] = rules + ["Tough(9)"]
	u.unit_properties["defense"] = defense
	u.unit_properties["quality"] = quality
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Battle-log index of the first line holding `needle`, -1 when none does.
func _line_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## One 5-attack Quality 2 striker against 2 models; seed 7 draws [6,2,5,6,4] (5 hits).
func _strike(epoch: int, defender_rules: Array) -> Array:
	AiActRecorder.rules_epoch = epoch
	var attacker := _unit(1, "Charger", 0.0, 1, [], 5, 2)
	var defender := _unit(2, "Defender", 0.5, 2, defender_rules, 1)
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._solo_melee_strike_phase(attacker, defender, true, 0)   # 0 = SoloStrike.ALL
	var rolls: Array = []
	for rec in _main.solo_controller.decision_log:
		if str((rec as Dictionary).get("kind", "")) == "dice":
			rolls.append([str(rec["roll_kind"]), Array(rec["faces"])])
	await E2EBoot.settle(get_tree())
	return rolls


func test_two_parry_models_cancel_a_strike_hit_at_epoch_73(timeout := 90000) -> void:
	var rolls: Array = await _strike(AiActRecorder.EPOCH_73_V36, ["Parry(1)"])
	var kinds: Array = []
	for r in rolls:
		kinds.append(str((r as Array)[0]))
	assert_str(str(kinds)) \
		.override_failure_message("hits, then the 2 Parry dice, then one save batch for the remaining hits: %s" % str(rolls)) \
		.is_equal(str(["attack", "parry", "defense"]))
	var parry: Array = (rolls[1] as Array)[1]
	assert_int(parry.size()).is_equal(2)
	assert_int(_line_of("Parry: Defender rolls 2 dice and cancels 1 strike hits")) \
		.override_failure_message("the battle log names Parry and the cancelled hits") \
		.is_greater_equal(0)


func test_no_parry_dice_are_drawn_at_epoch_72() -> void:
	var rolls: Array = await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Parry(1)"])
	var kinds: Array = []
	for r in rolls:
		kinds.append(str((r as Array)[0]))
	assert_bool(kinds.has("parry")) \
		.override_failure_message("epoch 72 draws no Parry dice: %s" % str(rolls)) \
		.is_false()
	assert_int(_line_of("Parry: Defender")).is_equal(-1)


func test_a_defender_without_parry_draws_no_parry_dice_at_epoch_73() -> void:
	var rolls: Array = await _strike(AiActRecorder.EPOCH_73_V36, [])
	var kinds: Array = []
	for r in rolls:
		kinds.append(str((r as Array)[0]))
	assert_bool(kinds.has("parry")) \
		.override_failure_message("a defender without Parry draws no Parry dice: %s" % str(rolls)) \
		.is_false()


func test_hit_ev_values_a_rending_six_above_a_plain_hit() -> void:
	var dctx := {"defense": 4, "tough": 1}
	var plain := {"ap": 0}
	var rending := {"ap": 0, "rending": true}
	assert_float(AiCombatMath.hit_ev(plain, false, dctx)) \
		.is_less(AiCombatMath.hit_ev(rending, true, dctx))
