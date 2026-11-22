extends GdUnitTestSuite
## E2E — VFX #2 rides the REAL volley (the AI body `_run_ai_shooting`, the core door): one tracer per firing model on exactly the
## eye pair the per-model LOS count cleared (base spot + the unit's LOS height, the same numbers the rule
## used), none for a model whose sight line a third unit blocks, and none at all for Indirect fire (its LOS
## is waived — a line there would be drawn through whatever stands in the way).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _preset_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_main.volley_cue.force_for_tests = true
	_main.volley_cue.enabled = true
	_preset_before = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW   # still form: one line per tracer


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	GraphicsSettings.current_preset = _preset_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The unit's own OPR weapon: a 24" Rifle, one gun per model, printing `rules`.
func _arm(attacker: GameUnit, rules: Array[String]) -> void:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 1
	w.count = attacker.models.size()
	w.special_rules = rules
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	attacker.source_type = "opr"
	attacker.source_data = src


## The game's own call: the core door takes the volley (the board is captured first).
func _door_volley(shooters: GameUnit) -> void:
	_main.solo_controller.ai_slot = 1
	_main.solo_controller.human_slot = 2
	_main.opr_army_manager.current_round = 1
	CoreActivation._env = 1
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting(ActIntent.blank_report(shooters))
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot it)") \
		.is_equal(runs + 1)
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0


## The player's own volley through the core door: the activation is opened first (the Fire! button's path), then the
## door shoots; false from the door would mean the table is left to resolve it.
func _door_fire(attacker: GameUnit, target: GameUnit) -> bool:
	CoreActivation._env = 1
	assert_bool(CoreActivation.open_session(_main, attacker)).override_failure_message("no activation session for the attacker").is_true()
	var took: bool = await CoreActivation.human_shoot(_main, attacker, target)
	assert_bool(took).override_failure_message("the core door did not take the volley (the table would resolve it)").is_true()
	CoreActivation.close_session(_main, attacker.unit_id)
	return took


func _lines() -> Array:
	var out: Array = []
	for seg in _main.volley_cue.get_children():
		var half: Vector3 = (seg as MeshInstance3D).global_transform.basis.y * 0.5
		out.append([(seg as Node3D).global_position - half, (seg as Node3D).global_position + half])
	return out


func test_each_sighted_model_traces_its_rule_eye_pair(timeout := 240000) -> void:
	var shooters := _unit(1, "Line", [Vector3(0, 0, 0), Vector3(0.06, 0, 0)])
	var target := _unit(2, "Mark", [Vector3(0, 0, 10 * INCH)])
	_arm(shooters, [])
	await _door_volley(shooters)
	var lines := _lines()
	assert_int(lines.size()).is_equal(2)
	var up_from: Vector3 = Vector3.UP * _main._solo_unit_los_height_m(shooters)
	var up_to: Vector3 = Vector3.UP * _main._solo_unit_los_height_m(target)
	for i in 2:
		var mi := shooters.models[i] as ModelInstance
		var ends: Array = lines[i]
		assert_float((ends[0] as Vector3).distance_to(mi.node.global_position + up_from)).is_less(0.001)
		assert_float((ends[1] as Vector3).distance_to(target.models[0].node.global_position + up_to)).is_less(0.001)
	await E2EBoot.settle(get_tree())


func test_a_blocked_model_draws_no_tracer(timeout := 240000) -> void:
	var shooters := _unit(1, "Line", [Vector3(0, 0, 0), Vector3(0.12, 0, 0)])
	var target := _unit(2, "Mark", [Vector3(0, 0, 10 * INCH)])
	_unit(1, "Wall", [Vector3(0, 0, 5 * INCH)])   # a third unit's base right on shooter 1's sight line
	_arm(shooters, [])
	await _door_volley(shooters)
	var lines := _lines()
	assert_int(lines.size()).override_failure_message("only the clear model fires a tracer").is_equal(1)
	assert_float(((lines[0] as Array)[0] as Vector3).x).is_equal_approx(0.12, 0.001)
	await E2EBoot.settle(get_tree())


func test_indirect_fire_draws_no_tracer(timeout := 240000) -> void:
	var shooters := _unit(1, "Mortars", [Vector3(0, 0, 0)])
	var target := _unit(2, "Mark", [Vector3(0, 0, 10 * INCH)])
	_arm(shooters, ["Indirect"] as Array[String])
	await _door_volley(shooters)
	assert_str(_main.battle_log.entries().map(func(e): return str(e["text"])).reduce(func(a, b): return a + b, "")) \
		.override_failure_message("fixture: the indirect weapon must fire").contains("Rifle")
	assert_int(_main.volley_cue.get_child_count()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_the_players_own_volley_traces_too(timeout := 240000) -> void:
	var shooters := _unit(1, "Squad", [Vector3(0, 0, 0), Vector3(0.06, 0, 0)])
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 1
	w.count = 2
	opr.weapons = [w] as Array[OPRApiClient.OPRWeapon]
	shooters.source_type = "opr"
	shooters.source_data = opr
	var target := _unit(2, "Mark", [Vector3(0, 0, 10 * INCH)])
	_main.solo_ai_slots = {2: true}   # the player's own unit against the AI's: the human door
	if not await _door_fire(shooters, target):
		return   # the assertion above failed: nothing was shot, nothing to read
	var lines := _lines()
	assert_int(lines.size()).is_equal(2)
	var up_from: Vector3 = Vector3.UP * _main._solo_unit_los_height_m(shooters)
	assert_float(((lines[0] as Array)[0] as Vector3).distance_to(shooters.models[0].node.global_position + up_from)).is_less(0.001)
	await E2EBoot.settle(get_tree())

