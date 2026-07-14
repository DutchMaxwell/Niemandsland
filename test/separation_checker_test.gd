extends GdUnitTestSuite
## Tests for SeparationChecker — OPR unit-separation distance math and the 1"
## "too close to a model of ANOTHER unit" hint trigger (GF/AoF Advanced Rules
## v3.5.1, p.7 "General Movement": models may never be within 1" of models from
## other units — ANY other unit, friendly included — unless charging). Exception
## matrix: ENEMY base contact = intentional melee, exempt; FRIENDLY other-unit
## contact has no Charge to justify it -> still a violation; SAME unit is exempt
## (coherency governs inside a unit).
##
## Geometry cases use explicit BaseShapes (no scene needed). Distances are authored
## in INCHES via the _round/_oval/_rect helpers, and edge_distance() returns inches,
## so expected values read directly. TOL is generous (0.01") — round-round and
## round-rect are exact; oval pairs use the documented centre-line approximation,
## exercised here along an axis where it is exact.

const INCH := 0.0254   # metres per inch
const TOL := 0.01      # inches


# ===== Helpers =====

func _round(cx_in: float, cz_in: float, r_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_round(Vector2(cx_in, cz_in) * INCH, r_in * INCH)


func _oval(cx_in: float, cz_in: float, yaw: float, sx_in: float, sz_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_oval(Vector2(cx_in, cz_in) * INCH, yaw, sx_in * INCH, sz_in * INCH)


func _rect(cx_in: float, cz_in: float, yaw: float, sx_in: float, sz_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_rect(Vector2(cx_in, cz_in) * INCH, yaw, sx_in * INCH, sz_in * INCH)


func _model_node(pos: Vector3, yaw: float = 0.0) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	node.global_position = pos
	node.rotation.y = yaw
	return node


# ===== Circle-Circle (exact) =====

func test_circle_circle_edge_distance() -> void:
	# Two 1"-diameter bases 3" centre-to-centre -> 2" edge gap.
	assert_float(SeparationChecker.edge_distance(_round(0, 0, 0.5), _round(3, 0, 0.5))).is_equal_approx(2.0, TOL)


func test_circle_circle_overlap_is_negative() -> void:
	# Centres 0.6" apart, radii 0.5" each -> -0.4" (overlap).
	assert_float(SeparationChecker.edge_distance(_round(0, 0, 0.5), _round(0.6, 0, 0.5))).is_equal_approx(-0.4, TOL)


# ===== Circle-Ellipse (directional; exact along an axis) =====

func test_circle_ellipse_along_major_axis() -> void:
	# Ellipse semi 1.0x0.5"; round r0.5" 3" away along the major (X) axis.
	# 3 - 1.0(ellipse) - 0.5(round) = 1.5".
	assert_float(SeparationChecker.edge_distance(_oval(0, 0, 0.0, 1.0, 0.5), _round(3, 0, 0.5))).is_equal_approx(1.5, TOL)


func test_circle_ellipse_along_minor_axis() -> void:
	# Same ellipse, round 2" away along the minor (Z) axis: 2 - 0.5 - 0.5 = 1.0".
	assert_float(SeparationChecker.edge_distance(_oval(0, 0, 0.0, 1.0, 0.5), _round(0, 2, 0.5))).is_equal_approx(1.0, TOL)


# ===== Ellipse-Ellipse (directional; exact along an axis) =====

func test_ellipse_ellipse_along_major_axis() -> void:
	# Two 1.0x0.5" ellipses 4" apart along X: 4 - 1 - 1 = 2".
	assert_float(SeparationChecker.edge_distance(_oval(0, 0, 0.0, 1.0, 0.5), _oval(4, 0, 0.0, 1.0, 0.5))).is_equal_approx(2.0, TOL)


func test_ellipse_ellipse_along_minor_axis() -> void:
	# Two 1.0x0.5" ellipses 3" apart along Z: 3 - 0.5 - 0.5 = 2".
	assert_float(SeparationChecker.edge_distance(_oval(0, 0, 0.0, 1.0, 0.5), _oval(0, 3, 0.0, 1.0, 0.5))).is_equal_approx(2.0, TOL)


# ===== Rect-Circle (exact closest point on rect) =====

func test_rect_circle_face() -> void:
	# Rect 1.0x0.5"; circle r0.5" 1.5" out along +Z. Closest rect point (0,0.5),
	# dist 1.0, minus r -> 0.5".
	assert_float(SeparationChecker.edge_distance(_rect(0, 0, 0.0, 1.0, 0.5), _round(0, 1.5, 0.5))).is_equal_approx(0.5, TOL)


func test_rect_circle_corner() -> void:
	# Circle out past a corner (3,2). Closest rect point is the corner (1,0.5):
	# dist hypot(2,1.5)=2.5, minus r0.5 -> 2.0". (Centre-line would differ — this
	# confirms true closest-point-on-rect handling.)
	assert_float(SeparationChecker.edge_distance(_rect(0, 0, 0.0, 1.0, 0.5), _round(3, 2, 0.5))).is_equal_approx(2.0, TOL)


func test_rect_circle_rotated() -> void:
	# Rect rotated 90°: its semi_z(0.5) now faces +X. Circle r0.5" at (1.5,0):
	# 1.5 - 0.5(rect extent) - 0.5(round) = 0.5".
	assert_float(SeparationChecker.edge_distance(_rect(0, 0, PI / 2.0, 1.0, 0.5), _round(1.5, 0, 0.5))).is_equal_approx(0.5, TOL)


func test_rect_circle_overlap_when_centre_inside() -> void:
	# Circle centre inside the rect -> closest point is the centre, gap = -radius.
	assert_float(SeparationChecker.edge_distance(_rect(0, 0, 0.0, 1.0, 0.5), _round(0, 0, 0.5))).is_equal_approx(-0.5, TOL)
	assert_bool(SeparationChecker.is_base_contact(_rect(0, 0, 0.0, 1.0, 0.5), _round(0, 0, 0.5))).is_true()


# ===== Rect-Rect (exact convex) =====

func test_rect_rect_faces() -> void:
	# Two 1.0x0.5" rects 4" apart along X: right face x=1, left face x=3 -> 2" gap.
	assert_float(SeparationChecker.edge_distance(_rect(0, 0, 0.0, 1.0, 0.5), _rect(4, 0, 0.0, 1.0, 0.5))).is_equal_approx(2.0, TOL)


func test_rect_rect_overlap_is_contact() -> void:
	# A spans x[-1,1], B spans x[0,2] -> overlap -> gap 0 -> base contact.
	assert_float(SeparationChecker.edge_distance(_rect(0, 0, 0.0, 1.0, 0.5), _rect(1, 0, 0.0, 1.0, 0.5))).is_equal_approx(0.0, TOL)
	assert_bool(SeparationChecker.is_base_contact(_rect(0, 0, 0.0, 1.0, 0.5), _rect(1, 0, 0.0, 1.0, 0.5))).is_true()


# ===== 1" threshold boundary =====

func test_at_or_above_one_inch_is_not_a_violation() -> void:
	# A gap of 1" or more is compliant (rule is "within 1"", i.e. strictly less).
	# Tested just clear of the exact boundary to stay off the float knife-edge.
	var a := _round(0, 0, 0.5)
	var b := _round(2.05, 0, 0.5)   # 2.05" centres, 0.5" radii -> gap 1.05"
	assert_float(SeparationChecker.edge_distance(a, b)).is_equal_approx(1.05, TOL)
	assert_bool(SeparationChecker.is_separation_violation(a, b)).is_false()


func test_just_under_one_inch_is_a_violation() -> void:
	var a := _round(0, 0, 0.5)
	var b := _round(1.9, 0, 0.5)   # gap 0.9"
	assert_bool(SeparationChecker.is_separation_violation(a, b)).is_true()


# ===== Melee exception (ENEMY base contact suppresses the warning) =====

func test_enemy_base_contact_suppresses_warning() -> void:
	# Touching an ENEMY (gap 0) = intentional Charge into melee -> contact yes,
	# violation no (contact_is_melee defaults to true = enemy semantics).
	var a := _round(0, 0, 0.5)
	var b := _round(1.0, 0, 0.5)   # gap 0.0"
	assert_bool(SeparationChecker.is_base_contact(a, b)).is_true()
	assert_bool(SeparationChecker.is_separation_violation(a, b)).is_false()
	assert_bool(SeparationChecker.is_separation_violation(a, b, true)).is_false()


func test_sub_one_inch_no_contact_warns() -> void:
	# Clearly within 1" but not touching -> warn (any other unit, enemy or friend).
	var a := _round(0, 0, 0.5)
	var b := _round(1.5, 0, 0.5)   # gap 0.5"
	assert_bool(SeparationChecker.is_base_contact(a, b)).is_false()
	assert_bool(SeparationChecker.is_separation_violation(a, b, true)).is_true()
	assert_bool(SeparationChecker.is_separation_violation(a, b, false)).is_true()


# ===== Friendly other unit (no legal contact — Charge only targets enemies) =====

func test_friendly_contact_is_a_violation() -> void:
	# Touching a FRIENDLY other unit: no Charge can justify it -> warn.
	var a := _round(0, 0, 0.5)
	var b := _round(1.0, 0, 0.5)   # gap 0.0" (contact)
	assert_bool(SeparationChecker.is_separation_violation(a, b, false)).is_true()


func test_friendly_overlap_is_a_violation() -> void:
	# Even overlapping friendly bases (negative gap) warn.
	var a := _round(0, 0, 0.5)
	var b := _round(0.6, 0, 0.5)   # gap -0.4"
	assert_bool(SeparationChecker.is_separation_violation(a, b, false)).is_true()


func test_friendly_sub_one_inch_warns() -> void:
	var a := _round(0, 0, 0.5)
	var b := _round(1.5, 0, 0.5)   # gap 0.5"
	assert_bool(SeparationChecker.is_separation_violation(a, b, false)).is_true()


func test_friendly_at_or_above_one_inch_is_compliant() -> void:
	var a := _round(0, 0, 0.5)
	var b := _round(2.05, 0, 0.5)   # gap 1.05"
	assert_bool(SeparationChecker.is_separation_violation(a, b, false)).is_false()


func test_base_contact_epsilon_parameter() -> void:
	var a := _round(0, 0, 0.5)
	var b := _round(1.5, 0, 0.5)   # gap 0.5"
	assert_bool(SeparationChecker.is_base_contact(a, b, 0.6)).is_true()   # within a wide epsilon
	assert_bool(SeparationChecker.is_base_contact(a, b)).is_false()       # default 0.05"


# ===== Enemy vs friendly classification (mocked affiliations) =====
# Drives the melee contact-exemption and the red/amber tint; also kept as API for
# the solo-AI movement planner.

func test_are_enemy_players_different_known_slots() -> void:
	assert_bool(SeparationChecker.are_enemy_players(1, 2)).is_true()
	assert_bool(SeparationChecker.are_enemy_players(2, 3)).is_true()


func test_same_army_is_not_enemy() -> void:
	assert_bool(SeparationChecker.are_enemy_players(1, 1)).is_false()
	assert_bool(SeparationChecker.are_enemy_players(2, 2)).is_false()


func test_unknown_affiliation_never_enemy() -> void:
	# Missing / non-positive player_id = unknown -> never a false warning.
	assert_bool(SeparationChecker.are_enemy_players(1, 0)).is_false()
	assert_bool(SeparationChecker.are_enemy_players(0, 2)).is_false()
	assert_bool(SeparationChecker.are_enemy_players(-1, 2)).is_false()
	assert_bool(SeparationChecker.are_enemy_players(0, 0)).is_false()


# ===== Unit identity (the rule's scope: "models from other units") =====

func test_are_different_units_two_units() -> void:
	var a := GameUnit.new()
	var b := GameUnit.new()
	assert_bool(SeparationChecker.are_different_units(a, b)).is_true()


func test_same_unit_is_not_different() -> void:
	# Same-unit models are exempt — coherency governs INSIDE a unit.
	var a := GameUnit.new()
	assert_bool(SeparationChecker.are_different_units(a, a)).is_false()


func test_null_units_are_not_comparable() -> void:
	# Unknown affiliation -> no warning rather than a false warning.
	var a := GameUnit.new()
	assert_bool(SeparationChecker.are_different_units(a, null)).is_false()
	assert_bool(SeparationChecker.are_different_units(null, a)).is_false()
	assert_bool(SeparationChecker.are_different_units(null, null)).is_false()


func test_attached_hero_resolves_to_host_unit() -> void:
	# A joined Hero counts as part of its host unit (coherency requires it within
	# 1" of the host, so the pair must never be flagged as "different units").
	var host := GameUnit.new()
	var hero := GameUnit.new()
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_object(SeparationChecker.effective_unit(hero)).is_same(host)
	assert_bool(SeparationChecker.are_different_units(hero, host)).is_false()
	# ...but the hero IS a different unit to any third unit.
	var third := GameUnit.new()
	assert_bool(SeparationChecker.are_different_units(hero, third)).is_true()


# ===== Combined decision (other unit AND within 1", per exception matrix) =====

func test_exception_matrix_within_band_and_contact() -> void:
	var band := _round(1.5, 0, 0.5)     # 0.5" gap to `a` — inside the band
	var touching := _round(1.0, 0, 0.5)  # 0.0" gap to `a` — base contact
	var a := _round(0, 0, 0.5)
	# Sub-1" without contact warns for BOTH enemy and friendly other units.
	assert_bool(SeparationChecker.is_separation_violation(a, band, true)).is_true()
	assert_bool(SeparationChecker.is_separation_violation(a, band, false)).is_true()
	# Contact: exempt vs an enemy (melee), still a violation vs a friend.
	assert_bool(SeparationChecker.is_separation_violation(a, touching, true)).is_false()
	assert_bool(SeparationChecker.is_separation_violation(a, touching, false)).is_true()


# ===== Null safety =====

func test_null_shapes_are_safe() -> void:
	assert_float(SeparationChecker.edge_distance(null, _round(0, 0, 0.5))).is_equal(INF)
	assert_bool(SeparationChecker.is_base_contact(null, null)).is_false()
	assert_bool(SeparationChecker.is_separation_violation(_round(0, 0, 0.5), null)).is_false()


# ===== BaseShape helpers =====

func test_bounding_radius_encloses_base() -> void:
	assert_float(SeparationChecker.BaseShape.make_round(Vector2.ZERO, 0.02).bounding_radius()).is_equal_approx(0.02, 0.0001)
	# Oval/rect enclosing radius = hypot(semi_x, semi_z).
	var expected := sqrt(0.03 * 0.03 + 0.02 * 0.02)
	assert_float(SeparationChecker.BaseShape.make_oval(Vector2.ZERO, 0.0, 0.03, 0.02).bounding_radius()).is_equal_approx(expected, 0.0001)


# ===== shape_for_model extractor (ownership / base seam) =====

func test_shape_for_model_round_base() -> void:
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": 40, "base_is_oval": false, "player_id": 1}
	var model := ModelInstance.new()
	model.unit = unit
	model.is_alive = true
	model.properties = {"tough": 1}
	model.node = _model_node(Vector3(0.1, 0.0, 0.2))

	var shape := SeparationChecker.shape_for_model(model)
	assert_object(shape).is_not_null()
	assert_int(shape.kind).is_equal(SeparationChecker.BaseShape.Kind.ROUND)
	assert_vector(shape.center).is_equal_approx(Vector2(0.1, 0.2), Vector2(0.001, 0.001))
	# Expected radius derived exactly as the extractor does (per-model Tough scale).
	var scale := float(OPRArmyManager.model_base_long_mm(40, 1)) / 40.0
	var expected_r := (40 / 2.0) * 0.001 * scale
	assert_float(shape.radius).is_equal_approx(expected_r, 0.0005)


func test_shape_for_model_oval_base_with_yaw() -> void:
	var unit := GameUnit.new()
	unit.unit_properties = {"base_is_oval": true, "base_width_mm": 60, "base_depth_mm": 35, "player_id": 2}
	var model := ModelInstance.new()
	model.unit = unit
	model.is_alive = true
	model.properties = {"tough": 1}
	model.node = _model_node(Vector3(0.0, 0.0, 0.0), 0.5)

	var shape := SeparationChecker.shape_for_model(model)
	assert_object(shape).is_not_null()
	assert_int(shape.kind).is_equal(SeparationChecker.BaseShape.Kind.OVAL)
	assert_float(shape.yaw).is_equal_approx(0.5, 0.001)
	var scale := float(OPRArmyManager.model_base_long_mm(60, 1)) / 60.0
	assert_float(shape.semi_x).is_equal_approx((60 / 2.0) * 0.001 * scale, 0.0005)
	assert_float(shape.semi_z).is_equal_approx((35 / 2.0) * 0.001 * scale, 0.0005)


func test_shape_for_model_missing_node_returns_null() -> void:
	var model := ModelInstance.new()
	model.node = null
	assert_object(SeparationChecker.shape_for_model(model)).is_null()


# ===== Retreat-ruler witness points (nearest_edge_points) =====
## The ruler LABEL must always agree with the distance math, so gap_inches ==
## edge_distance for every shape kind; the witness SEGMENT reproduces that gap exactly
## for round-round and round-rect (the exact branches).

func test_nearest_edge_points_gap_matches_edge_distance_round() -> void:
	var a := _round(0, 0, 0.5)
	var b := _round(3, 0, 0.5)  # 2" gap
	var pts := SeparationChecker.nearest_edge_points(a, b)
	assert_float(pts["gap_inches"]).is_equal_approx(SeparationChecker.edge_distance(a, b), TOL)
	# Exact for round-round: the witness segment length equals the gap.
	var seg := (pts["to"] as Vector2).distance_to(pts["from"]) / INCH
	assert_float(seg).is_equal_approx(2.0, TOL)


func test_nearest_edge_points_gap_matches_edge_distance_oval() -> void:
	var a := _oval(0, 0, 0.0, 0.8, 0.4)
	var b := _oval(3, 0, 0.0, 0.8, 0.4)
	var pts := SeparationChecker.nearest_edge_points(a, b)
	assert_float(pts["gap_inches"]).is_equal_approx(SeparationChecker.edge_distance(a, b), TOL)


func test_nearest_edge_points_gap_matches_edge_distance_rect() -> void:
	# round-vs-rect (an exact branch): 1"-radius circle, 1"x1" half-extent rect, 4" apart.
	var round_base := _round(0, 0, 1.0)
	var rect := _rect(4, 0, 0.0, 1.0, 1.0)
	var pts := SeparationChecker.nearest_edge_points(round_base, rect)
	var gap := SeparationChecker.edge_distance(round_base, rect)
	assert_float(pts["gap_inches"]).is_equal_approx(gap, TOL)
	# Exact branch: witness segment length reproduces the gap (2" here: 4 - 1 - 1).
	var seg := (pts["to"] as Vector2).distance_to(pts["from"]) / INCH
	assert_float(seg).is_equal_approx(2.0, TOL)


func test_nearest_edge_points_witness_lies_on_boundaries_round() -> void:
	# Each witness point sits on its own base's boundary (distance from centre == radius).
	var a := _round(0, 0, 0.5)
	var b := _round(2, 0, 0.5)
	var pts := SeparationChecker.nearest_edge_points(a, b)
	assert_float((pts["from"] as Vector2).distance_to(a.center) / INCH).is_equal_approx(0.5, TOL)
	assert_float((pts["to"] as Vector2).distance_to(b.center) / INCH).is_equal_approx(0.5, TOL)


func test_nearest_edge_points_concentric_is_degenerate() -> void:
	# Coincident centres -> from == to (caller hides the zero-length line).
	var a := _round(0, 0, 0.5)
	var b := _round(0, 0, 0.5)
	var pts := SeparationChecker.nearest_edge_points(a, b)
	assert_float((pts["from"] as Vector2).distance_to(pts["to"] as Vector2)).is_equal_approx(0.0, 0.0001)
