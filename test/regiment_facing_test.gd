extends GdUnitTestSuite
## RegimentFacingVisualizer.front_arc_contains: the pure facing test behind the
## regiment facing display aid (arrow/wedge) and the measure tool's front/flank label.
## Pure/static — no nodes, no scene. Display only; no game rule is enforced.

const HALF := PI / 2.0  # 90° half-angle -> the forward 180° half-plane (the "front")


# ===== forward half-plane (90° half-angle) =====


func test_point_directly_ahead_is_front() -> void:
	# Facing +Z, point straight ahead.
	var inside := RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2.ZERO, Vector2(0, 5), HALF)
	assert_bool(inside).is_true()


func test_point_directly_behind_is_not_front() -> void:
	var inside := RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2.ZERO, Vector2(0, -5), HALF)
	assert_bool(inside).is_false()


func test_point_dead_abeam_is_on_the_boundary_and_counts_as_front() -> void:
	# Exactly 90° off facing: cos = 0 >= cos(90°) = 0, so the boundary is inclusive.
	var inside := RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2.ZERO, Vector2(5, 0), HALF)
	assert_bool(inside).is_true()


func test_point_just_behind_the_beam_is_flank_rear() -> void:
	var inside := RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2.ZERO, Vector2(5, -0.1), HALF)
	assert_bool(inside).is_false()


# ===== apex offset + arbitrary facing =====


func test_uses_the_apex_not_the_origin() -> void:
	# Apex at (10, 10) facing +X; a point further along +X is in front...
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		Vector2(1, 0), Vector2(10, 10), Vector2(15, 10), HALF)).is_true()
	# ...and a point back toward -X from the apex is behind.
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		Vector2(1, 0), Vector2(10, 10), Vector2(5, 10), HALF)).is_false()


func test_diagonal_facing_classifies_by_angle() -> void:
	var facing := Vector2(1, 1)  # 45° between +X and +Z
	# A point along the facing diagonal is front.
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		facing, Vector2.ZERO, Vector2(3, 3), HALF)).is_true()
	# A point along the opposite diagonal is rear.
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		facing, Vector2.ZERO, Vector2(-3, -3), HALF)).is_false()


# ===== degenerate inputs =====


func test_point_at_apex_counts_as_front() -> void:
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2(2, 2), Vector2(2, 2), HALF)).is_true()


func test_zero_facing_is_never_front() -> void:
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		Vector2.ZERO, Vector2.ZERO, Vector2(0, 5), HALF)).is_false()


# ===== narrower arc =====


func test_narrow_arc_excludes_wide_angles() -> void:
	var quarter := PI / 4.0  # 45° half-angle -> 90° total front cone
	# 60° off facing is outside a 45° half-angle cone...
	var p := Vector2(sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0))) * 5.0
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2.ZERO, p, quarter)).is_false()
	# ...but 30° off is inside it.
	var q := Vector2(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0))) * 5.0
	assert_bool(RegimentFacingVisualizer.front_arc_contains(
		Vector2(0, 1), Vector2.ZERO, q, quarter)).is_true()


# ===== classify_arc (four 90° quadrants, AoF:R v3.5.1 p.5) =====


func test_classify_arc_ahead_is_front() -> void:
	# Facing +Z, point straight ahead.
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, Vector2(0, 5))
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FRONT)


func test_classify_arc_behind_is_rear() -> void:
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, Vector2(0, -5))
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.REAR)


func test_classify_arc_right_is_flank_right() -> void:
	# Facing +Z, point to +X (right).
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, Vector2(5, 0))
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FLANK_RIGHT)


func test_classify_arc_left_is_flank_left() -> void:
	# Facing +Z, point to -X (left).
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, Vector2(-5, 0))
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FLANK_LEFT)


func test_classify_arc_30_deg_off_is_still_front() -> void:
	# 30° off facing is within the 45° half-angle front cone.
	var p := Vector2(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0))) * 5.0
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, p)
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FRONT)


func test_classify_arc_60_deg_off_is_flank() -> void:
	# 60° off facing is past the 45° boundary -> right flank.
	var p := Vector2(sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0))) * 5.0
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, p)
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FLANK_RIGHT)


func test_classify_arc_negative_60_deg_off_is_left_flank() -> void:
	# -60° off facing (to the left) -> left flank.
	var p := Vector2(sin(deg_to_rad(-60.0)), cos(deg_to_rad(-60.0))) * 5.0
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2.ZERO, p)
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FLANK_LEFT)


func test_classify_arc_diagonal_facing_uses_world_axis() -> void:
	# Facing +X; a +X point is front, a +Z point is left flank (since +Z is 90° left of +X).
	var front := RegimentFacingVisualizer.classify_arc(Vector2(1, 0), Vector2.ZERO, Vector2(5, 0))
	assert_int(front).is_equal(RegimentFacingVisualizer.ArcQuadrant.FRONT)
	var left := RegimentFacingVisualizer.classify_arc(Vector2(1, 0), Vector2.ZERO, Vector2(0, 5))
	assert_int(left).is_equal(RegimentFacingVisualizer.ArcQuadrant.FLANK_LEFT)


func test_classify_arc_at_apex_is_front() -> void:
	var q := RegimentFacingVisualizer.classify_arc(Vector2(0, 1), Vector2(2, 2), Vector2(2, 2))
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FRONT)


func test_classify_arc_zero_facing_is_front() -> void:
	# Degenerate facing falls back to FRONT (no crash).
	var q := RegimentFacingVisualizer.classify_arc(Vector2.ZERO, Vector2.ZERO, Vector2(0, 5))
	assert_int(q).is_equal(RegimentFacingVisualizer.ArcQuadrant.FRONT)


func test_quadrant_labels_are_human_readable() -> void:
	assert_str(RegimentFacingVisualizer.quadrant_label(RegimentFacingVisualizer.ArcQuadrant.FRONT)).is_equal("Front")
	assert_str(RegimentFacingVisualizer.quadrant_label(RegimentFacingVisualizer.ArcQuadrant.FLANK_RIGHT)).is_equal("Right Flank")
	assert_str(RegimentFacingVisualizer.quadrant_label(RegimentFacingVisualizer.ArcQuadrant.FLANK_LEFT)).is_equal("Left Flank")
	assert_str(RegimentFacingVisualizer.quadrant_label(RegimentFacingVisualizer.ArcQuadrant.REAR)).is_equal("Rear")
