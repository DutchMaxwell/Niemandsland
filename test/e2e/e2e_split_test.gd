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
	army.army_id = "split_fixture"
	army.game_system_abbrev = "gf"
	army.faction_folder = "wormhole_daemons_of_change"
	manager.armies[2] = army
	manager.api_client._army_books[army.army_id] = {"units": [{"id": "hatchlings",
		"name": "Hatchlings", "size": 3, "quality": 5, "defense": 5, "specialRules": [],
		"equipment": [{"name": "Claws", "range": 0, "attacks": 1}]}]}
	var profile := OPRApiClient.OPRUnit.new()
	profile.name = "Carrier"
	profile.size = 2
	profile.quality = 4
	profile.defense = 4
	profile.game_system = "gf"
	profile.base_size_round = 25
	profile.special_rules.assign(["Split(Hatchlings [3])"])
	return manager.create_runtime_unit({"opr_unit": profile, "faction_folder": "wormhole_daemons_of_change"},
		2, [Vector3.ZERO, Vector3(0.05, 0, 0)], "fixture")


func _spawned() -> Array:
	return _main.opr_army_manager.get_all_game_units().filter(func(u: GameUnit) -> bool:
		return str(u.unit_properties.get("origin", "")) == "split")


func _assert_split_at(anchor: Vector3, radius: float) -> void:
	var units := _spawned()
	assert_array(units).has_size(1)
	if units.is_empty():
		return
	var child := units[0] as GameUnit
	assert_int(child.get_alive_count()).is_equal(3)
	assert_int(child.get_quality()).is_equal(5)
	for model in child.get_alive_models():
		var mi := model as ModelInstance
		var distance := mi.node.global_position.distance_to(anchor)
		assert_float(distance + SoloController.model_base_radius_m(mi)).is_less_equal(6.0 * INCH + radius + 0.0001)
		assert_float(distance).is_greater_equal(radius + SoloController.model_base_radius_m(mi))
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	assert_str(text).contains("Split:")
	assert_str(text).contains("Hatchlings")


func test_split_waits_for_last_casualty_and_uses_its_table_position_once() -> void:
	var carrier := _carrier()
	await _main._solo_apply_wounds(carrier, 1)
	assert_array(_spawned()).is_empty()
	var last := carrier.get_alive_models()[0] as ModelInstance
	var anchor := last.node.global_position
	var radius := SoloController.model_base_radius_m(last)
	await _main._solo_apply_wounds(carrier, 1)
	_assert_split_at(anchor, radius)
	await _main._solo_apply_wounds(carrier, 20)
	assert_array(_spawned()).has_size(1)


func test_split_resolves_from_deadly_casualties() -> void:
	var carrier := _carrier()
	await _main._solo_apply_wounds(carrier, 1)
	var last := carrier.get_alive_models()[0] as ModelInstance
	var anchor := last.node.global_position
	var radius := SoloController.model_base_radius_m(last)
	await _main._solo_land_deadly_wounds(carrier, "Fixture", 3, 0, 1)
	_assert_split_at(anchor, radius)


func test_split_resolves_from_takedown_casualties() -> void:
	var carrier := _carrier()
	await _main._solo_apply_wounds(carrier, 1)
	var last := carrier.get_alive_models()[0] as ModelInstance
	var anchor := last.node.global_position
	var radius := SoloController.model_base_radius_m(last)
	var pick := {"unit": carrier, "index": carrier.models.find(last), "model": last}
	await _main._solo_land_takedown_wounds(carrier, "Fixture", pick, 0, 1)
	_assert_split_at(anchor, radius)


func test_split_registry_entries_expose_the_consumed_placement_limit() -> void:
	for system in ["gf", "gff", "aof", "aofr", "aofs"]:
		var faction := "wormhole_daemons_of_change" if system in ["gf", "gff"] else "rift_daemons_of_change"
		assert_bool(RulesRegistry.has_primitive(system, faction, "Split")).is_true()
		assert_int(int(RulesRegistry.param(system, faction, "Split", "place_in", 0))).is_equal(6)


func test_split_resolves_from_a_manually_picked_last_wound() -> void:
	var carrier := _carrier()
	await _main._solo_apply_wounds(carrier, 1)
	var last := carrier.get_alive_models()[0] as ModelInstance
	var anchor := last.node.global_position
	var radius := SoloController.model_base_radius_m(last)
	await _main._solo_apply_picked_wound(carrier, last, 2)
	_assert_split_at(anchor, radius)


func test_split_resolves_from_regiment_pooled_wounds() -> void:
	var carrier := _carrier()
	carrier.unit_properties.merge({"regiment_mode": true, "game_system": "aofr",
		"faction_folder": "rift_daemons_of_change"}, true)
	var regiment: Regiment = _main.opr_army_manager.form_regiment(carrier)
	assert_object(regiment).is_not_null()
	await _main._solo_apply_wounds(carrier, 1)
	assert_array(_spawned()).is_empty()
	var last := carrier.get_alive_models()[0] as ModelInstance
	var anchor := last.node.global_position
	var radius := SoloController.model_base_radius_m(last)
	await _main._solo_apply_wounds(carrier, 1)
	_assert_split_at(anchor, radius)
