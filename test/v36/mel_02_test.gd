extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-02: the AI's melee estimates already read the Assault melee copy (pinned here),
## Limited is one use per game across shooting and melee, and the battle log says how many models are in
## strike reach and when a Limited weapon is used up in melee. The reach is 3" from epoch 73, 2" below.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 902

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
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _pistol(limited: bool) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Assault Pistol"
	w.range_value = 12
	w.attacks = 2
	w.count = 1
	w.special_rules.append("Assault")
	if limited:
		w.special_rules.append("Limited")
	return w


func _ccw() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Claw"
	w.range_value = 0
	w.attacks = 4
	w.count = 1
	return w


## A one-model-per-spot unit of player 1 carrying exactly `weapons`.
func _unit(spots: Array, weapons: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Pistols", spots)
	var typed: Array[OPRApiClient.OPRWeapon] = []
	for w in weapons:
		typed.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = typed
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A ten-model AI target on a short line, all of it in reach of a model at the origin.
func _foe() -> GameUnit:
	var spots: Array = []
	for i in 10:
		spots.append(Vector3(0.04, 0, (float(i) - 4.5) * 0.3 * INCH))
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", spots)
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


## One strike-back (no charge) at `epoch` on tray seed 902; returns the battle log as one text.
func _strike(epoch: int, striker: GameUnit, foe: GameUnit) -> String:
	AiActRecorder.rules_epoch = epoch
	_main.seed_tray_rng(SEED)
	_main.battle_log.clear()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	await E2EBoot.settle(get_tree())
	return text


func _melee_profile(unit: GameUnit) -> Dictionary:
	var weapons: Array = (unit.source_data as OPRApiClient.OPRUnit).weapons
	var melee: Array = AiShooting.melee_profiles(weapons)
	return melee[0] if not melee.is_empty() else {}


func test_an_unused_limited_assault_weapon_is_spent_by_its_first_melee_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var striker := _unit([Vector3.ZERO], [_pistol(true)])
	var foe := _foe()
	var profile := _melee_profile(striker)
	assert_bool(profile.is_empty()).override_failure_message("no melee copy at 73").is_false()
	var log := await _strike(AiActRecorder.EPOCH_73_V36, striker, foe)
	assert_bool(_main.solo_controller.is_limited_used(striker, profile)) \
		.override_failure_message("the first melee must spend the Limited Assault weapon").is_true()
	assert_str(log).contains("Assault Pistol (Limited) is used up in melee")


func test_a_limited_assault_weapon_is_still_available_at_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var striker := _unit([Vector3.ZERO], [_pistol(true)])
	var foe := _foe()
	assert_array(_main._solo_attack_groups(striker, 0.0, true, foe)).is_empty()
	assert_bool(_main.solo_controller.is_limited_used(striker, {"name": "Assault Pistol"})).is_false()


func test_a_limited_assault_weapon_spent_by_shooting_does_not_strike_in_melee_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var striker := _unit([Vector3.ZERO], [_pistol(true)])
	var foe := _foe()
	_main.solo_controller.mark_limited_used(striker, _melee_profile(striker))
	var log := await _strike(AiActRecorder.EPOCH_73_V36, striker, foe)
	assert_str(log).not_contains("Assault Pistol")


## CONTROL: a non-Limited Assault weapon is never spent, so it strikes in every melee.
func test_a_non_limited_assault_weapon_strikes_in_every_melee_at_73() -> void:
	var striker := _unit([Vector3.ZERO], [_pistol(false)])
	var foe := _foe()
	var first := await _strike(AiActRecorder.EPOCH_73_V36, striker, foe)
	var second := await _strike(AiActRecorder.EPOCH_73_V36, striker, foe)
	assert_str(first).contains("Assault Pistol also strikes in melee")
	assert_str(second).contains("Assault Pistol also strikes in melee")
	assert_bool(_main.solo_controller.is_limited_used(striker, _melee_profile(striker))).is_false()


## The strike log names the models in reach when fewer strike than are alive (3" at 73).
func test_the_strike_log_names_the_models_in_reach_at_73() -> void:
	var striker := _unit([Vector3.ZERO, Vector3(20 * INCH, 0, 0), Vector3(20 * INCH, 0, 0.2 * INCH)],
		[_pistol(false)])
	var foe := _foe()
	var log := await _strike(AiActRecorder.EPOCH_73_V36, striker, foe)
	assert_str(log).contains("Pistols: 1 of 3 models are within 3\" and strike")


## Below 73 the same line reads the old 2" reach.
func test_the_strike_log_names_the_models_in_reach_at_72() -> void:
	var striker := _unit([Vector3.ZERO, Vector3(20 * INCH, 0, 0), Vector3(20 * INCH, 0, 0.2 * INCH)],
		[_ccw()])
	var foe := _foe()
	var log := await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, striker, foe)
	assert_str(log).contains("Pistols: 1 of 3 models are within 2\" and strike")
