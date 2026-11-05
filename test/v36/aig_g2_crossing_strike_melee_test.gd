extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AIG-G2 row R3: a Crossing Strike weapon attacks only when its bearer moves
## through an enemy unit. The shooting list already filtered it, but the melee list did not, so a
## range-0 Crossing Strike weapon (Zeppelins' Drop Bombs) struck as plain melee. From EPOCH_73_V36 the
## melee list leaves it out and the strike names the book rule; epoch 72 replays today's dice. Twin of
## core/nml-core/src/tests/unit/v36_data_rows/aig_g2_r3.rs. Units are built like the game builds them: a
## real OPRWeapon on a real OPRUnit, the strike through _run_ai_melee on the real main scene.

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


func _weapon(weapon_name: String, weapon_rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = 0
	w.attacks = 4
	w.special_rules.assign(weapon_rules)
	return w


func _names(profiles: Array) -> Array:
	var out: Array = []
	for p in profiles:
		out.append(str((p as Dictionary).get("name", "")))
	return out


## One 1-model unit at `x` inches carrying one range-0 weapon per [name, rules] pair.
func _unit(pid: int, unit_name: String, x: float, loadout: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0.0, 0.0)])
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for pair in loadout:
		ws.append(_weapon(str(pair[0]), pair[1] as Array))
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = ws
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


func _charge(epoch: int, loadout: Array) -> void:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Zeppelins", 0.0, loadout)
	var defender := _unit(1, "Defender", 1.0, [])
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})


func test_the_melee_list_leaves_a_crossing_strike_weapon_out_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bombs := _weapon("Drop Bombs", ["Crossing Strike"])
	assert_array(AiShooting.melee_profiles([bombs])) \
		.override_failure_message("a Crossing Strike weapon struck as plain melee").is_empty()
	assert_array(AiShooting.melee_profiles([_weapon("Drop Bombs", ["Strafing"])])) \
		.override_failure_message("the 3.5 name is the same rule").is_empty()
	assert_int(AiShooting.strafing_profiles([bombs]).size()) \
		.override_failure_message("the weapon stays in the move-through set").is_equal(1)


func test_the_melee_list_keeps_a_crossing_strike_weapon_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_array(_names(AiShooting.melee_profiles([_weapon("Drop Bombs", ["Crossing Strike"])]))) \
		.is_equal(["Drop Bombs"])


## Control: a plain range-0 weapon beside it keeps striking, so the filter is the rule and not "range 0".
func test_a_plain_weapon_beside_it_keeps_striking_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var weapons: Array = [_weapon("Drop Bombs", ["Crossing Strike"]), _weapon("Gondola Crew", [])]
	assert_array(_names(AiShooting.melee_profiles(weapons))).is_equal(["Gondola Crew"])


func test_a_melee_strike_leaves_the_crossing_strike_weapon_out_and_names_the_rule_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, [["Drop Bombs", ["Crossing Strike"]], ["Gondola Crew", []]])
	assert_str(_log_text()).not_contains("strikes with Drop Bombs")
	assert_str(_log_text()).contains("strikes with Gondola Crew")
	assert_str(_log_text()).contains("Crossing Strike: Drop Bombs attacks only when Zeppelins moves through an enemy unit")
	await E2EBoot.settle(get_tree())


func test_a_melee_strike_is_untouched_at_epoch_72(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, [["Drop Bombs", ["Crossing Strike"]], ["Gondola Crew", []]])
	assert_str(_log_text()).contains("strikes with Drop Bombs")
	assert_str(_log_text()).not_contains("Crossing Strike:")
	await E2EBoot.settle(get_tree())


func test_a_unit_without_the_rule_logs_no_crossing_strike_line_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, [["Gondola Crew", []]])
	assert_str(_log_text()).contains("strikes with Gondola Crew")
	assert_str(_log_text()).not_contains("Crossing Strike")
	await E2EBoot.settle(get_tree())
