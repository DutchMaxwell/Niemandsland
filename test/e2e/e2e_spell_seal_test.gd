extends GdUnitTestSuite
## E2E — VFX #3 rides the REAL cast resolver (_solo_resolve_one_cast): the seal forms at the caster with the
## purple preview ring's own radius (RangeRingController: base edge + spell range), flares when the logged
## cast roll is a SUCCESS and cracks when it FAILED, and a cast that fizzles before any die draws no seal.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _seals: Array = []


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
	_main.spell_seal.force_for_tests = true
	_main.spell_seal.enabled = true
	_seals.clear()
	_main.spell_seal.child_entered_tree.connect(func(n: Node) -> void: _seals.append(n))


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _cast(caster: GameUnit, targets: Array) -> Dictionary:
	return {"caster": caster, "caster_unit": caster, "name": "Hex", "targets": targets, "boost": 0,
		"interference": 0, "base_target": 4, "threshold": 1,
		"spell": {"range_in": 12, "effect": {"kind": "debuff", "grants_rule": "Slowed"}}}


func _param(seal: Node, key: String) -> float:
	return float(((seal as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(key))


func test_the_seal_sits_on_the_preview_ring_and_follows_the_roll(timeout := 240000) -> void:
	var caster := _unit(1, "Seer", Vector3(0.1, 0, 0))
	var target := _unit(2, "Mark", Vector3(0.1, 0, 8 * INCH))
	for attempt in 6:   # 4+ casts: both outcomes show up within a few tries, each one is checked
		var before: int = _main.battle_log.entries().size()
		await _main._solo_resolve_one_cast(_cast(caster, [target]))
		assert_int(_seals.size()).is_equal(attempt + 1)
		var seal: Node3D = _seals[attempt]
		var node: Node3D = caster.models[0].node
		var radius: float = _main.range_ring_controller.ring_outer_radius_for_props(
			_main.range_ring_controller._props_of(node), 12)
		assert_float(SpellSeal.BAND_M / _param(seal, "band")).is_equal_approx(radius, 0.001)
		assert_float(Vector2(seal.global_position.x, seal.global_position.z).distance_to(
			Vector2(node.global_position.x, node.global_position.z))).is_less(0.001)
		var lines: String = ""
		for e in _main.battle_log.entries().slice(before):
			lines += str(e["text"]) + "\n"
		await get_tree().create_timer(0.2).timeout
		if lines.contains("— SUCCESS"):
			assert_float(_param(seal, "flare")).override_failure_message(lines).is_greater(0.5)
			assert_float(_param(seal, "crack")).is_equal(0.0)
		else:
			assert_str(lines).contains("— FAILED")
			assert_float(_param(seal, "crack")).override_failure_message(lines).is_greater(0.3)
			assert_float(_param(seal, "flare")).is_equal(0.0)
	await get_tree().create_timer(1.0).timeout
	assert_int(_main.spell_seal.get_child_count()).override_failure_message("every seal must leave").is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_fizzled_cast_draws_no_seal(timeout := 240000) -> void:
	var caster := _unit(1, "Seer", Vector3.ZERO)
	await _main._solo_resolve_one_cast(_cast(caster, []))
	assert_int(_seals.size()).is_equal(0)
	await E2EBoot.settle(get_tree())
