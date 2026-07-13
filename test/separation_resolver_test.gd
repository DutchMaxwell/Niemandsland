extends GdUnitTestSuite
## Tests for SeparationResolver.resolve_overlaps — the ABSOLUTE anti-stacking pass reused by the Solo-AI
## placement gate (field-test finding 3: bases must NEVER overlap after an AI move/deploy). GF/AoF Advanced
## Rules v3.5.1 p.7: models "may never move through other models or units, friendly or enemy". Pure geometry
## on explicit BaseShapes (no scene). The item shapes are mutated in place; the returned translation is the
## total world-XZ push. Distances authored in INCHES (radius/centres) via _round; edge_distance returns inches.

const IN2M := 0.0254


func _round(cx_in: float, cz_in: float, r_in: float) -> SeparationChecker.BaseShape:
	return SeparationChecker.BaseShape.make_round(Vector2(cx_in * IN2M, cz_in * IN2M), r_in * IN2M)


func test_no_overlap_input_is_left_untouched() -> void:
	var item: Array = [_round(0, 0, 0.5)]
	var obstacles: Array = [_round(3, 0, 0.5)]   # centres 3" apart, radii 0.5"+0.5" → 2" clear gap
	var delta := SeparationResolver.resolve_overlaps(item, obstacles)
	assert_float(delta.length()).is_less(1e-4)   # nothing to resolve → no move (no resting jitter)


func test_overlapping_pair_is_pushed_to_at_least_contact() -> void:
	var item: Array = [_round(0, 0, 0.5)]
	var obstacle := _round(0.4, 0, 0.5)          # centres 0.4" apart, radii sum 1.0" → 0.6" overlap
	SeparationResolver.resolve_overlaps(item, [obstacle])
	# After resolution the item base no longer overlaps the obstacle (edge gap ≥ ~0, within the module eps).
	assert_float(SeparationChecker.edge_distance(item[0], obstacle)).is_greater(-0.05)


func test_symmetric_wedge_still_escapes_to_a_clear_spot() -> void:
	# A base wedged symmetrically between four others: the summed penetration resultant cancels, so the
	# relaxation stalls — the directional escape scan must still move it fully clear (the finite-set guarantee).
	var item: Array = [_round(0, 0, 0.5)]
	var obstacles: Array = [_round(0.3, 0, 0.5), _round(-0.3, 0, 0.5), _round(0, 0.3, 0.5), _round(0, -0.3, 0.5)]
	SeparationResolver.resolve_overlaps(item, obstacles)
	for o in obstacles:
		assert_float(SeparationChecker.edge_distance(item[0], o as SeparationChecker.BaseShape)).is_greater(-0.05)


func test_empty_inputs_are_safe_noops() -> void:
	assert_float(SeparationResolver.resolve_overlaps([], [_round(0, 0, 0.5)]).length()).is_equal(0.0)
	assert_float(SeparationResolver.resolve_overlaps([_round(0, 0, 0.5)], []).length()).is_equal(0.0)
