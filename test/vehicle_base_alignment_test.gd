extends GdUnitTestSuite
## Orienting a GLB on its OVAL base. Vehicles (tanks) align ALONG the base long axis; walkers sit
## CROSSWISE ("quer"). Round/square bases and already-correct models are left untouched. Pure
## logic on a throwaway Node3D — Y-only rotation, so scale/y-offset are unaffected.

const OPRMgrScript := preload("res://scripts/opr_army_manager.gd")


func _mgr() -> Object:
	return auto_free(OPRMgrScript.new())


func _glb() -> Node3D:
	return auto_free(Node3D.new())


# ===== Vehicles: align ALONG the oval long axis =====

func test_rotates_when_model_long_x_on_oval_long_z() -> void:
	# Oval long axis Z (depth 0.06 > width 0.035); model longest on X → rotate to run along Z.
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(2, 1, 1)), true, 0.035, 0.06)
	assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_no_rotation_when_already_aligned() -> void:
	# Model longest on Z, base long axis Z → already aligned, no rotation.
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.035, 0.06)
	assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


func test_rotates_when_base_long_x_and_model_long_z() -> void:
	# Symmetric: base long axis X (width 0.06 > depth 0.035), model longest on Z → rotate.
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.06, 0.035)
	assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_round_base_never_rotates() -> void:
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(2, 1, 1)), false, 0.032, 0.032)
	assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


# ===== Walkers: sit CROSSWISE (quer) to the oval long axis =====

func test_walker_no_rotation_when_already_crosswise() -> void:
	# Walker, model long X, oval long Z -> already perpendicular (quer) -> leave it.
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(2, 1, 1)), true, 0.035, 0.06, true)
	assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


func test_walker_rotates_when_aligned_to_long_axis() -> void:
	# Walker, model long Z, oval long Z -> aligned -> rotate so it sits crosswise (quer).
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB(Vector3.ZERO, Vector3(1, 1, 2)), true, 0.035, 0.06, true)
	assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_is_walker_name_heuristic() -> void:
	var mgr := _mgr()
	assert_bool(mgr._is_walker("Combat Walker")).is_true()
	assert_bool(mgr._is_walker("GREAT WALKER")).is_true()
	assert_bool(mgr._is_walker("Battle Tank")).is_false()
	assert_bool(mgr._is_walker("Heavy Gunship")).is_false()
