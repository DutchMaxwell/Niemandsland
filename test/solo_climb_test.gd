extends GdUnitTestSuite
## Heights B2 step 17 — the AI climbs a piece up to 3" tall (GF p.11) through the shared MovementPlanner:
## the climbable edge leaves the walls, the climb is movement spent, and the model settles on the surface.

const EDGE_X_M := 2.0 * 0.0254          # a container edge 2" ahead of the model
const ROOF_M := 2.5 * 0.0254

var _epoch0 := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch   # statics leak across gdUnit tests — restored in after_test
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_70_TRAY_EXACT


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _setup(dy_in: float, wired: bool) -> Array:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	var a := Vector2(EDGE_X_M, -0.5)
	var b := Vector2(EDGE_X_M, 0.5)
	solo.walls_provider = func() -> Array: return [[a, b]]   # the container edge is ALSO a wall today
	if wired:
		solo.ledges_provider = func() -> Array: return [{"a": a, "b": b, "dy_in": dy_in}]
		solo.surface_y_provider = func(p: Vector2) -> float: return ROOF_M if p.x > EDGE_X_M else 0.0
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": 25}
	var model := ModelInstance.new()
	model.unit = unit
	model.is_alive = true
	model.properties = {"tough": 1}
	model.node = auto_free(Node3D.new())
	add_child(model.node)
	model.node.global_position = Vector3.ZERO
	unit.models.append(model)
	return [solo, unit, model]


func test_ai_advance_climbs_a_ledge_pays_it_and_settles_on_the_roof() -> void:
	var s := _setup(2.5, true)
	var solo: SoloController = s[0]
	solo._execute_move(s[1], Vector3(1.0, 0, 0), 6.0, false)
	var node: Node3D = (s[2] as ModelInstance).node
	assert_float(node.global_position.x / 0.0254).is_equal_approx(3.5, 0.15)   # 2" + 1.5" after the 2.5" climb
	assert_float(node.global_position.y).is_equal_approx(ROOF_M, 0.0001)
	assert_float(solo.last_move_climb_in).is_equal_approx(2.5, 0.01)


func test_without_the_ledge_wiring_the_edge_stays_a_wall() -> void:
	var s := _setup(2.5, false)
	# Plan only (a blocked execute walks the boxed-in ladder, which needs an army manager).
	var solo: SoloController = s[0]
	var models: Array = solo._moving_models(s[1])
	var out: Array = solo._plan_positions(s[1], models, solo._positions_of(models), Vector3(6.0 * 0.0254, 0, 0), false)
	assert_float((out[0] as Vector3).x).is_less(EDGE_X_M)


func test_at_epoch_69_the_wired_edge_stays_a_wall() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_70_TRAY_EXACT - 1
	var s := _setup(2.5, true)
	var solo: SoloController = s[0]
	var models: Array = solo._moving_models(s[1])
	var out: Array = solo._plan_positions(s[1], models, solo._positions_of(models), Vector3(6.0 * 0.0254, 0, 0), false)
	assert_float((out[0] as Vector3).x).is_less(EDGE_X_M)


# --- F3: a multi-model Rush over one closed container may not climb for free ---------------------------
# A 6"x3" container (2.5" tall) centred on the table origin. The climb is movement spent (GF p.11), so after
# the real _execute_move pipeline (plan, coherency pull, untangle, solver, distance-truth trim, gate) every
# model's published route must cost at most the 8" band as ground distance + climb paid.

const IN_M := 0.0254
const RUSH_IN := 8.0


func _box_edges_m() -> Array:
	var c := [Vector2(-3, -1.5), Vector2(3, -1.5), Vector2(3, 1.5), Vector2(-3, 1.5)]
	var out: Array = []
	for i in range(4):
		out.append([(c[i] as Vector2) * IN_M, (c[(i + 1) % 4] as Vector2) * IN_M])
	return out


## Move a unit of n models (a 5-wide grid, 1.6" pitch, from `origin_in`) toward `goal_in` on an 8" Rush;
## returns [solo, ledges] after the move.
func _rush_over_box(n: int, origin_in: Vector2, goal_in: Vector2) -> Array:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	var box := _box_edges_m()
	var ledges: Array = []
	for w in box:
		ledges.append({"a": w[0], "b": w[1], "dy_in": 2.5})
	solo.walls_provider = func() -> Array: return box   # the container edges are ALSO walls today
	solo.ledges_provider = func() -> Array: return ledges
	solo.surface_y_provider = func(p: Vector2) -> float:
		return ROOF_M if absf(p.x) < 3.0 * IN_M and absf(p.y) < 1.5 * IN_M else 0.0
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": 25}
	for i in range(n):
		var p: Vector2 = origin_in + Vector2(float(i % 5) * 1.6, floorf(float(i) / 5.0) * 1.6)
		var model := ModelInstance.new()
		model.unit = unit
		model.is_alive = true
		model.properties = {"tough": 1}
		model.node = auto_free(Node3D.new())
		add_child(model.node)
		model.node.global_position = Vector3(p.x * IN_M, 0, p.y * IN_M)
		unit.models.append(model)
	solo._execute_move(unit, Vector3(goal_in.x * IN_M, 0, goal_in.y * IN_M), RUSH_IN, false)
	return [solo, ledges]


## [worst flat + climb over all published routes, summed climb of all routes, nearest route end to the
## container in inches (0 = on or over it)].
func _worst_cost_in(solo: SoloController, ledges: Array) -> Array:
	var worst := 0.0
	var climbed := 0.0
	var nearest := INF
	for e in solo.last_move_paths:
		var path: Array = e["path"]
		var climb := SoloController._trail_climb_in(path, ledges)
		climbed += climb
		worst = maxf(worst, MovementPlanner.polyline_length(path) / IN_M + climb)
		var end := (path.back() as Vector3) / IN_M
		nearest = minf(nearest, Vector2(maxf(absf(end.x) - 3.0, 0.0), maxf(absf(end.z) - 1.5, 0.0)).length())
	return [worst, climbed, nearest]


## Three unit shapes and approaches that each sent a model over a ledge it had no movement left for.
const OVER_THE_BOX := [[5, Vector2(-2.88, -7.55), Vector2(2.51, 2.60)],
	[5, Vector2(-4.61, -4.69), Vector2(2.12, 0.79)],
	[3, Vector2(2.98, 4.77), Vector2(0.92, -2.04)]]


func test_at_epoch_74_multi_model_rush_over_a_container_pays_every_climb_within_the_band() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_74_CLIMB_COST
	for c in OVER_THE_BOX:
		var r := _rush_over_box(int(c[0]), c[1], c[2])
		var cost := _worst_cost_in(r[0], r[1])
		# The scenario must still press the unit against the container (a model on it, or at its edge).
		assert_float(cost[2]).override_failure_message("case %s: the unit ended %.2f\" from the container — the scenario lost its ledge"
			% [str(c), cost[2]]).is_less_equal(1.0)
		assert_float(cost[0]).override_failure_message("case %s: a model spent %.2f\" (ground + climb) of an 8\" Rush"
			% [str(c), cost[0]]).is_less_equal(RUSH_IN + 0.02)


## The old leg: a record stamped EPOCH_73_V36 was made with the flat trims after the priced walk, so the same
## Rushes still replay it - at least one model climbs past the 8" band, exactly as before #2608.
func test_at_epoch_73_the_trims_after_the_walk_stay_flat() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var worst := 0.0
	for c in OVER_THE_BOX:
		var r := _rush_over_box(int(c[0]), c[1], c[2])
		worst = maxf(worst, float(_worst_cost_in(r[0], r[1])[0]))
	assert_float(worst).override_failure_message("at epoch 73 every route kept the band: the climb cost leaked below its gate") \
		.is_greater(RUSH_IN + 0.02)


func test_control_rush_beside_the_container_climbs_nothing_and_keeps_the_full_band() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_74_CLIMB_COST
	var r := _rush_over_box(5, Vector2(-14.0, 6.0), Vector2(4.0, 6.0))
	var cost := _worst_cost_in(r[0], r[1])
	assert_float(cost[1]).is_equal(0.0)
	assert_float(cost[0]).is_equal_approx(RUSH_IN, 0.02)
