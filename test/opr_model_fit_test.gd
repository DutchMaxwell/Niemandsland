extends GdUnitTestSuite
## Tests for OPRArmyManager._compute_model_fit - scales a GLB so it fits its base:
## height target ~ base long side, footprint capped at 125% of the base long
## side, the smaller factor wins; Flying units get an extra vertical lift.


func _mgr() -> OPRArmyManager:
	# Not added to the tree, so _ready() (HTTPRequest + registry load) is skipped;
	# _compute_model_fit is pure math and needs none of it.
	return auto_free(OPRArmyManager.new())


func test_footprint_cap_limits_wide_models() -> void:
	var mgr := _mgr()
	# 1 m wide, 0.1 m tall -> the footprint cap is the binding constraint.
	var aabb := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.1, 1.0))
	var base_long_mm := 40
	var fit = mgr._compute_model_fit(aabb, base_long_mm, 0, 0.0)

	var footprint: float = max(aabb.size.x, aabb.size.z) * fit.scale
	var cap: float = base_long_mm * OPRArmyManager.FOOTPRINT_MAX_RATIO * 0.001
	assert_float(footprint).is_equal_approx(cap, 0.0005)


func test_height_target_for_tall_thin_models() -> void:
	var mgr := _mgr()
	# 0.1 m wide, 1 m tall -> the height target is the binding constraint.
	var aabb := AABB(Vector3(-0.05, 0.0, -0.05), Vector3(0.1, 1.0, 0.1))
	var base_long_mm := 32  # > 25 mm -> height target equals the base long side
	var fit = mgr._compute_model_fit(aabb, base_long_mm, 0, 0.0)

	assert_float(aabb.size.y * fit.scale).is_equal_approx(0.032, 0.0005)


func test_flying_adds_lift() -> void:
	var mgr := _mgr()
	var aabb := AABB(Vector3(-0.05, 0.0, -0.05), Vector3(0.1, 0.1, 0.1))
	var base_long_mm := 40
	var expected_lift: float = base_long_mm * OPRArmyManager.FLYING_HOVER_RATIO * 0.001
	var grounded = mgr._compute_model_fit(aabb, base_long_mm, 0, 0.0)
	var flying = mgr._compute_model_fit(aabb, base_long_mm, 0, expected_lift)  # caller-supplied lift

	assert_float(flying.y_offset - grounded.y_offset).is_equal_approx(expected_lift, 0.0001)
	assert_float(flying.height - grounded.height).is_equal_approx(expected_lift, 0.0001)


func test_degenerate_aabb_returns_fallback() -> void:
	var mgr := _mgr()
	var fit = mgr._compute_model_fit(AABB(), 32, 0, 0.0)
	assert_float(fit.scale).is_equal_approx(0.001, 0.0001)
