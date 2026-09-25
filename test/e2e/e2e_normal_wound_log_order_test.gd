extends GdUnitTestSuite

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

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


func _index_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


func _unit(unit_name: String, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(0.2, 0.0, 0.02 * i))
	var unit := E2EBoot.make_unit(_main, 2, unit_name, positions)
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	return unit


func test_wounds_line_precedes_model_loss(timeout := 240000) -> void:
	var unit := _unit("WoundOrderPair", 2)
	await _main._solo_apply_wounds(unit, 1)
	assert_int(_index_of("WoundOrderPair takes 1 wound")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderPair loses a model")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderPair takes 1 wound")).is_less(_index_of("WoundOrderPair loses a model"))
	assert_int(unit.get_alive_count()).is_equal(1)
	await E2EBoot.settle(get_tree())


func test_wounds_line_precedes_destruction(timeout := 240000) -> void:
	var unit := _unit("WoundOrderSingle", 1)
	await _main._solo_apply_wounds(unit, 1)
	assert_int(_index_of("WoundOrderSingle takes 1 wound")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderSingle destroyed")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderSingle takes 1 wound")).is_less(_index_of("WoundOrderSingle destroyed"))
	assert_int(unit.get_alive_count()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_deadly_line_names_its_weapon(timeout := 240000) -> void:
	var unit := _unit("WoundOrderDeadly", 1)
	await _main._solo_land_deadly_wounds(unit, "Hammer", 2, 0, 1)
	assert_int(_index_of("Deadly(2): 1 unsaved ×2, no carry-over → 1 wound dealt (Hammer)")) \
		.is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_direct_wound_models_still_parks_casualties(timeout := 240000) -> void:
	var unit := _unit("WoundOrderDirect", 1)
	var remaining: int = await _main._solo_wound_models(unit, 1, 2)
	assert_int(remaining).is_equal(0)
	assert_int(_index_of("WoundOrderDirect destroyed")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())
