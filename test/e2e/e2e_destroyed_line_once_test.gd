extends GdUnitTestSuite
## E2E: a unit that dies in ONE volley is announced destroyed ONCE (it used to be once per casualty:
## the 06.11. solo games printed "Blood Hounds destroyed" five times for one unit).

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


func _count(line: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == line).size()


func _unit(pid: int, unit_name: String, models: int) -> GameUnit:
	var positions: Array = range(models).map(func(i: int) -> Vector3: return Vector3(8.0 * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## What a volley leaves behind: every wound applied (all models dead), none parked yet; parking writes the log.
func _wipe(u: GameUnit) -> void:
	var died: Array[ModelInstance] = []
	for m in u.models:
		(m as ModelInstance).is_alive = false
		died.append(m as ModelInstance)
	await _main._solo_remove_dead_models(u, died, int(u.unit_properties["player_id"]))


func test_a_unit_wiped_out_in_one_volley_is_announced_destroyed_once(timeout := 240000) -> void:
	await _wipe(_unit(2, "Hounds", 5))
	assert_int(_count("Hounds destroyed")).is_equal(1)
	await E2EBoot.settle(get_tree())


## Counter-check: two units sharing a name each keep their own line (a name-keyed guard would eat one).
func test_two_same_named_units_are_each_announced(timeout := 240000) -> void:
	await _wipe(_unit(1, "Twins", 1))
	await _wipe(_unit(2, "Twins", 1))
	assert_int(_count("Twins destroyed")).is_equal(2)
	await E2EBoot.settle(get_tree())


## Counter-check: a unit that returns and falls again is announced again.
func test_a_unit_that_returns_and_falls_again_is_announced_again(timeout := 240000) -> void:
	var u := _unit(2, "Phoenix", 1)
	await _wipe(u)
	(u.models[0] as ModelInstance).is_alive = true
	_main.opr_army_manager.set_loose_model_dead((u.models[0] as ModelInstance).node, 2, false)
	await _wipe(u)
	assert_int(_count("Phoenix destroyed")).is_equal(2)
	await E2EBoot.settle(get_tree())
