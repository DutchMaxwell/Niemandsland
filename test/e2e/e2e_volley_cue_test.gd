extends GdUnitTestSuite
## E2E — VFX #2 rides the REAL volley (_solo_resolve_ai_volley): one tracer per firing model on exactly the
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
	GraphicsSettings.current_preset = _preset_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _shots(attacker: GameUnit, rules: Array[String]) -> Array:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 1
	w.count = attacker.models.size()
	w.special_rules = rules
	return [{"member": attacker, "quality": attacker.get_quality(), "alive": attacker.get_alive_count(),
		"max": attacker.models.size(), "reach": 24, "profile": AiShooting.profiles_in_range([w], 0.0)[0]}]


func _lines() -> Array:
	var out: Array = []
	for seg in _main.volley_cue.get_children():
		var half: Vector3 = (seg as MeshInstance3D).global_transform.basis.y * 0.5
		out.append([(seg as Node3D).global_position - half, (seg as Node3D).global_position + half])
	return out


func test_each_sighted_model_traces_its_rule_eye_pair(timeout := 240000) -> void:
	var shooters := _unit(1, "Line", [Vector3(0, 0, 0), Vector3(0.06, 0, 0)])
	var target := _unit(2, "Mark", [Vector3(0, 0, 10 * INCH)])
	await _main._solo_resolve_ai_volley(shooters, target, _shots(shooters, []), false)
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
	await _main._solo_resolve_ai_volley(shooters, target, _shots(shooters, []), false)
	var lines := _lines()
	assert_int(lines.size()).override_failure_message("only the clear model fires a tracer").is_equal(1)
	assert_float(((lines[0] as Array)[0] as Vector3).x).is_equal_approx(0.12, 0.001)
	await E2EBoot.settle(get_tree())


func test_indirect_fire_draws_no_tracer(timeout := 240000) -> void:
	var shooters := _unit(1, "Mortars", [Vector3(0, 0, 0)])
	var target := _unit(2, "Mark", [Vector3(0, 0, 10 * INCH)])
	await _main._solo_resolve_ai_volley(shooters, target, _shots(shooters, ["Indirect"] as Array[String]), false)
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
	await _main._run_human_shooting(shooters, target)
	var lines := _lines()
	assert_int(lines.size()).is_equal(2)
	var up_from: Vector3 = Vector3.UP * _main._solo_unit_los_height_m(shooters)
	assert_float(((lines[0] as Array)[0] as Vector3).distance_to(shooters.models[0].node.global_position + up_from)).is_less(0.001)
	await E2EBoot.settle(get_tree())

