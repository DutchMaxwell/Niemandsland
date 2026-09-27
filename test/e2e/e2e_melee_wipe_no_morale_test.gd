extends GdUnitTestSuite
## GF/AoF v3.5.1 p.10: a unit destroyed in melee loses regardless of wound tallies.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
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
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x: float, attacks: int) -> GameUnit:
	var unit := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0, 0)])
	(unit.models[0] as ModelInstance).model_index = 0
	var source := OPRApiClient.OPRUnit.new()
	if attacks > 0:
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = "Club"
		weapon.range_value = 0
		weapon.attacks = attacks
		source.weapons = [weapon]
	unit.source_type = "opr"
	unit.source_data = source
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	return unit


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_destroyed_fear_charger_loses_and_survivor_does_not_test_morale(timeout := 90000) -> void:
	_main.solo_ai_slots = {1: true, 2: true}
	var charger := _unit(2, "Fear Charger", 0.0, 0)
	charger.unit_properties["special_rules"] = ["Fear(2)"]
	charger.unit_properties["defense"] = 6
	# Two attacks can wipe the one-wound charger but cannot outscore Fear(2).
	var defender := _unit(1, "Defender", 1.0, 2)
	defender.unit_properties["quality"] = 2
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	var text := _log_text()
	assert_int(_main._solo_combined_alive(charger)).is_equal(0)
	assert_int(_main._solo_combined_alive(defender)).is_equal(1)
	assert_str(text).contains("Fear Charger loses the melee")
	assert_str(text).not_contains("Morale test: Defender")
	await E2EBoot.settle(get_tree())
