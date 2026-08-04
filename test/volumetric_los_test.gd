extends GdUnitTestSuite
## VolumetricLos is the ONE volumetric sight truth (elevation program, Phase A): model heights come from
## the official base-size table and every piece of terrain is an upright 3D volume. These prove the height
## table and the slab-clip-then-2D geometry every later sight query rides on. Everything is built in
## INCHES here and converted with K — the module itself only ever sees metres.

const K := VolumetricLos.INCHES_TO_METERS


func _p(x_in: float, y_in: float, z_in: float) -> Vector3:
	return Vector3(x_in, y_in, z_in) * K


func _box(cx_in: float, cz_in: float, hx_in: float, hz_in: float, y0_in: float, y1_in: float) -> Dictionary:
	return {"kind": "box", "c": Vector2(cx_in, cz_in) * K, "he": Vector2(hx_in, hz_in) * K,
		"yaw": 0.0, "y0": y0_in * K, "y1": y1_in * K, "solid": true}


func _cyl(cx_in: float, cz_in: float, r_in: float, y0_in: float, y1_in: float) -> Dictionary:
	return {"kind": "cyl", "c": Vector2(cx_in, cz_in) * K, "r": r_in * K,
		"y0": y0_in * K, "y1": y1_in * K, "solid": true}


func test_base_height_table_matches_the_official_volumetric_sizes() -> void:
	# P1: the height of a model is a function of its BASE, never of its mesh (meshes are optional
	# per-client content — a mesh-derived height would desync multiplayer).
	assert_float(VolumetricLos.height_in_for_base_mm(25.0)).is_equal_approx(1.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(32.0)).is_equal_approx(1.25, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(40.0)).is_equal_approx(1.5, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(50.0)).is_equal_approx(2.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(60.0)).is_equal_approx(3.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(100.0)).is_equal_approx(4.0, 0.0001)


func test_base_height_interpolates_clamps_and_averages_ovals() -> void:
	# Between two rows: LINEAR. 28 mm sits 3/7 of the way from 25 mm (1") to 32 mm (1.25").
	assert_float(VolumetricLos.height_in_for_base_mm(28.0)).is_equal_approx(1.1071, 0.0001)
	# Outside the table: clamp to the first / last row (no negative or giant models).
	assert_float(VolumetricLos.height_in_for_base_mm(20.0)).is_equal_approx(1.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(120.0)).is_equal_approx(4.0, 0.0001)
	# Oval bases enter the table through their MEAN axis: 60x35 counts as 47.5 mm -> 1.875".
	assert_float(VolumetricLos.oval_effective_mm(60.0, 35.0)).is_equal_approx(47.5, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(47.5)).is_equal_approx(1.875, 0.0001)


func test_box_volume_is_clipped_by_its_y_slab_before_the_2d_test() -> void:
	var box := _box(0.0, 0.0, 1.5, 1.5, 0.0, 2.0)   # 3x3", 2" tall, standing on the table
	# Straight through at 1": hit.
	assert_bool(VolumetricLos.segment_hits_box(_p(-6, 1, 0), _p(6, 1, 0), box)).is_true()
	# Straight over the top at 3": miss — this is the elevation win.
	assert_bool(VolumetricLos.segment_hits_box(_p(-6, 3, 0), _p(6, 3, 0), box)).is_false()
	# Steep climb: the UNCLIPPED XZ projection crosses the footprint, but the part inside the slab
	# (t <= 1/6, x <= -4") does not — so slab-clip FIRST, 2D test second.
	assert_bool(VolumetricLos.segment_hits_box(_p(-6, 0, 0), _p(6, 12, 0), box)).is_false()


func test_cylinder_volume_is_clipped_by_its_y_slab_before_the_2d_test() -> void:
	var cyl := _cyl(0.0, 0.0, 1.5, 0.0, 2.0)   # r = 1.5", 2" tall
	assert_bool(VolumetricLos.segment_hits_cyl(_p(-6, 1, 0), _p(6, 1, 0), cyl)).is_true()
	assert_bool(VolumetricLos.segment_hits_cyl(_p(-6, 3, 0), _p(6, 3, 0), cyl)).is_false()
	assert_bool(VolumetricLos.segment_hits_cyl(_p(-6, 0, 0), _p(6, 12, 0), cyl)).is_false()
