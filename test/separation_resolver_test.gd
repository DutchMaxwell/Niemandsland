extends GdUnitTestSuite
## Tests for SeparationResolver — the drop-time anti-stacking push-back and the magnetic
## enemy contact snap (GF/AoF Advanced Rules v3.5.1, p.7). Push-back slides a base that
## OVERLAPS another unit's base out to clean contact (enemy AND friendly); the snap
## pulls a near-miss INWARD to kissing an ENEMY base only. Shapes authored in inches;
## resolution runs in metres. resolve_translation mutates the item shapes in place and
## returns the total translation, so we assert both the delta and the resolved gaps.

const INCH := 0.0254
const TOL := 0.02       # inches
const M_TOL := 0.0006   # metres (~0.6 mm)


# ===== Helpers =====

func _round(cx_in: float, cz_in: float, r_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_round(Vector2(cx_in, cz_in) * INCH, r_in * INCH)


func _cand(shape: SeparationChecker.BaseShape, player_id: int) -> Dictionary:
	return {"shape": shape, "player_id": player_id}


# ===== Anti-stacking push-back =====

func test_enemy_overlap_pushes_to_contact() -> void:
	# Item r0.5" at origin overlaps an enemy r0.5" at (0.6,0) by 0.4".
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(0.6, 0, 0.5), 2)]
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	# Pushed 0.4" along -X (away from the enemy at +X).
	assert_float(delta.x).is_equal_approx(-0.4 * INCH, M_TOL)
	assert_float(delta.y).is_equal_approx(0.0, M_TOL)
	# Resolved to base contact (gap ~0).
	assert_float(SeparationChecker.edge_distance(item[0], cands[0]["shape"])).is_equal_approx(0.0, TOL)


func test_friendly_overlap_also_pushes_to_contact() -> void:
	# Friendly minis must not interpenetrate either (they just stay a marked violation).
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(0.6, 0, 0.5), 1)]  # same army
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.x).is_equal_approx(-0.4 * INCH, M_TOL)
	assert_float(SeparationChecker.edge_distance(item[0], cands[0]["shape"])).is_equal_approx(0.0, TOL)


func test_no_overlap_no_move() -> void:
	# 0.5" gap, no enemy near enough to snap (see snap tests) -> item stays put.
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(2.5, 0, 0.5), 1)]  # gap 1.5", friendly
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.length()).is_equal_approx(0.0, M_TOL)


func test_multi_overlap_resolves_all() -> void:
	# Wedged against two enemies on perpendicular axes -> ends clear of both.
	var item := [_round(0, 0, 0.5)]
	var a := _round(0.5, 0, 0.5)   # overlap 0.5" along +X
	var b := _round(0, 0.5, 0.5)   # overlap 0.5" along +Z
	var cands := [_cand(a, 2), _cand(b, 2)]
	SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(SeparationChecker.edge_distance(item[0], a)).is_greater_equal(-TOL)
	assert_float(SeparationChecker.edge_distance(item[0], b)).is_greater_equal(-TOL)


# ===== Magnetic enemy contact snap =====

func test_near_enemy_snaps_to_contact() -> void:
	# Item r0.5" at origin, enemy r0.5" at (1.3,0): gap 0.3" (< 0.5" snap) -> kiss.
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(1.3, 0, 0.5), 2)]
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.x).is_equal_approx(0.3 * INCH, M_TOL)  # pulled toward the enemy
	assert_float(SeparationChecker.edge_distance(item[0], cands[0]["shape"])).is_equal_approx(0.0, TOL)


func test_no_snap_to_friendly() -> void:
	# Same near-miss geometry but the neighbour is friendly -> no snap.
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(1.3, 0, 0.5), 1)]  # same army
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.length()).is_equal_approx(0.0, M_TOL)


func test_enemy_beyond_threshold_does_not_snap() -> void:
	# Gap 0.7" exceeds the 0.5" snap window -> left alone.
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(1.7, 0, 0.5), 2)]
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.length()).is_equal_approx(0.0, M_TOL)


func test_unknown_affiliation_does_not_snap() -> void:
	# Unknown enemy affiliation (player_id 0) is never classified as enemy -> no snap.
	var item := [_round(0, 0, 0.5)]
	var cands := [_cand(_round(1.3, 0, 0.5), 0)]
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.length()).is_equal_approx(0.0, M_TOL)


func test_snap_picks_nearest_enemy() -> void:
	# Two enemies in the snap window; snap to the closer (gap 0.2") not the farther (0.4").
	var item := [_round(0, 0, 0.5)]
	var near := _round(1.2, 0, 0.5)   # gap 0.2"
	var far := _round(-1.4, 0, 0.5)   # gap 0.4"
	var cands := [_cand(far, 2), _cand(near, 2)]
	var delta := SeparationResolver.resolve_translation(item, cands, 1)
	assert_float(delta.x).is_equal_approx(0.2 * INCH, M_TOL)


# ===== Empty inputs =====

func test_empty_inputs_are_safe() -> void:
	assert_float(SeparationResolver.resolve_translation([], [_cand(_round(0, 0, 0.5), 2)], 1).length()).is_equal(0.0)
	assert_float(SeparationResolver.resolve_translation([_round(0, 0, 0.5)], [], 1).length()).is_equal(0.0)
