extends GdUnitTestSuite
## A joined hero may take the host's morale test on its better Quality (GF p.14).

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


func _joined_unit(host_alive: bool) -> GameUnit:
	var host := Boot.make_unit(_main, 2, "Squad", [Vector3.ZERO])
	host.unit_properties["quality"] = 5
	var hero := Boot.make_unit(_main, 2, "Captain", [Vector3(0.0254, 0, 0)])
	hero.unit_properties["quality"] = 3
	hero.unit_properties["special_rules"] = ["Hero"]
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	(host.models[0] as ModelInstance).is_alive = host_alive
	return host


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func test_living_hero_tests_for_dead_host_on_quality_three() -> void:
	var host := _joined_unit(false)
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(host, "AI (Squad)")
	assert_str(_log_text()).contains("Hero Captain tests on behalf of Squad (Q3+)")
	assert_str(_log_text()).contains("1 hit (3+)")


func test_better_living_hero_tests_for_living_host_on_quality_three() -> void:
	var host := _joined_unit(true)
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(host, "AI (Squad)")
	assert_str(_log_text()).contains("Hero Captain tests on behalf of Squad (Q3+)")
	assert_str(_log_text()).contains("1 hit (3+)")


func test_dead_hero_cannot_supply_quality_to_living_host() -> void:
	var host := _joined_unit(true)
	var hero := host.get_attached_heroes()[0] as GameUnit
	(hero.models[0] as ModelInstance).is_alive = false
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(host, "AI (Squad)")
	assert_str(_log_text()).not_contains("Hero Captain tests on behalf")
	assert_str(_log_text()).contains("1 hit (5+)")
