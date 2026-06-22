extends GdUnitTestSuite
## Orienting a GLB on its OVAL base. Vehicles (tanks) align ALONG the base long axis; walkers sit
## CROSSWISE ("quer"). Round/square bases and already-correct models are left untouched. Pure
## logic on a throwaway Node3D — Y-only rotation, so scale/y-offset are unaffected.

const OPRMgrScript := preload("res://scripts/opr_army_manager.gd")


func _mgr() -> Object:
	return auto_free(OPRMgrScript.new())


func _glb() -> Node3D:
	return auto_free(Node3D.new())


# ===== Vehicles: run ALONG the oval long axis, DETERMINISTICALLY (AABB ignored) =====
# A near-square hull has no reliable AABB long axis; vehicle orientation depends ONLY on the base
# geometry (the exact opposite turn from a walker), so identical vehicles are always consistent.

func test_vehicle_no_rotation_on_depth_long_oval() -> void:
	# Depth-long oval (depth 0.06 >= width 0.035): the model's +Z already runs ALONG the long Z axis
	# → no turn, regardless of the AABB.
	var gx := _glb()
	_mgr()._align_to_oval_long_axis(gx, AABB(Vector3.ZERO, Vector3(2, 1, 1)), true, 0.035, 0.06)
	assert_float(gx.rotation.y).is_equal_approx(0.0, 0.001)
	var gz := _glb()
	_mgr()._align_to_oval_long_axis(gz, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.035, 0.06)
	assert_float(gz.rotation.y).is_equal_approx(0.0, 0.001)


func test_vehicle_rotates_on_width_long_oval() -> void:
	# Width-long oval (width 0.06 > depth 0.035): turn 90° so +Z runs ALONG the long X axis — any AABB.
	var gx := _glb()
	_mgr()._align_to_oval_long_axis(gx, AABB(Vector3.ZERO, Vector3(2, 1, 1)), true, 0.06, 0.035)
	assert_float(absf(gx.rotation.y)).is_equal_approx(PI / 2.0, 0.001)
	var gz := _glb()
	_mgr()._align_to_oval_long_axis(gz, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.06, 0.035)
	assert_float(absf(gz.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_round_base_never_rotates() -> void:
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(2, 1, 1)), false, 0.032, 0.032)
	assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


# ===== Walkers: sit CROSSWISE (quer), DETERMINISTICALLY (AABB ignored) =====
# A biped footprint is near-square, so the AABB long axis is noise; walker orientation depends
# only on the base geometry, so identical walkers are always consistent.

func test_walker_quer_is_deterministic_on_depth_long_oval() -> void:
	# Depth-long oval (depth > width): rotate 90° to sit quer — same for ANY AABB.
	var gx := _glb()
	_mgr()._align_to_oval_long_axis(gx, AABB(Vector3.ZERO, Vector3(2, 1, 1)), true, 0.035, 0.06, true)
	assert_float(absf(gx.rotation.y)).is_equal_approx(PI / 2.0, 0.001)
	var gz := _glb()
	_mgr()._align_to_oval_long_axis(gz, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.035, 0.06, true)
	assert_float(absf(gz.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_walker_no_rotation_on_width_long_oval() -> void:
	# Width-long oval (width > depth): model +Z already faces the short axis -> no rotation, any AABB.
	var gx := _glb()
	_mgr()._align_to_oval_long_axis(gx, AABB(Vector3.ZERO, Vector3(2, 1, 1)), true, 0.06, 0.035, true)
	assert_float(gx.rotation.y).is_equal_approx(0.0, 0.001)
	var gz := _glb()
	_mgr()._align_to_oval_long_axis(gz, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.06, 0.035, true)
	assert_float(gz.rotation.y).is_equal_approx(0.0, 0.001)


func test_is_walker_name_heuristic() -> void:
	var mgr := _mgr()
	assert_bool(mgr._is_walker("Combat Walker")).is_true()
	assert_bool(mgr._is_walker("GREAT WALKER")).is_true()
	assert_bool(mgr._is_walker("Battle Tank")).is_false()
	assert_bool(mgr._is_walker("Heavy Gunship")).is_false()
