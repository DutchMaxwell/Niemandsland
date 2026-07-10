extends GdUnitTestSuite
## Tests for OPRArmyManager._compute_model_fit - scales a GLB so it fits its base:
## height target ~ base long side, footprint capped at 125% of the base long
## side, the smaller factor wins; Aircraft get a caller-supplied flight-stand lift.


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


func test_caller_supplied_lift_adds_offset() -> void:
	# A caller-supplied lift (Aircraft flight stand) shifts the y_offset and reported height by exactly
	# that lift. Flying no longer produces a lift — the caller passes 0 for it (see opr_item_grants_test).
	var mgr := _mgr()
	var aabb := AABB(Vector3(-0.05, 0.0, -0.05), Vector3(0.1, 0.1, 0.1))
	var base_long_mm := 40
	var expected_lift: float = OPRArmyManager.AIRCRAFT_HOVER_M
	var grounded = mgr._compute_model_fit(aabb, base_long_mm, 0, 0.0)
	var lifted = mgr._compute_model_fit(aabb, base_long_mm, 0, expected_lift)  # caller-supplied lift

	assert_float(lifted.y_offset - grounded.y_offset).is_equal_approx(expected_lift, 0.0001)
	assert_float(lifted.height - grounded.height).is_equal_approx(expected_lift, 0.0001)


func test_degenerate_aabb_returns_fallback() -> void:
	var mgr := _mgr()
	var fit = mgr._compute_model_fit(AABB(), 32, 0, 0.0)
	assert_float(fit.scale).is_equal_approx(0.001, 0.0001)


func test_oval_base_fits_model_within_narrow_width() -> void:
	var mgr := _mgr()
	# Dwarf Attack Vehicle case: a ~square-footprint hull (1.0 x 1.0, 0.64 tall) on a 120x92 oval
	# base. It must fit WITHIN the narrow 92mm width (+5%), NOT be scaled to base_long x 1.25 (=150mm)
	# which overhung the width by +63% (the reported scale-creep).
	var aabb := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.64, 1.0))
	var fit = mgr._compute_model_fit(aabb, 120, 6, 0.0, 92)  # base_long=120, base_short=92
	var footprint_mm: float = max(aabb.size.x, aabb.size.z) * fit.scale * 1000.0
	assert_float(footprint_mm).is_equal_approx(92.0 * mgr.OVAL_FOOTPRINT_RATIO, 1.0)  # fits the 92mm width
	assert_float(footprint_mm).is_less_equal(120.0)  # within the base, no overhang


func test_vehicle_aligned_along_oval_long_axis_walker_across() -> void:
	var mgr := _mgr()
	# An X-LONG model (decisive aspect 2.0): its LENGTH must land on the base's long axis (QA r4 —
	# the snakes-crosswise fix; the model's own axis drives the mapping, not a Z-forward assumption).
	var aabb := AABB(Vector3.ZERO, Vector3(1, 0.5, 0.5))
	# Base long axis = Z (depth 0.120 >= width 0.092): X-long model → turn 90° so its length runs on Z.
	var veh_z: Node3D = auto_free(Node3D.new())
	mgr._align_to_oval_long_axis(veh_z, aabb, true, 0.092, 0.120, false)
	assert_float(absf(veh_z.rotation.y)).is_equal_approx(PI / 2.0, 0.01)
	# Base long axis = X (width 0.120 > depth 0.092): X-long model already aligned → no turn.
	var veh_x: Node3D = auto_free(Node3D.new())
	mgr._align_to_oval_long_axis(veh_x, aabb, true, 0.120, 0.092, false)
	assert_float(veh_x.rotation.y).is_equal_approx(0.0, 0.01)
	# Walker: deterministic crosswise, AABB ignored — long axis = Z → turn 90° (faces ACROSS it).
	var walker: Node3D = auto_free(Node3D.new())
	mgr._align_to_oval_long_axis(walker, aabb, true, 0.092, 0.120, true)
	assert_float(absf(walker.rotation.y)).is_equal_approx(PI / 2.0, 0.01)


func test_tough_derived_round_base_fits_with_no_overhang() -> void:
	var mgr := _mgr()
	# A bracketless vehicle: round base sized from Tough (e.g. T6 -> 60mm), fit_to_base=true. A wide
	# hull fills the base EXACTLY (no 125% overhang); an organic mini (fit_to_base=false) keeps the margin.
	var aabb := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.3, 1.0))
	var fp_fit: float = max(aabb.size.x, aabb.size.z) * mgr._compute_model_fit(aabb, 60, 6, 0.0, -1, true).scale * 1000.0
	var fp_org: float = max(aabb.size.x, aabb.size.z) * mgr._compute_model_fit(aabb, 60, 6, 0.0, -1, false).scale * 1000.0
	assert_float(fp_fit).is_equal_approx(60.0, 0.5)         # fills the base, no overhang
	assert_float(fp_org).is_equal_approx(60.0 * 1.25, 0.5)  # default round keeps the organic margin
