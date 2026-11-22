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
