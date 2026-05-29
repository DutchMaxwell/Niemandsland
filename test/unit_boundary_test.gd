extends GdUnitTestSuite
## Tests for UnitBoundaryVisualizer hull geometry: each model point is expanded
## by its OWN base radius so a joined Hero on a larger base is enclosed correctly.


func _viz() -> UnitBoundaryVisualizer:
	# Not in the tree, so _ready()/army_manager lookup is skipped; the hull math
	# is pure.
	return auto_free(UnitBoundaryVisualizer.new())


func test_hull_expands_each_point_by_its_own_radius() -> void:
	var viz := _viz()
	# Point at x=1 has a big base (0.05 m), point at x=0 a small one (0.01 m).
	var positions: Array = [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	var radii: Array = [0.01, 0.05]
	var hull := viz._calculate_smooth_hull(positions, radii)

	assert_int(hull.size()).is_greater(2)

	var max_x := -INF
	var min_x := INF
	for point in hull:
		max_x = maxf(max_x, point.x)
		min_x = minf(min_x, point.x)

	# Right side reflects the big base (~1 + 0.05), left side the small one (~-0.01),
	# i.e. the expansion is per-point, not a single uniform radius.
	assert_float(max_x).is_greater(1.0 + 0.05)
	assert_float(min_x).is_greater(-0.05)
	assert_float(min_x).is_less(0.0)


func test_uniform_small_radius_stays_tight() -> void:
	var viz := _viz()
	var positions: Array = [Vector2(0.0, 0.0), Vector2(0.5, 0.0)]
	var radii: Array = [0.01, 0.01]
	var hull := viz._calculate_smooth_hull(positions, radii)

	var max_x := -INF
	for point in hull:
		max_x = maxf(max_x, point.x)
	# Both small bases -> hull only slightly past 0.5.
	assert_float(max_x).is_less(0.5 + 0.02)
