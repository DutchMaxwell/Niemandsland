extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
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


func _carrier() -> GameUnit:
	var manager: OPRArmyManager = _main.opr_army_manager
	var army := OPRApiClient.OPRArmy.new()
	army.army_id = "spawn_fixture"
	army.game_system_abbrev = "gf"
	army.faction_folder = "alien_hives"
	manager.armies[2] = army
	manager.api_client._army_books[army.army_id] = {"units": [{"id": "hatchlings",
		"name": "Hatchlings", "size": 3, "quality": 5, "defense": 5, "specialRules": [],
		"equipment": [{"name": "Claws", "range": 0, "attacks": 1}]}]}
	var profile := OPRApiClient.OPRUnit.new()
	profile.name = "Carrier"
	profile.size = 1
	profile.quality = 4
	profile.defense = 4
	profile.game_system = "gf"
	profile.base_size_round = 25
	profile.special_rules.assign(["Spawn(Hatchlings [3])"])
	return manager.create_runtime_unit({"opr_unit": profile, "faction_folder": "alien_hives"},
		2, [Vector3.ZERO], "fixture")


func _spawned() -> Array:
	return _main.opr_army_manager.get_all_game_units().filter(func(u: GameUnit) -> bool:
		return str(u.unit_properties.get("origin", "")) == "spawn")


func test_spawn_activation_builds_the_book_profile_once_with_legal_bases_and_named_log() -> void:
	var carrier := _carrier()
	assert_object(carrier).is_not_null()
	await _main._solo_try_reanimation(carrier)
	var units := _spawned()
	assert_array(units).has_size(1)
	if units.is_empty():
		return
	var spawned := units[0] as GameUnit
	assert_int(spawned.get_alive_count()).is_equal(3)
	assert_int(spawned.get_quality()).is_equal(5)
	assert_bool(spawned.is_activated).is_false()
	var bearer := carrier.models[0] as ModelInstance
	for model in spawned.get_alive_models():
		var mi := model as ModelInstance
		assert_float(mi.node.global_position.distance_to(bearer.node.global_position)
			+ SoloController.model_base_radius_m(mi)) \
			.is_less_equal(6.0 * INCH + SoloController.model_base_radius_m(bearer) + 0.0001)
		assert_float(mi.node.global_position.distance_to(bearer.node.global_position)) \
			.is_greater_equal(SoloController.model_base_radius_m(mi) + SoloController.model_base_radius_m(bearer))
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	assert_str(text).contains("Spawn:")
	assert_str(text).contains("Hatchlings")
	await _main._solo_try_reanimation(carrier)
	_main.opr_army_manager.current_round += 1
	await _main._solo_try_reanimation(carrier)
	assert_array(_spawned()).has_size(1)


func test_spawn_registry_entries_expose_the_consumed_placement_and_use_limits() -> void:
	var contexts := {"gf": ["alien_hives", "ratmen_clans", "robot_legions", "wormhole_daemons_of_lust"],
		"gff": ["wormhole_daemons_of_lust"],
		"aof": ["dwarves", "rift_daemons_of_lust", "saurians", "vampiric_undead", "wood_elves"],
		"aofr": ["dwarves", "rift_daemons_of_lust", "saurians", "vampiric_undead", "wood_elves"],
		"aofs": ["rift_daemons_of_lust"]}
	for system in contexts:
		for faction in contexts[system]:
			assert_bool(RulesRegistry.has_primitive(system, faction, "Spawn")).is_true()
			assert_int(int(RulesRegistry.param(system, faction, "Spawn", "place_in", 0))).is_equal(6)
			assert_bool(bool(RulesRegistry.param(system, faction, "Spawn", "once_per_game", false))).is_true()


func test_spawn_uses_the_bearer_model_rule_without_a_unit_wide_grant() -> void:
	var carrier := _carrier()
	carrier.unit_properties["special_rules"] = []
	await _main._solo_try_reanimation(carrier)
	assert_array(_spawned()).has_size(1)
