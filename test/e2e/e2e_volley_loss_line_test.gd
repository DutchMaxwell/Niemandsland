extends GdUnitTestSuite
## E2E: a volley that kills several models of a surviving unit writes ONE loss line for it ("X loses 4
## models (1/5)"), not one identical "X loses a model (1/5)" per casualty (the 06.11. solo games printed
## "War Furies loses a model (1/10)" nine times after one volley). A single casualty keeps the singular line.

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


func _lines(prefix: String) -> Array:
	return _main.battle_log.entries().map(func(e: Dictionary) -> String: return str(e["text"])) \
		.filter(func(t: String) -> bool: return t.begins_with(prefix))


func _unit(pid: int, unit_name: String, models: int) -> GameUnit:
	var positions: Array = range(models).map(func(i: int) -> Vector3: return Vector3(8.0 * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## What a volley leaves behind: the first `count` models dead, none parked yet; parking writes the log.
func _volley(u: GameUnit, count: int) -> void:
	var died: Array[ModelInstance] = []
	for m in u.models:
		if died.size() < count and (m as ModelInstance).is_alive:
			(m as ModelInstance).is_alive = false
			died.append(m as ModelInstance)
	await _main._solo_remove_dead_models(u, died, int(u.unit_properties["player_id"]))


func test_a_volley_that_kills_four_models_writes_one_line(timeout := 240000) -> void:
	await _volley(_unit(2, "Furies", 5), 4)
	assert_array(_lines("Furies loses")).is_equal(["Furies loses 4 models (1/5)"])
	await E2EBoot.settle(get_tree())


## Counter-check: one casualty keeps the singular line, word for word.
func test_one_casualty_keeps_the_singular_line(timeout := 240000) -> void:
	await _volley(_unit(2, "Hounds", 5), 1)
	assert_array(_lines("Hounds loses")).is_equal(["Hounds loses a model (4/5)"])
	await E2EBoot.settle(get_tree())


## Counter-check: the count is per volley, not per unit for the whole game (two volleys, two lines).
func test_two_volleys_write_two_lines(timeout := 240000) -> void:
	var u := _unit(2, "Raiders", 6)
	await _volley(u, 2)
	await _volley(u, 1)
	assert_array(_lines("Raiders loses")).is_equal(["Raiders loses 2 models (4/6)", "Raiders loses a model (3/6)"])
	await E2EBoot.settle(get_tree())


## Counter-check: a casualty parked by hand (the radial menu, no volley) is written at once, not held back.
func test_a_hand_parked_casualty_is_written_at_once(timeout := 240000) -> void:
	var u := _unit(2, "Walkers", 3)
	(u.models[0] as ModelInstance).is_alive = false
	_main.opr_army_manager.set_loose_model_dead((u.models[0] as ModelInstance).node, 2, true, u.unit_id)
	assert_array(_lines("Walkers loses")).is_equal(["Walkers loses a model (2/3)"])
	await E2EBoot.settle(get_tree())


## Counter-check: each unit keeps its own line (even across sides), and a wipe-out stays "destroyed", never "loses".
func test_each_unit_gets_its_own_line_and_a_wipe_out_stays_destroyed(timeout := 240000) -> void:
	await _volley(_unit(2, "Left", 4), 3)
	await _volley(_unit(1, "Right", 4), 2)
	await _volley(_unit(2, "Gone", 3), 3)
	assert_array(_lines("Left loses")).is_equal(["Left loses 3 models (1/4)"])
	assert_array(_lines("Right loses")).is_equal(["Right loses 2 models (2/4)"])
	assert_array(_lines("Gone")).is_equal(["Gone destroyed"])
	await E2EBoot.settle(get_tree())
