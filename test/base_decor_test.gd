extends GdUnitTestSuite
## BaseDecor — "perfectly based" miniature bases: ring-vs-no-ring assignment, shared-material
## caching, and the procedural rim/top/ring geometry (bevel + vignette UV). Pure/headless.


# ===== Ring assignment (solo -> ring, unit member -> no ring) =====

func test_solo_model_gets_a_ring() -> void:
	# A unit of one (hero / monster / loose single model) is the one-model equivalent of a
	# multi-model unit's boundary rubberband, so it carries the affiliation ring.
	assert_bool(BaseDecor.should_ring(1)).is_true()


func test_multi_model_unit_member_gets_no_ring() -> void:
	# Members of a multi-model unit have NO ring — their affiliation is the boundary rubberband.
	assert_bool(BaseDecor.should_ring(2)).is_false()
	assert_bool(BaseDecor.should_ring(5)).is_false()
	assert_bool(BaseDecor.should_ring(20)).is_false()


func test_degenerate_zero_size_is_treated_as_solo() -> void:
	assert_bool(BaseDecor.should_ring(0)).is_true()


# ===== Shared materials (one rim, one ring per player colour) =====

func test_rim_material_is_a_single_shared_instance() -> void:
	assert_object(BaseDecor.rim_material()).is_same(BaseDecor.rim_material())


func test_ring_material_is_cached_per_colour() -> void:
	var blue := Color(0.20, 0.40, 0.90)
	var red := Color(0.90, 0.20, 0.20)
	# Same colour -> same shared material; different colour -> different material.
	assert_object(BaseDecor.ring_material(blue)).is_same(BaseDecor.ring_material(blue))
	assert_object(BaseDecor.ring_material(blue)).is_not_same(BaseDecor.ring_material(red))
	# The ring uses the requested (player) colour as its albedo — the rubberband's colour source.
	assert_that(BaseDecor.ring_material(blue).albedo_color).is_equal(blue)


# ===== Base assembly structure =====

func _round_base(is_solo: bool) -> Node3D:
	# 25 mm round base (radius 12.5 mm = 0.0125 m).
	return auto_free(BaseDecor.build_base(false, false, 0.0, 0.0, 0.0125, Color(0.2, 0.4, 0.9), is_solo, null))


func test_solo_base_has_rim_top_and_ring() -> void:
	var base := _round_base(true)
	assert_object(base.get_node_or_null("BaseRim")).is_not_null()
	assert_object(base.get_node_or_null("BaseTop")).is_not_null()
	assert_object(base.get_node_or_null("AffiliationRing")).is_not_null()


func test_unit_member_base_has_no_ring() -> void:
	var base := _round_base(false)
	assert_object(base.get_node_or_null("BaseRim")).is_not_null()
	assert_object(base.get_node_or_null("BaseTop")).is_not_null()
	assert_object(base.get_node_or_null("AffiliationRing")).is_null()


func test_decor_meshes_are_flagged_shared_so_the_dimmer_skips_them() -> void:
	# The lock dimmer (object_manager) must never mutate a shared material; every decor mesh is tagged.
	var base := _round_base(true)
	for name in ["BaseRim", "BaseTop", "AffiliationRing"]:
		var mi := base.get_node_or_null(name) as MeshInstance3D
		assert_object(mi).is_not_null()
		assert_bool(mi.has_meta(BaseDecor.SHARED_MATERIAL_META)).is_true()


# ===== Geometry: bevel + vignette UV =====

func test_round_rim_is_a_beveled_frustum() -> void:
	# The black rim is a shallow frustum: its top radius is smaller than the bottom radius, giving the
	# slightly-chamfered tabletop-base edge.
	var base := _round_base(false)
	var rim := base.get_node("BaseRim") as MeshInstance3D
	assert_object(rim.mesh).is_instanceof(CylinderMesh)
	var cyl := rim.mesh as CylinderMesh
	assert_float(cyl.top_radius).is_less(cyl.bottom_radius)
	# The bevel is subtle, not a spike: top radius stays above 85% of the bottom radius.
	assert_float(cyl.top_radius).is_greater(cyl.bottom_radius * 0.85)


func test_top_mesh_bakes_the_rim_vignette_into_uv_x() -> void:
	# UV.x is the vignette coordinate: 0 at the centre vertex, 1 at every rim vertex.
	var base := _round_base(false)
	var top := base.get_node("BaseTop") as MeshInstance3D
	var arrays := top.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_int(verts.size()).is_greater(3)
	var saw_centre := false
	var saw_rim := false
	for i in range(verts.size()):
		if verts[i].length() < 0.00001:
			assert_float(uvs[i].x).is_equal_approx(0.0, 0.0001)
			saw_centre = true
		else:
			assert_float(uvs[i].x).is_equal_approx(1.0, 0.0001)
			saw_rim = true
	assert_bool(saw_centre).is_true()
	assert_bool(saw_rim).is_true()


func test_top_disc_sits_inside_the_rim_so_a_black_border_shows() -> void:
	# The terrain top radius (TOP_RADIUS_RATIO) is inside the rim-cap radius (RIM_TOP_RATIO), leaving
	# the flat black rim ring the affiliation ring lands on.
	assert_float(BaseDecor.TOP_RADIUS_RATIO).is_less(BaseDecor.RIM_TOP_RATIO)
	assert_float(BaseDecor.RIM_TOP_RATIO).is_less(1.0)


func test_ring_annulus_lies_between_the_top_edge_and_the_rim_cap() -> void:
	# Every ring vertex sits in the [TOP_RADIUS_RATIO .. RIM_TOP_RATIO] band of the base radius.
	var radius := 0.0125
	var base: Node3D = auto_free(BaseDecor.build_base(false, false, 0.0, 0.0, radius, Color.RED, true, null))
	var ring := base.get_node("AffiliationRing") as MeshInstance3D
	var verts: PackedVector3Array = ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_greater(0)
	var lo := radius * BaseDecor.TOP_RADIUS_RATIO - 0.0001
	var hi := radius * BaseDecor.RIM_TOP_RATIO + 0.0001
	for v in verts:
		var r := Vector2(v.x, v.z).length()
		assert_float(r).is_between(lo, hi)


func test_square_base_uses_a_box_rim() -> void:
	# Regiment (square) bases use a flat black box rim; the inset terrain top leaves the black border.
	var base: Node3D = auto_free(BaseDecor.build_base(false, true, 0.025, 0.025, 0.0125, Color.RED, false, null))
	var rim := base.get_node("BaseRim") as MeshInstance3D
	assert_object(rim.mesh).is_instanceof(BoxMesh)
