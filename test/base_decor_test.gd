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

func test_round_rim_is_a_beveled_frame_without_a_cap_under_the_terrain() -> void:
	# The black rim is a beveled WALL (full outline at the bottom, inset outline at the top) plus a
	# flat annular top cap. Crucially it has NO cap under the terrain quad — the previous full top
	# face z-fought the terrain top (a dark shimmer ring). Verify the bevel and the missing centre cap.
	var radius := 0.0125
	var base := _round_base(false)  # 25 mm round base, radius 0.0125 m
	var rim := base.get_node("BaseRim") as MeshInstance3D
	var verts: PackedVector3Array = rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_greater(0)
	var bottom_max := 0.0
	var top_max := 0.0
	var top_min := 1.0e9
	for v in verts:
		var r := Vector2(v.x, v.z).length()
		if v.y < BaseDecor.BASE_HEIGHT_M * 0.5:   # bottom ring (y ~ 0)
			bottom_max = maxf(bottom_max, r)
		else:                                       # top-level ring/cap (y ~ BASE_HEIGHT)
			top_max = maxf(top_max, r)
			top_min = minf(top_min, r)
	# Bevel: the top outline insets from the full bottom outline, but only subtly (> 85 %).
	assert_float(top_max).is_less(bottom_max)
	assert_float(top_max).is_greater(bottom_max * 0.85)
	# No cap under the terrain: the flat top annulus starts at TOP_RADIUS_RATIO, never the centre.
	assert_float(top_min).is_greater(radius * BaseDecor.TOP_RADIUS_RATIO * 0.9)


func test_round_top_is_a_quad_with_centred_shape_uv_for_discard() -> void:
	# The terrain top is a flat QUAD (renders like a PlaneMesh, which the sun answers identically —
	# a single-apex fan measured markedly darker). UV is a centred shape coordinate: the shader
	# discards fragments with length(UV) > 1, so a round base's quad corners (length sqrt(2)) are
	# clipped and the inscribed circle remains.
	var base := _round_base(false)
	var top := base.get_node("BaseTop") as MeshInstance3D
	var arrays := top.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_int(verts.size()).is_equal(4)          # a quad (two triangles)
	var max_uv_len := 0.0
	for uv in uvs:
		max_uv_len = maxf(max_uv_len, uv.length())
	assert_float(max_uv_len).is_equal_approx(sqrt(2.0), 0.001)   # corners at sqrt(2) => discarded


func test_square_top_uv_never_exceeds_one_so_the_full_square_shows() -> void:
	# A square base keeps its full square terrain: its quad UVs are pre-scaled by 1/sqrt(2) so no
	# corner reaches length 1 and the shader never discards.
	var base: Node3D = auto_free(BaseDecor.build_base(false, true, 0.025, 0.025, 0.0125, Color.RED, false, null))
	var top := base.get_node("BaseTop") as MeshInstance3D
	var uvs: PackedVector2Array = top.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_int(uvs.size()).is_equal(4)
	for uv in uvs:
		assert_float(uv.length()).is_less_equal(1.0001)


func test_top_mesh_carries_a_world_aligned_tangent_for_the_detail_normal() -> void:
	# The terrain-top shader applies the board's detail NORMAL_MAP so the base catches the same sun
	# glints (identical texture => identical brightness); that needs a tangent frame. Every quad
	# vertex carries a world-aligned +X tangent (binormal sign +1) matching the table's PlaneMesh.
	var base := _round_base(false)
	var top := base.get_node("BaseTop") as MeshInstance3D
	var arrays := top.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	assert_int(tangents.size()).is_equal(verts.size() * 4)   # (x, y, z, w) per vertex
	assert_float(tangents[0]).is_equal_approx(1.0, 0.0001)
	assert_float(tangents[1]).is_equal_approx(0.0, 0.0001)
	assert_float(tangents[2]).is_equal_approx(0.0, 0.0001)
	assert_float(tangents[3]).is_equal_approx(1.0, 0.0001)


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


func test_square_base_rim_is_a_frame_without_a_top_face_under_the_terrain() -> void:
	# Regiment (square) bases use the same beveled-frame rim (a rectangular wall + annular top cap),
	# not a solid box whose full top face would z-fight the terrain quad. Verify no top-level vertex
	# sits under the terrain (the cap's inner edge stays at TOP_RADIUS_RATIO, off-centre).
	var base: Node3D = auto_free(BaseDecor.build_base(false, true, 0.025, 0.025, 0.0125, Color.RED, false, null))
	var rim := base.get_node("BaseRim") as MeshInstance3D
	var verts: PackedVector3Array = rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_greater(0)
	var top_min := 1.0e9
	for v in verts:
		if v.y > BaseDecor.BASE_HEIGHT_M * 0.5:
			top_min = minf(top_min, maxf(absf(v.x), absf(v.z)))
	# Half-width 0.0125; the cap's inner edge is at TOP_RADIUS_RATIO -> ~0.01075 m, well off-centre.
	assert_float(top_min).is_greater(0.0125 * BaseDecor.TOP_RADIUS_RATIO * 0.9)
