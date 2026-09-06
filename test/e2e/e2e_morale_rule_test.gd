extends GdUnitTestSuite

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


func _unit(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "morale_fixture"
	u.unit_properties = {"player_id": 2, "quality": 4, "defense": 4, "name": "Fixture",
		"special_rules": rules, "game_system": "gf"}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func test_morale_rating_reaches_the_shared_ai_and_dice_bonus() -> void:
	var unit := _unit(["Morale(2)"])
	assert_int(SoloController.morale_bonus_of(unit)).is_equal(2)
	unit.unit_properties["special_rules"] = ["Morale(2)", "Banner"]
	assert_int(SoloController.morale_bonus_of(unit)).is_equal(3)
	var hero := _unit(["Morale(3)"])
	unit.unit_properties["attached_heroes"] = [hero]
	assert_int(SoloController.morale_bonus_of(unit)).is_equal(4)


func test_morale_changes_the_actual_test_outcome_and_names_the_bonus() -> void:
	var unit := _unit(["Morale(2)"])
	var rng := RandomNumberGenerator.new()
	var chosen_seed := -1
	for candidate in range(100):
		rng.seed = candidate
		if rng.randi_range(1, 6) == 2:
			chosen_seed = candidate
			break
	assert_int(chosen_seed).is_greater_equal(0)
	_main.seed_tray_rng(chosen_seed)
	await _main._solo_morale_test(unit, "Fixture")
	assert_bool(unit.is_shaken).is_false()
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	assert_str(text).contains("Morale(2):")
	assert_str(text).contains("passes on 2+")


func test_morale_registry_maps_the_existing_rating_encoding_in_every_system() -> void:
	for system in ["gf", "gff", "aof", "aofr", "aofs"]:
		assert_bool(RulesRegistry.has_primitive(system, "", "Morale")).is_true()
		assert_str(str(RulesRegistry.param(system, "", "Morale", "rating", ""))).is_equal("X")
