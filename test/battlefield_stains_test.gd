extends GdUnitTestSuite
## BattlefieldStains: the blood pool (infantry) / oil pool + fires (vehicle) left where a
## model was removed (issue #60), sized to the base. Pure node-building; seeded for parity.

const BattlefieldStainsScript = preload("res://scripts/battlefield_stains.gd")


func _stains():
	return auto_free(BattlefieldStainsScript.new())


func _disc(node: Node3D) -> MeshInstance3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			return c as MeshInstance3D
	return null


func _fire_count(node: Node3D) -> int:
	var n := 0
	for c in node.get_children():
		if c is FireProp:
			n += 1
	return n


func test_blood_stain_is_one_disc_no_fire() -> void:
	var s = _stains()
	s.add_stain(Vector3(1.0, 0.0, 2.0), 0.016, false, 42)
	assert_int(_fire_count(s)).is_equal(0)
	var disc := _disc(s)
	assert_object(disc).is_not_null()
	var mat := disc.material_override as StandardMaterial3D
	assert_object(mat.albedo_color).is_equal(BattlefieldStainsScript.BLOOD_COLOR)


func test_vehicle_stain_is_oil_disc_plus_1_to_3_fires() -> void:
	var s = _stains()
	s.add_stain(Vector3.ZERO, 0.03, true, 7)
	var disc := _disc(s)
	assert_object((disc.material_override as StandardMaterial3D).albedo_color) \
		.is_equal(BattlefieldStainsScript.OIL_COLOR)
	assert_int(_fire_count(s)).is_between(
		BattlefieldStainsScript.VEHICLE_FIRE_MIN, BattlefieldStainsScript.VEHICLE_FIRE_MAX)


func test_disc_radius_matches_the_base() -> void:
	var s = _stains()
	s.add_stain(Vector3.ZERO, 0.025, false, 1)
	var mesh := _disc(s).mesh as CylinderMesh
	assert_float(mesh.top_radius).is_equal_approx(0.025, 0.0001)


func test_tiny_base_clamped_to_minimum() -> void:
	var s = _stains()
	s.add_stain(Vector3.ZERO, 0.0, false, 1)  # degenerate base
	var mesh := _disc(s).mesh as CylinderMesh
	assert_float(mesh.top_radius).is_equal_approx(BattlefieldStainsScript.STAIN_MIN_RADIUS_M, 0.0001)


func test_fire_count_deterministic_per_seed() -> void:
	var a = _stains(); a.add_stain(Vector3.ZERO, 0.03, true, 99)
	var b = _stains(); b.add_stain(Vector3.ZERO, 0.03, true, 99)
	assert_int(_fire_count(a)).is_equal(_fire_count(b))
