extends GdUnitTestSuite

## Grounded Protection (aof volcanic_dwarves / wood_elves — registry
## `Regeneration | ignore_target=5, all_models=true, terrain_within_in=1`):
## the table's Regeneration walk (`_solo_regen_pick`) must answer the
## "within 1 inch of terrain" condition the same majority-in-cover read the
## Shielded twin answers (main.gd:5588). In the open the protection is simply
## not there — every wound lands and the trace names the verdict
## (rules-must-log); within terrain the 5+ rolls.

const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _model_nodes: Array


func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_model_nodes = []
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	_free_model_nodes()
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## The orphan monitor samples at TEST end (before after_test), so the stand-in
## model nodes are freed inside each test, not in the teardown.
func _free_model_nodes() -> void:
	for n in _model_nodes:
		if is_instance_valid(n):
			n.free()
	_model_nodes = []


## The stand-in overlay: every probe answers FOREST (cover terrain —
## TerrainRules.gives_cover), so the majority read sees all models in cover.
class FakeOverlay extends Node3D:
	func get_terrain_at_world_position(_p: Vector3) -> int:
		return TerrainRules.TerrainType.FOREST


func _unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "grounded_prot"
	u.unit_properties = {"player_id": 2, "name": "Hammer Guard", "quality": 3, "defense": 3,
		"special_rules": ["Grounded Protection"], "game_system": "aof",
		"faction_folder": "volcanic_dwarves"}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func _unit_with_node() -> GameUnit:
	var u := _unit()
	var node := Node3D.new()
	_model_nodes.append(node)
	u.models[0].node = node
	return u


func _log_since(start: int) -> String:
	var text := ""
	for entry in _main.battle_log.entries().slice(start):
		text += str(entry["text"]) + "\n"
	return text


func test_grounded_protection_in_the_open_ignores_nothing_and_names_the_verdict() -> void:
	var unit := _unit()   # no model node: the open verdict never reaches the board
	_main.seed_tray_rng(1300)
	var start: int = _main.battle_log.entries().size()
	var landed: int = await _main._solo_apply_regeneration(unit, 20, false)
	assert_int(landed) \
		.override_failure_message("in the open the protection must ignore nothing (the flat 5+ fold fired)") \
		.is_equal(20)
	_free_model_nodes()
	var text := _log_since(start)
	assert_str(text).contains("Grounded Protection") \
		.override_failure_message("rules-must-log: the refusal names the rule")
	assert_str(text).contains("in the open -> no Regeneration") \
		.override_failure_message("rules-must-log: the verdict is traced")


func test_grounded_protection_within_terrain_rolls_the_5_plus() -> void:
	var unit := _unit_with_node()
	var fake := FakeOverlay.new()
	_main.terrain_overlay = fake
	_main.seed_tray_rng(1300)
	var start: int = _main.battle_log.entries().size()
	var landed: int = await _main._solo_apply_regeneration(unit, 20, false)
	_main.terrain_overlay = null
	fake.free()
	assert_int(landed) \
		.override_failure_message("within terrain the 5+ must ignore some wounds") \
		.is_less(20)
	_free_model_nodes()
	var text := _log_since(start)
	assert_str(text).contains("within 1\" of terrain") \
		.override_failure_message("rules-must-log: the verdict is traced with the rule's own proximity")
	assert_str(text).contains("Regeneration 5+") \
		.override_failure_message("rules-must-log: the trace names the folded target")
