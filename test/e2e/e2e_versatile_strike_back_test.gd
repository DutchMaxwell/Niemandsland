extends GdUnitTestSuite
## Versatile Expert (rules 3.6): the pick lasts until the end of the unit's OWN activation, so a strike-back
## in the enemy's activation neither picks nor latches; a charge in its own activation still does.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
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
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _unit(pid: int, uname: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, uname, [Vector3(0, 0, 0), Vector3(0, 0, 0.02)])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.attacks = 4
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w] as Array[OPRApiClient.OPRWeapon]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_strike_back_in_enemy_activation_neither_picks_nor_latches() -> void:
	var u := _unit(2, "Experts", ["Versatile Expert"])
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(2)
	await _main._solo_melee_strike_phase(u, _unit(1, "Chargers", []), false, 0, 0.0)
	assert_str(_log_text()).not_contains(" picks ")
	assert_bool(_main._solo_versatile_latch_read(u).is_empty()).is_true()


func test_charge_in_own_activation_still_picks_and_latches() -> void:
	var u := _unit(1, "Experts", ["Versatile Expert"])
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(2)
	await _main._solo_melee_strike_phase(u, _unit(2, "Anvils", []), true, 0, 3.0)
	assert_str(_log_text()).contains(" picks ")
	assert_bool(_main._solo_versatile_latch_read(u).is_empty()).is_false()
