extends GdUnitTestSuite
## Tests for SeparationZone — the 1"-band ZONE-WALL geometry around a unit (GF/AoF
## Advanced Rules v3.5.1, p.7 "General Movement"). Covers the per-shape outline
## (round/oval/rect), the MERGED union of overlapping vs disjoint members (ONE contour
## per cluster, not overlapping rings), and the band triangle soup: a point half a band
## out is inside the wall, the unit's interior (the hole) and a point beyond the band
## are not. Shapes are authored in INCHES via helpers; geometry runs in metres.

const INCH := 0.0254            # metres per inch
const BAND := 0.0254            # 1" band width in metres
const TOL := 0.02               # inches


# ===== Helpers =====

func _round(cx_in: float, cz_in: float, r_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_round(Vector2(cx_in, cz_in) * INCH, r_in * INCH)


func _oval(cx_in: float, cz_in: float, yaw: float, sx_in: float, sz_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_oval(Vector2(cx_in, cz_in) * INCH, yaw, sx_in * INCH, sz_in * INCH)


func _rect(cx_in: float, cz_in: float, yaw: float, sx_in: float, sz_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_rect(Vector2(cx_in, cz_in) * INCH, yaw, sx_in * INCH, sz_in * INCH)


## World-XZ point in metres from inch coordinates.
func _p(x_in: float, z_in: float) -> Vector2:
	return Vector2(x_in, z_in) * INCH


func _triangle_area(tris: PackedVector2Array) -> float:
	var area := 0.0
	var count := tris.size() / 3
	for t in range(count):
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		area += absf((b - a).cross(c - a)) * 0.5
	return area


# ===== Per-shape outline =====

func test_round_polygon_lies_on_circle() -> void:
	var poly := SeparationZone.polygon_for_shape(_round(0, 0, 0.5))
	assert_int(poly.size()).is_equal(SeparationZone.ARC_SEGMENTS)
	for v in poly:
		assert_float(v.length()).is_equal_approx(0.5 * INCH, 0.001)


func test_rect_polygon_has_four_corners() -> void:
	var poly := SeparationZone.polygon_for_shape(_rect(0, 0, 0.0, 1.0, 0.5))
	assert_int(poly.size()).is_equal(4)
	# Corners at (±1, ±0.5)".
	for v in poly:
		assert_float(absf(v.x)).is_equal_approx(1.0 * INCH, 0.001)
		assert_float(absf(v.y)).is_equal_approx(0.5 * INCH, 0.001)


# ===== Merged union (one contour per cluster) =====

func test_overlapping_members_merge_to_one_loop() -> void:
	var polys := [
		SeparationZone.polygon_for_shape(_round(0, 0, 0.5)),
		SeparationZone.polygon_for_shape(_round(0.6, 0, 0.5)),
	]
	assert_int(SeparationZone.union_solid_loops(polys).size()).is_equal(1)


func test_disjoint_members_stay_two_loops() -> void:
	var polys := [
		SeparationZone.polygon_for_shape(_round(0, 0, 0.5)),
		SeparationZone.polygon_for_shape(_round(3, 0, 0.5)),
	]
	assert_int(SeparationZone.union_solid_loops(polys).size()).is_equal(2)


func test_three_in_a_row_merge_to_one_loop() -> void:
	# A bridges nothing to C directly, but B overlaps both -> one fused contour.
	var polys := [
		SeparationZone.polygon_for_shape(_round(0, 0, 0.5)),
		SeparationZone.polygon_for_shape(_round(1.6, 0, 0.5)),  # C
		SeparationZone.polygon_for_shape(_round(0.8, 0, 0.5)),  # B, bridges A & C
	]
	assert_int(SeparationZone.union_solid_loops(polys).size()).is_equal(1)


# ===== Band containment: round =====

func test_round_band_contains_midband_point() -> void:
	var tris := SeparationZone.unit_band_triangles([_round(0, 0, 0.5)])
	assert_bool(tris.size() >= 3).is_true()
	# Edge at 0.5", band out to ~1.5": a point 1.0" from centre is mid-band.
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(1.0, 0))).is_true()


func test_round_band_excludes_interior_and_far() -> void:
	var tris := SeparationZone.unit_band_triangles([_round(0, 0, 0.5)])
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0, 0))).is_false()      # hole
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(2.0, 0))).is_false()    # beyond band


func test_round_band_area_matches_annulus() -> void:
	# Analytic annulus pi((r+w)^2 - r^2), r=0.5" w=1" -> pi*2 sq in, in m^2.
	var tris := SeparationZone.unit_band_triangles([_round(0, 0, 0.5)])
	var expected := PI * (1.5 * 1.5 - 0.5 * 0.5) * INCH * INCH
	assert_float(_triangle_area(tris)).is_equal_approx(expected, expected * 0.15)


# ===== Band containment: oval =====

func test_oval_band_contains_points_off_both_axes() -> void:
	var tris := SeparationZone.unit_band_triangles([_oval(0, 0, 0.0, 1.0, 0.5)])
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(1.5, 0))).is_true()   # 0.5" past major edge
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0, 1.0))).is_true()   # 0.5" past minor edge
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0, 0))).is_false()    # hole
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(3.0, 0))).is_false()  # far


# ===== Band containment: rect (regiment tray) =====

func test_rect_band_hugs_faces() -> void:
	var tris := SeparationZone.unit_band_triangles([_rect(0, 0, 0.0, 1.0, 0.5)])
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0, 1.0))).is_true()   # 0.5" past +Z face
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(1.5, 0))).is_true()   # 0.5" past +X face
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0, 0))).is_false()    # hole
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0, 2.0))).is_false()  # far


# ===== Band of a merged cluster =====

func test_merged_band_excludes_waist_includes_flanks() -> void:
	var shapes := [_round(0, 0, 0.5), _round(0.6, 0, 0.5)]  # overlapping pair
	var tris := SeparationZone.unit_band_triangles(shapes)
	assert_bool(tris.size() >= 3).is_true()
	# The waist (0.3,0) is INSIDE the merged footprint -> a hole, not band.
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(0.3, 0))).is_false()
	# 0.4" beyond the left edge (-0.5) and the right edge (1.1) -> band.
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(-0.9, 0))).is_true()
	assert_bool(SeparationZone.triangles_contain_point(tris, _p(1.5, 0))).is_true()


# ===== Degenerate inputs =====

func test_empty_shapes_yields_no_triangles() -> void:
	assert_int(SeparationZone.unit_band_triangles([]).size()).is_equal(0)
