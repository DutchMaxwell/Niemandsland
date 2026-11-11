extends GdUnitTestSuite
## Rules 3.6, maintainer ruling: Parry only reduces the hits of ordinary melee attacks. The Impact dice a
## charge rolls are not parried, so no Parry die is drawn for them. The sanity case runs a real strike
## into the same defenders to prove the roll-kind reader does see a Parry die when one is rolled.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 7

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
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


## `models` models at `x` inches with one melee weapon; Tough(9) keeps every model alive.
func _unit(pid: int, unit_name: String, x: float, models: int, rules: Array, attacks: int) -> GameUnit:
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
	u.unit_properties["defense"] = 4
	u.unit_properties["quality"] = 2
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The roll kinds the table drew, in order.
func _kinds() -> Array:
	var kinds: Array = []
	for rec in _main.solo_controller.decision_log:
		if str((rec as Dictionary).get("kind", "")) == "dice":
			kinds.append(str(rec["roll_kind"]))
	return kinds


func test_an_impact_charge_into_parry_defenders_draws_no_parry_die() -> void:
	var charger := _unit(1, "Charger", 0.0, 1, ["Impact(3)"], 5)
	var defender := _unit(2, "Defender", 0.5, 2, ["Parry(1)"], 1)
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._solo_charge_impact(charger, defender, false, 0.0)
	var kinds := _kinds()
	assert_str(str(kinds)).override_failure_message(
		"Impact is rolled, then saved; no Parry die between them: %s" % str(kinds)).is_equal(str(["attack", "defense"]))
	await E2EBoot.settle(get_tree())


## CONTROL (passes with and without the change): an ordinary strike into the same defenders IS parried.
func test_a_plain_strike_into_the_same_defenders_still_draws_a_parry_die() -> void:
	var attacker := _unit(1, "Charger", 0.0, 1, [], 5)
	var defender := _unit(2, "Defender", 0.5, 2, ["Parry(1)"], 1)
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._solo_melee_strike_phase(attacker, defender, true, 0)   # 0 = SoloStrike.ALL
	var kinds := _kinds()
	assert_bool(kinds.has("parry")).override_failure_message(
		"a strike must still draw its Parry die: %s" % str(kinds)).is_true()
	await E2EBoot.settle(get_tree())
