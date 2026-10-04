extends GdUnitTestSuite
## Heights B2 step 17 — the AI climbs a piece up to 3" tall (GF p.11) through the shared MovementPlanner:
## the climbable edge leaves the walls, the climb is movement spent, and the model settles on the surface.

const EDGE_X_M := 2.0 * 0.0254          # a container edge 2" ahead of the model
const ROOF_M := 2.5 * 0.0254

var _seam0 := false


func before_test() -> void:
	_seam0 = SoloController.climb_seam   # statics leak across gdUnit tests — restored in after_test
	SoloController.climb_seam = true


func after_test() -> void:
	SoloController.climb_seam = _seam0


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


func test_with_the_seam_off_the_wired_edge_stays_a_wall() -> void:
	SoloController.climb_seam = false
	var s := _setup(2.5, true)
	var solo: SoloController = s[0]
	var models: Array = solo._moving_models(s[1])
	var out: Array = solo._plan_positions(s[1], models, solo._positions_of(models), Vector3(6.0 * 0.0254, 0, 0), false)
	assert_float((out[0] as Vector3).x).is_less(EDGE_X_M)
