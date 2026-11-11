extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-02b: the B14 strike-back gate must also skip a defender whose only melee
## weapons are already-spent Limited ones. MEL-02 filters Limited PER PROFILE, so such a group is left
## with an empty profile list while the group itself is still there. From epoch 73 that defender gets no
## strike-back, no dialog, no fatigue, and a log line. At epoch 72 the old read stays byte-exact.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SPENT_LINE := "melee weapons are all spent (Limited) — cannot strike back"

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
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One model at `x` inches carrying a single range-0 weapon, optionally Limited, with Tough(9) so the
## melee never kills a side and the dice cannot decide the assertions.
func _unit(pid: int, unit_name: String, x: float, limited: bool) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0, 0)])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	w.count = 1
	if limited:
		w.special_rules.append("Limited")
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["special_rules"] = ["Tough(9)"]
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


func _melee_profile(unit: GameUnit) -> Dictionary:
	var weapons: Array = (unit.source_data as OPRApiClient.OPRUnit).weapons
	var melee: Array = AiShooting.melee_profiles(weapons)
	return melee[0] if not melee.is_empty() else {}


## The AI charges a one-model defender whose only melee weapon is Limited; when `spent`, it is marked
## used before the charge, so the Limited filter leaves the group with no profile at all.
func _charge(epoch: int, spent: bool) -> GameUnit:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, false)
	var defender := _unit(1, "Defender", 1.0, true)
	if spent:
		_main.solo_controller.mark_limited_used(defender, _melee_profile(defender))
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	await E2EBoot.settle(get_tree())
	return defender


func test_a_spent_limited_defender_is_not_offered_a_strike_back_at_epoch_73() -> void:
	var defender: GameUnit = await _charge(AiActRecorder.EPOCH_73_V36, true)
	var text := _log_text()
	assert_str(text).contains(SPENT_LINE)
	assert_str(text).not_contains("Defender strikes with Blade")
	assert_bool(defender.is_fatigued) \
		.override_failure_message("a defender with no usable melee weapon must not tire").is_false()


## CONTROL: the same weapon before it is spent still strikes back normally (and tires).
func test_an_unspent_limited_defender_still_strikes_back_at_epoch_73() -> void:
	var defender: GameUnit = await _charge(AiActRecorder.EPOCH_73_V36, false)
	var text := _log_text()
	assert_str(text).contains("Defender strikes with Blade")
	assert_str(text).not_contains(SPENT_LINE)
	assert_bool(defender.is_fatigued) \
		.override_failure_message("a defender that struck back must tire").is_true()


## Below epoch 73 nothing changes: the old read of the group list still offers the strike-back.
func test_a_spent_limited_defender_still_strikes_back_at_epoch_72() -> void:
	var defender: GameUnit = await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true)
	var text := _log_text()
	assert_str(text).not_contains(SPENT_LINE)
	assert_bool(defender.is_fatigued) \
		.override_failure_message("epoch 72 keeps the old group-list read").is_true()
