extends GdUnitTestSuite
## GF/AoF p.13: Fearless recovery requires the rule on every living model.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array


func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(unit_name: String, rules: Array) -> GameUnit:
	var unit := Boot.make_unit(_main, 2, unit_name, [Vector3.ZERO])
	unit.unit_properties["quality"] = 4
	unit.unit_properties["special_rules"] = rules
	return unit


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func test_fearless_squad_with_plain_hero_has_no_recovery_die() -> void:
	var squad := _unit("Squad", ["Fearless"])
	var hero := _unit("Captain", ["Hero"])
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	assert_bool(bool(AiEv.ctx_for(squad)["fearless"])).is_false()
	assert_bool(BattleSim._morale_fails_expected({"unit": squad, "shaken": false})).is_true()
	squad.is_shaken = true
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(squad, "AI (Squad)")
	assert_str(_log_text()).not_contains("Squad is Fearless — recovery die")


func test_lone_fearless_hero_gets_recovery_die() -> void:
	var hero := _unit("Captain", ["Hero", "Fearless"])
	assert_bool(bool(AiEv.ctx_for(hero)["fearless"])).is_true()
	assert_bool(BattleSim._morale_fails_expected({"unit": hero, "shaken": false})).is_false()
	hero.is_shaken = true
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(hero, "AI (Captain)")
	assert_str(_log_text()).contains("Captain is Fearless — recovery die")
