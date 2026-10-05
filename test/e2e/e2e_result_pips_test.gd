extends GdUnitTestSuite
## E2E — VFX #1 result pips ride the REAL wound allocation in main.gd (_solo_apply_wounds ->
## _solo_wound_models callbacks): a casualty gets a blood marker, a surviving Tough model gets one tick per
## wound that landed in THIS batch, and a rout wipe (no wound, the unit just leaves) shows nothing.
## The marks read the allocation; they must never change it.

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
	_main.result_pips.force_for_tests = true   # headless spawns nothing unless a test opts in
	_main.result_pips.enabled = true           # the player setting defaults to off


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(unit_name: String, models: int, wounds: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(8.0 * INCH, 0.0, 0.03 * i))
	var u := E2EBoot.make_unit(_main, 2, unit_name, positions)
	for m in u.models:
		(m as ModelInstance).wounds_max = wounds
		(m as ModelInstance).wounds_current = wounds
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _pips(shape: int) -> Array:
	var out: Array = []
	for c in _main.result_pips.get_children():
		if int(((c as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("shape")) == shape:
			out.append(c)
	return out


func test_casualties_get_a_marker_each(timeout := 240000) -> void:
	var target := _unit("Grunts", 5, 1)
	await _main._solo_apply_wounds(target, 2)
	assert_int(target.get_alive_count()).override_failure_message("fixture: two models must die").is_equal(3)
	assert_int(_pips(ResultPips.Kind.KILL).size()).is_equal(2)
	assert_int(_pips(ResultPips.Kind.WOUND).size()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_tough_model_ticks_only_this_batch(timeout := 240000) -> void:
	var target := _unit("Ogre", 1, 6)
	await _main._solo_apply_wounds(target, 2)
	await _main._solo_apply_wounds(target, 1)
	var ticks := _pips(ResultPips.Kind.WOUND)
	assert_int(ticks.size()).is_equal(2)
	var counts: Array = ticks.map(func(c): return int((c.material_override as ShaderMaterial).get_shader_parameter("count")))
	assert_array(counts).contains_exactly([2, 1])
	assert_int(int(target.models[0].wounds_current)).override_failure_message("the marks must not change the allocation").is_equal(3)
	await E2EBoot.settle(get_tree())


func test_a_rout_wipe_shows_no_wound_marks(timeout := 240000) -> void:
	var target := _unit("Runners", 4, 1)
	await _main._solo_apply_wounds(target, 48, false)
	assert_int(target.get_alive_count()).override_failure_message("fixture: the wipe must remove the unit").is_equal(0)
	assert_int(_main.result_pips.get_child_count()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_hits_and_saves_sit_over_the_unit(timeout := 240000) -> void:
	var striker := _unit("Rifles", 1, 1)
	var target := _unit("Grunts", 5, 1)
	_main.seed_tray_rng(31337)
	var w: int = await _main._solo_resolve_saves(striker, target, "Rifle", [], 6, 4, {"ap": 0}, false, false)
	var hits := _pips(ResultPips.Kind.HIT)
	var saves := _pips(ResultPips.Kind.SAVE)
	assert_int(hits.size()).is_equal(1)
	assert_int(int((hits[0].material_override as ShaderMaterial).get_shader_parameter("count"))).is_equal(6)
	assert_int(w).override_failure_message("fixture: some saves must fail and some hold").is_between(1, 5)
	assert_int(int((saves[0].material_override as ShaderMaterial).get_shader_parameter("count"))).is_equal(6 - w)
	var c: Vector3 = _main.solo_controller.unit_centre(target)
	assert_float(Vector2(hits[0].global_position.x, hits[0].global_position.z).distance_to(Vector2(c.x, c.z))).is_less(0.001)
	await E2EBoot.settle(get_tree())
