extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AIG-G2: Unwieldy and Imprecise sit on WEAPONS in the shipped lists, but
## their readers walked unit rules only, so neither ever applied. From EPOCH_73_V36 a weapon-borne
## Unwieldy makes its unit strike last on a charge and a weapon-borne Imprecise costs that weapon's
## attacks -1 to hit; epoch 72 replays today's dice. Units are built like the game builds them: a
## real OPRWeapon on a real OPRUnit, the profile through AiShooting._profile, the charge through
## _run_ai_melee on the real main scene.

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


func _weapon(weapon_rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	w.special_rules.assign(weapon_rules)
	return w


## One 1-model unit at `x` inches whose single melee weapon carries `weapon_rules`.
func _unit(pid: int, unit_name: String, x: float, weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0.0, 0.0)])
	var ws: Array[OPRApiClient.OPRWeapon] = [_weapon(weapon_rules)]
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


func _charge(epoch: int, weapon_rules: Array) -> GameUnit:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, weapon_rules)
	var defender := _unit(1, "Defender", 1.0, [])
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	return charger


func test_a_weapon_borne_unwieldy_makes_the_charger_strike_last_at_epoch_73(timeout := 90000) -> void:
	var charger: GameUnit = await _charge(AiActRecorder.EPOCH_73_V36, ["Unwieldy"])
	assert_bool(_main._solo_unit_has_unwieldy(charger)).is_true()
	assert_str(_log_text()).contains("Unwieldy: Charger strikes last on the charge")
	await E2EBoot.settle(get_tree())


func test_a_weapon_borne_unwieldy_is_inert_at_epoch_72(timeout := 90000) -> void:
	var charger: GameUnit = await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Unwieldy"])
	assert_bool(_main._solo_unit_has_unwieldy(charger)).is_false()
	assert_str(_log_text()).not_contains("Unwieldy")
	await E2EBoot.settle(get_tree())


func test_a_charger_without_unwieldy_strikes_first_at_both_epochs(timeout := 180000) -> void:
	var charger: GameUnit = await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, [])
	assert_bool(_main._solo_unit_has_unwieldy(charger)).is_false()
	await E2EBoot.settle(get_tree())
	charger = await _charge(AiActRecorder.EPOCH_73_V36, [])
	assert_bool(_main._solo_unit_has_unwieldy(charger)).is_false()
	assert_str(_log_text()).not_contains("Unwieldy")
	await E2EBoot.settle(get_tree())


## Faces [6, 5, 4, 3] at 4+: three hits. Imprecise turns the target into 5+ and leaves two.
func test_a_weapon_borne_imprecise_costs_one_to_hit_at_epoch_73(timeout := 120000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var profile: Dictionary = AiShooting._profile(_weapon(["Imprecise"]), 4, 0)
	var hits: int = await _main._solo_hits([6, 5, 4, 3], 4, profile, 0.0)
	assert_int(hits).override_failure_message("Imprecise: Quality 4+ becomes 5+, so the 4 no longer hits").is_equal(2)
	assert_str(_log_text()).contains("Imprecise: -1 to hit")


func test_a_weapon_borne_imprecise_is_inert_at_epoch_72(timeout := 120000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var profile: Dictionary = AiShooting._profile(_weapon(["Imprecise"]), 4, 0)
	var hits: int = await _main._solo_hits([6, 5, 4, 3], 4, profile, 0.0)
	assert_int(hits).is_equal(3)
	assert_str(_log_text()).not_contains("Imprecise")


## The same weapon without the rule: 3 hits at both epochs and no Imprecise line.
func test_a_weapon_without_imprecise_is_untouched_at_epoch_73(timeout := 120000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var profile: Dictionary = AiShooting._profile(_weapon([]), 4, 0)
	var hits: int = await _main._solo_hits([6, 5, 4, 3], 4, profile, 0.0)
	assert_int(hits).is_equal(3)
	assert_str(_log_text()).not_contains("Imprecise")


## End to end: an Imprecise charger's melee names the rule in the real battle log.
func test_an_imprecise_charge_names_the_rule_in_the_battle_log_at_epoch_73(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, ["Imprecise"])
	assert_str(_log_text()).contains("Imprecise: -1 to hit")
	await E2EBoot.settle(get_tree())
