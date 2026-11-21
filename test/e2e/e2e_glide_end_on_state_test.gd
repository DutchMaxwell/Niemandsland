extends GdUnitTestSuite
## E2E — where a gliding AI model comes to rest. The placement gate leaves each model on a legal spot (`new_positions`), `_apply_model_positions` writes it as the
## state, and the retraced route (`_retrace_to`) may end up to 0.0005 m short of that spot (it keeps the trimmed route's own end inside that window). The glide used
## to set each model to the route's last point, so after every move a model stood 0.01 to 0.02 in off its own state (the charger's 1 in separation back-step of the
## melee roster sweep: 49 of 880 charges differed from the core, which ends on the gated spot). The move now publishes the gated spot as `end` and the glide ends on it.
##
## Real: scenes/main.tscn, the real SoloController executor (`separate_from_melee` -> `_execute_move`) and the real glide (`_solo_animate_move`).
## Constructed: the GameUnits and their model nodes, and one hand-made route whose last point lies 3 mm off its `end`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	BattleSim._core_env = 0
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true


func after_test() -> void:
	BattleSim._core_env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A glide whose route ends 3 mm off the published `end` comes to rest ON `end`; a route without one (an older caller) rests on its last point.
func test_the_glide_rests_on_the_published_end_not_on_the_routes_last_point() -> void:
	var a := Vector3(-0.3, 0.0, -0.2)
	var b := Vector3(-0.29, 0.0, -0.2)
	var end := Vector3(-0.2897, 0.0, -0.2003)
	var u := _register(2, "Glider", [a, a + Vector3(0.0, 0.0, 0.1)])
	var with_end := (u.models[0] as ModelInstance).node
	var without := (u.models[1] as ModelInstance).node
	await _main._solo_animate_move([
		{"model": u.models[0], "path": [a, b], "radius_m": 0.0125, "end": end},
		{"model": u.models[1], "path": [a + Vector3(0.0, 0.0, 0.1), b + Vector3(0.0, 0.0, 0.1)], "radius_m": 0.0125}])
	assert_float(with_end.global_position.x).is_equal_approx(end.x, 0.000001)
	assert_float(with_end.global_position.z).is_equal_approx(end.z, 0.000001)
	assert_float(without.global_position.x).is_equal_approx(b.x, 0.000001)
	assert_float(without.global_position.z).is_equal_approx(b.z + 0.1, 0.000001)


## The real executor publishes, per model, the spot it applied as the state, and the glide leaves every model standing exactly there (the charger's
## separation back-step: three models at a defender's side, the step is the unit's own move).
func test_a_separation_back_step_ends_every_model_on_its_applied_state() -> void:
	var inch := 0.0254
	var charger := _register(2, "Charger", [Vector3(5.6 * inch, 0.0, -1.4 * inch), Vector3(5.6 * inch, 0.0, 0.0), Vector3(5.6 * inch, 0.0, 1.4 * inch)])
	var defender := _register(1, "Defender", [Vector3(7.0 * inch, 0.0, 0.0)])
	_main.solo_controller.separate_from_melee(charger, _main.solo_controller.unit_centre(defender))
	var paths: Array = _main.solo_controller.last_move_paths
	assert_int(paths.size()).override_failure_message("the back-step moved nobody: nothing to compare").is_equal(3)
	var applied: Dictionary = {}
	for entry in paths:
		var m: ModelInstance = (entry as Dictionary)["model"]
		assert_bool((entry as Dictionary).has("end")).override_failure_message("a published move names no end").is_true()
		applied[m] = m.node.global_position
		var end: Vector3 = (entry as Dictionary).get("end", Vector3(INF, 0.0, INF))
		assert_float(end.x).is_equal_approx(m.node.global_position.x, 0.000001)
		assert_float(end.z).is_equal_approx(m.node.global_position.z, 0.000001)
	await _main._solo_animate_move(paths, false)
	for m in applied:
		assert_float((m as ModelInstance).node.global_position.x).is_equal_approx((applied[m] as Vector3).x, 0.000001)
		assert_float((m as ModelInstance).node.global_position.z).is_equal_approx((applied[m] as Vector3).z, 0.000001)
