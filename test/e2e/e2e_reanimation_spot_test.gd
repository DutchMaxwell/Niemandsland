extends GdUnitTestSuite
## E2E - REVIVE-SPOT (PLAN_REVIVE_SPOT step 5, the table twin of the core's PENDING_EPOCH_REVIVE_SPOT): a model that
## Reanimation brings back stands on a legal spot - never in impassable terrain (a container), never off the table -
## and the placer no longer tries the spot where the model FELL first: the ring beside the anchors, in anchor order,
## +X first, is the only candidate list (the core keeps no fallen position, so both sides pick the same spot).

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


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## One standing model at `anchor` and one casualty that fell at `fell` (world metres, x / z).
func _pair(anchor: Vector2, fell: Vector2) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Bots", [Vector3(anchor.x, 0, anchor.y), Vector3(fell.x, 0, fell.y)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	u.unit_properties["special_rules"] = ["Reanimation"]
	u.unit_properties["faction_folder"] = "robot_legions"
	for i in 2:
		var m := u.models[i] as ModelInstance
		m.model_index = i
		m.wounds_max = 1
		m.wounds_current = 1
	var dead := u.models[1] as ModelInstance
	dead.wounds_current = 0
	dead.is_alive = false
	return u


func _xz(m: ModelInstance) -> Vector2:
	return Vector2(m.node.global_position.x, m.node.global_position.z)


func test_a_revive_never_lands_in_a_container() -> void:
	# A container ring around the anchor: every ring spot (base gap 2 mm and 0.5" + 2 mm) touches it; the casualty
	# fell far away (out of coherency), so before REVIVE-SPOT the ring spot was taken with no terrain check.
	_main.solo_controller.terrain_type_at = func(p: Vector3) -> int:
		var d := Vector2(p.x, p.z).length()
		return int(TerrainRules.TerrainType.CONTAINER) if d > 0.025 and d < 0.08 else int(TerrainRules.TerrainType.NONE)
	var u := _pair(Vector2.ZERO, Vector2(0.3, 0.0))
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool((u.models[1] as ModelInstance).is_alive) \
		.override_failure_message("restored into the container at %s:\n%s" % [str(_xz(u.models[1])), _log_text()]) \
		.is_false()
	assert_str(_log_text()).contains(
		"Reanimation: 1 successes but only 0 models placeable — coherency to non-restored models missing")


func test_the_ring_starts_at_anchor_zero_plus_x_and_ignores_the_fell_spot() -> void:
	# Planted control (no container): the casualty fell on a legal, coherent spot, 50 mm south of the anchor. The
	# placer must NOT stand it there any more: anchor 0, base gap 2 mm, heading +X.
	var u := _pair(Vector2.ZERO, Vector2(0.0, 0.05))
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool((u.models[1] as ModelInstance).is_alive).is_true()
	var r: float = _main._solo_base_radius(u.models[1])
	assert_vector(_xz(u.models[1])).is_equal_approx(Vector2(2.0 * r + 0.002, 0.0), Vector2(0.0005, 0.0005))


func test_a_revive_never_leaves_the_table() -> void:
	var half: Vector2 = _main.solo_controller._table_half_extents()
	var u := _pair(Vector2(half.x - 0.02, 0.0), Vector2(0.0, 0.0))
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool((u.models[1] as ModelInstance).is_alive).is_true()
	var r: float = _main._solo_base_radius(u.models[1])
	assert_float(absf(_xz(u.models[1]).x) + r) \
		.override_failure_message("the base hangs over the table edge at %s" % str(_xz(u.models[1]))) \
		.is_less_equal(half.x)


## REVIVE-MEMBERS (lead ruling): the army-book entry fires for a unit where all models have the rule, and a joined Hero
## counts as part of the unit (Beginner's Guide 3.6). A host with plain Reanimation and a standing joined hero WITHOUT it:
## no roll. The same hero WITH the rule: the chain rolls.
func _host_and_hero(hero_rules: Array) -> GameUnit:
	var host := _pair(Vector2.ZERO, Vector2(0.3, 0.0))
	var hero := E2EBoot.make_unit(_main, 2, "Hero", [Vector3(-0.05, 0, 0)])
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	hero.unit_properties["special_rules"] = hero_rules
	hero.unit_properties["faction_folder"] = "robot_legions"
	host.unit_properties["attached_heroes"] = [hero]
	return host


func _rolls() -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with("Reanimation: Bots rolls"):
			n += 1
	return n


func test_a_joined_hero_without_the_rule_stops_the_roll() -> void:
	var host := _host_and_hero(["Hero"])
	await _main._solo_try_reanimation(host)
	assert_int(_rolls()).override_failure_message("rolled for a unit whose joined hero lacks the rule:\n%s" % _log_text()) \
		.is_equal(0)
	assert_str(_log_text()).override_failure_message("every applied rule logs").contains(
		"Reanimation: Bots does not reanimate — a joined model lacks the rule")


func test_a_joined_hero_with_the_rule_lets_the_chain_roll() -> void:
	var host := _host_and_hero(["Hero", "Reanimation"])
	await _main._solo_try_reanimation(host)
	assert_int(_rolls()).override_failure_message("planted: the chain must roll:\n%s" % _log_text()).is_equal(1)



## Review of #3385: no ring candidate beyond a wall or on another level (the core's `revive_line_blocked`).
func test_a_ring_line_through_a_wall_or_onto_another_level_is_blocked() -> void:
	var solo = _main.solo_controller
	solo.walls_provider = func() -> Array: return [[Vector2(0.028, -0.05), Vector2(0.028, 0.05)]]
	await _runner.simulate_frames(1)   # `_rest_walls` caches per frame
	assert_bool(_main._solo_reanimation_line_blocked(Vector3.ZERO, Vector3(0.0467, 0, 0))).override_failure_message("through the wall").is_true()
	assert_bool(_main._solo_reanimation_line_blocked(Vector3.ZERO, Vector3(-0.0467, 0, 0))).override_failure_message("away from it").is_false()
	solo.walls_provider = func() -> Array: return []
	solo.surface_y_provider = func(p: Vector2) -> float: return 0.0762 if p.x > 0.02 else 0.0
	await _runner.simulate_frames(1)
	assert_bool(_main._solo_reanimation_line_blocked(Vector3.ZERO, Vector3(0.034, 0, 0))).override_failure_message("onto the raised tier").is_true()
	assert_bool(_main._solo_reanimation_line_blocked(Vector3.ZERO, Vector3(-0.034, 0, 0))).override_failure_message("same level").is_false()


## Review of #3385: the restored model stands ON the surface under its spot (the core settles it), not at the anchor's height.
func test_a_restored_model_stands_on_the_surface() -> void:
	_main.solo_controller.surface_y_provider = func(_p: Vector2) -> float: return 0.01
	var u := _pair(Vector2.ZERO, Vector2(0.3, 0.0))
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool((u.models[1] as ModelInstance).is_alive).is_true()
	assert_float((u.models[1] as ModelInstance).node.global_position.y) \
		.override_failure_message("floating at the anchor's height").is_equal_approx(0.01, 0.0001)
