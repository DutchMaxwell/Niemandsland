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


# A bare Object stands in for a GameUnit: the cache dicts only use it as a key,
# so no real unit/scene is needed to exercise the reduce-to-single transition.
func _stub_unit() -> Object:
	return auto_free(Object.new())


func test_drop_to_single_clears_stale_hull_cache() -> void:
	# A unit reduced to one model must clear its hull rail so a token can never be
	# placed back on the old multi-model boundary (Bug: marker stuck at old spot).
	var viz := _viz()
	var unit := _stub_unit()
	viz._boundary_hull_points[unit] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	viz._boundary_start_indices[unit] = 0

	viz._drop_to_single_model(unit)

	assert_bool(viz._boundary_hull_points.has(unit)).is_false()
	assert_bool(viz._boundary_start_indices.has(unit)).is_false()
	# With no cached hull, no boundary token positions can be produced.
	assert_array(viz.get_token_positions_on_boundary(unit, 3)).is_empty()


func test_drop_to_single_emits_boundary_lost_on_transition() -> void:
	# Had a boundary -> the transition fires boundary_lost (tokens hand over).
	var viz := _viz()
	var with_boundary := _stub_unit()
	var mesh: MeshInstance3D = auto_free(MeshInstance3D.new())
	viz._boundaries[with_boundary] = mesh

	var monitor := monitor_signals(viz)
	viz._drop_to_single_model(with_boundary)
	await assert_signal(monitor).is_emitted("boundary_lost", [with_boundary])


func test_drop_to_single_no_signal_without_prior_boundary() -> void:
	# A unit that never had a boundary (always one model) must NOT emit on a drop.
	var viz := _viz()
	var no_boundary := _stub_unit()

	var monitor := monitor_signals(viz)
	viz._drop_to_single_model(no_boundary)
	await assert_signal(monitor).wait_until(50).is_not_emitted("boundary_lost", [no_boundary])
