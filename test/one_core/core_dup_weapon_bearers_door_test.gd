extends GdUnitTestSuite
## T-DUP-WEAPON-BEARERS on the AI door (OD-2 of PLAN_D_DELETE_NOW): a unit that lists one weapon twice (the Jesters' "Atom Pistol"
## x8 plain and x2 AP(1): one pistol per model, two entries because the profiles differ) fires ONE die per sighted bearer in
## total. GF Advanced Rules v3.5.1 "Shooting, 1. Determine Attacks": the unit's attacks are the Attack values of the weapons of the
## models that can shoot at the target, so 8 sighted pistols roll 8 dice, not 16. The core has done so since EPOCH_89_SHARED_BEARERS
## (the by-name count, 8 + 8 dice, replays below it). Real: the main scene, NmlCore, the AI body's volley call (`_run_ai_shooting`)
## on a captured board. The dice are the attack lines of the battle log ("AI (Jesters): 6 4 4 -> ..."), one per entry.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 3

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 1)   # both seats AI: saves auto-resolve, no dialog
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)
	CoreActivation._env = 1


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _pistol(copies: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Atom Pistol"
	w.range_value = 12
	w.attacks = 1
	w.count = copies
	w.special_rules.assign(rules)
	return w


func _opr(weapons: Array) -> OPRApiClient.OPRUnit:
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign(weapons)
	return src


## Ten Jesters (one pistol in each per-model loadout, two entries of the weapon), `near` of them 5" from a three-model squad and
## the rest 30" behind: only `near` models are in range and sight. One AI volley through the door; returns the dice rolled per
## attack line (one line per entry that fired).
func _volley(epoch: int, near: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var positions: Array = []
	for i in 10:
		positions.append(Vector3((-5.0 if i < near else -30.0) * INCH, 0, 0.02 * i))
	var jesters := E2EBoot.make_unit(_main, 2, "Jesters", positions)
	for i in jesters.models.size():
		var mi := jesters.models[i] as ModelInstance
		mi.model_index = i
		mi.properties["weapons"] = [{"name": "Atom Pistol", "attacks": 1}]
	jesters.source_type = "opr"
	jesters.source_data = _opr([_pistol(8, []), _pistol(2, ["AP(1)"])])
	jesters.unit_properties.merge({"quality": 2, "game_system": "gf", "special_rules": []}, true)
	var squad := E2EBoot.make_unit(_main, 1, "Test Scouts", [Vector3.ZERO, Vector3(0, 0, 0.02), Vector3(0, 0, 0.04)])
	squad.unit_properties.merge({"quality": 4, "defense": 6, "game_system": "gf", "special_rules": []}, true)
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 24
	rifle.attacks = 1
	rifle.count = 3
	squad.source_type = "opr"
	squad.source_data = _opr([rifle])   # a plain target carries a profile
	for u in [jesters, squad]:
		_main.opr_army_manager.game_units[(u as GameUnit).unit_id] = u
	_main.seed_tray_rng(SEED)
	CoreActivation.ai_runs = 0
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting({"unit": jesters, "moved": false, "action": AiDecision.Action.HOLD})
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	var dice: Array = []
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.begins_with("AI (Jesters): "):
			dice.append(t.get_slice(" → ", 0).trim_prefix("AI (Jesters): ").split(" ", false).size())
	await E2EBoot.settle(get_tree())
	return dice


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The parity act's shape: 8 of the 10 models sighted. The eight pistols fire once, in the first entry; the second has no bearer
## left and says so. RED: below the epoch the same volley rolls 8 + 8 (the last test); a board left uncaptured makes the table shoot
## and fails the first assertion.
func test_entries_of_one_weapon_share_the_sighted_bearers(timeout := 120000) -> void:
	var dice := await _volley(AiActRecorder.rules_epoch, 8)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot)").is_equal(1)
	assert_array(dice).override_failure_message("8 sighted pistols roll 8 dice in one entry, got %s" % [dice]).is_equal([8])
	assert_str(_log_text()).override_failure_message("rules-must-log: the silent entry says why").contains("Atom Pistol silent")


## All ten models sighted: each entry fires its own copies, 8 + 2.
func test_every_pistol_fires_once_when_all_ten_are_sighted(timeout := 120000) -> void:
	var dice := await _volley(AiActRecorder.rules_epoch, 10)
	assert_int(CoreActivation.ai_runs).is_equal(1)
	assert_array(dice).override_failure_message("10 pistols roll 8 + 2 dice, got %s" % [dice]).is_equal([8, 2])


## Below EPOCH_89_SHARED_BEARERS a recorded game replays the by-name count: both entries read all bearers, 8 + 8.
func test_epoch_88_replays_the_by_name_count(timeout := 120000) -> void:
	var dice := await _volley(88, 8)
	assert_int(CoreActivation.ai_runs).is_equal(1)
	assert_array(dice).override_failure_message("EPOCH_88 keeps the by-name count, got %s" % [dice]).is_equal([8, 8])
