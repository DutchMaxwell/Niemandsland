extends GdUnitTestSuite
## Pure-logic tests for OPRArmyManager's model-building math: tough/scale, flying &
## walker detection, oval long-axis orientation, and AABB measurement. The spawn /
## tray / regiment-forming paths need the SceneTree + ObjectManager and are out of
## scope. Already covered elsewhere: _compute_model_fit, model_base_long_mm,
## round bookkeeping, _should_hover, buff_tokens_from_rules.


func _mgr() -> OPRArmyManager:
	# Not added to the tree: _ready() is skipped; the helpers under test are pure.
	return auto_free(OPRArmyManager.new())


# ===== _calculate_model_scale: pow(1.05, tough/3) =====

func test_calculate_model_scale() -> void:
	var m := _mgr()
	assert_float(m._calculate_model_scale(0)).is_equal_approx(1.0, 0.0001)
	assert_float(m._calculate_model_scale(3)).is_equal_approx(1.05, 0.0001)
	assert_float(m._calculate_model_scale(6)).is_equal_approx(1.1025, 0.0001)
	assert_float(m._calculate_model_scale(12)).is_equal_approx(1.2155, 0.001)


# ===== _is_flying_from_rules =====

func test_is_flying_from_rules() -> void:
	var m := _mgr()
	assert_bool(m._is_flying_from_rules(["Flying", "Tough(3)"])).is_true()
	assert_bool(m._is_flying_from_rules(["Flying(6)"])).is_true()
	assert_bool(m._is_flying_from_rules(["Fast", "Strider"])).is_false()
	assert_bool(m._is_flying_from_rules([])).is_false()


# ===== _is_walker (case-insensitive substring) =====

func test_is_walker() -> void:
	var m := _mgr()
	assert_bool(m._is_walker("Battle Walker")).is_true()
	assert_bool(m._is_walker("WALKER PRIME")).is_true()
	assert_bool(m._is_walker("Battle Brothers")).is_false()


# ===== _get_tough_value_from_rules (string + dict entries) =====

func test_get_tough_value_from_rules() -> void:
	var m := _mgr()
	assert_int(m._get_tough_value_from_rules(["Fearless", "Tough(6)"])).is_equal(6)
	assert_int(m._get_tough_value_from_rules([{"name": "Tough(12)"}])).is_equal(12)
	assert_int(m._get_tough_value_from_rules(["Fast"])).is_equal(0)
	assert_int(m._get_tough_value_from_rules([])).is_equal(0)
	# First Tough wins.
	assert_int(m._get_tough_value_from_rules(["Tough(3)", "Tough(6)"])).is_equal(3)


# ===== _align_to_oval_long_axis (Y-only rotation) =====

func _glb() -> Node3D:
	return auto_free(Node3D.new())


func test_align_noop_on_non_oval() -> void:
	var m := _mgr()
	var glb := _glb()
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.2)), false, 0.035, 0.060)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


func test_align_walker_turns_crosswise_on_z_long_base() -> void:
	var m := _mgr()
	var glb := _glb()
	# Oval long axis is Z (depth 60 >= width 35); walker (cross_align) -> 90° turn.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.6, 0.6, 0.6)), true, 0.035, 0.060, true)
	assert_float(glb.rotation.y).is_equal_approx(PI / 2.0, 0.0001)


func test_align_vehicle_turns_when_model_long_axis_crosses_base() -> void:
	var m := _mgr()
	var glb := _glb()
	# Base long = Z; model long = X (aabb.x > aabb.z) -> perpendicular -> 90° turn.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.3, 0.1, 0.1)), true, 0.035, 0.060, false)
	assert_float(glb.rotation.y).is_equal_approx(PI / 2.0, 0.0001)


func test_align_vehicle_keeps_when_already_aligned() -> void:
	var m := _mgr()
	var glb := _glb()
	# Base long = Z; model long = Z (aabb.z > aabb.x) -> already aligned -> no turn.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.3)), true, 0.035, 0.060, false)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


# ===== _get_model_aabb =====

func test_get_model_aabb_measures_box_mesh() -> void:
	var m := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.2, 0.3)
	mi.mesh = box
	root.add_child(mi)
	var aabb: AABB = m._get_model_aabb(root)
	assert_float(aabb.size.x).is_equal_approx(0.1, 0.0001)
	assert_float(aabb.size.y).is_equal_approx(0.2, 0.0001)
	assert_float(aabb.size.z).is_equal_approx(0.3, 0.0001)


func test_get_model_aabb_empty_node_is_zero() -> void:
	var m := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	var aabb: AABB = m._get_model_aabb(root)
	assert_float(aabb.size.length()).is_equal_approx(0.0, 0.0001)
