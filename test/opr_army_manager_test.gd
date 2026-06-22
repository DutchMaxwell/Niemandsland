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


func test_align_vehicle_no_turn_on_depth_long_oval() -> void:
	var m := _mgr()
	var glb := _glb()
	# Deterministic: base long = Z (depth 0.060 >= width 0.035) -> vehicle +Z already runs ALONG it,
	# no turn, EVEN with a model-long-X AABB (the AABB is ignored now).
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.3, 0.1, 0.1)), true, 0.035, 0.060, false)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


func test_align_vehicle_turns_on_width_long_oval() -> void:
	var m := _mgr()
	var glb := _glb()
	# Base long = X (width 0.060 > depth 0.035) -> turn 90° so the vehicle's +Z runs ALONG the long X
	# axis (the exact opposite turn from a walker); AABB ignored.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.3)), true, 0.060, 0.035, false)
	assert_float(absf(glb.rotation.y)).is_equal_approx(PI / 2.0, 0.0001)


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


# ===== effective_base_props: per-model Tough enlarges the base for tokens/measuring =====
# The mesh stays natural-sized (fixed in _create_unit_model/create_model_from_properties);
# THIS is what tokens/range-rings/measuring read so they anchor to the actual enlarged base.

func test_effective_base_round_enlarged_by_tough() -> void:
	# 25 mm round + Tough(6) -> 60 mm base (max(25, 60)).
	var out := OPRArmyManager.effective_base_props({"base_size_round": 25}, 6)
	assert_int(out["base_size_round"]).is_equal(60)


func test_effective_base_no_tough_is_unchanged() -> void:
	var out := OPRArmyManager.effective_base_props({"base_size_round": 25}, 0)
	assert_int(out["base_size_round"]).is_equal(25)


func test_effective_base_low_tough_below_base_is_unchanged() -> void:
	# Tough(2) -> from_tough 0 -> max(32, 0) = 32, no growth.
	var out := OPRArmyManager.effective_base_props({"base_size_round": 32}, 2)
	assert_int(out["base_size_round"]).is_equal(32)


func test_effective_base_already_big_is_unchanged() -> void:
	# 80 mm round + Tough(6) (->60) -> stays 80 (never shrink).
	var out := OPRArmyManager.effective_base_props({"base_size_round": 80}, 6)
	assert_int(out["base_size_round"]).is_equal(80)


func test_effective_base_oval_scales_both_axes_by_ratio() -> void:
	# Oval 35x60 (long=60) + Tough(12) (->120): ratio 2.0 -> 70x120.
	var out := OPRArmyManager.effective_base_props(
		{"base_is_oval": true, "base_width_mm": 35, "base_depth_mm": 60}, 12)
	assert_int(int(out["base_width_mm"])).is_equal(70)
	assert_int(int(out["base_depth_mm"])).is_equal(120)


func test_effective_base_does_not_mutate_input() -> void:
	var original := {"base_size_round": 25}
	OPRArmyManager.effective_base_props(original, 6)
	assert_int(original["base_size_round"]).is_equal(25)  # copy, not in-place
