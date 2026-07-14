extends GdUnitTestSuite
## Tests for MoveLedger — the "path painting" P1 data layer: polyline arc measurement
## (the number stamped on every trail), the no-re-route simplification, the per-model
## path derivation helpers (translate to a base / append the drop-resolved final), and
## the ACTIVATION-END clearing rules that decide when a visible trail fades (same-unit
## drops accumulate; a new drop by the same owner ends the previous activation; one
## drop_id spanning units never fades itself; marking Activated / round advance end it).

const INCH := 0.0254   # metres per inch
const TOL := 0.001     # inches


## World-XZ point in metres from inch coordinates.
func _p(x_in: float, z_in: float) -> Vector2:
	return Vector2(x_in, z_in) * INCH


func _line(points_in: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points_in:
		out.append((p as Vector2) * INCH)
	return out


## Fold extend_path over a sequence of cursor points (inches), starting empty — the net
## retrace-erased path a drag through those cursor positions would record.
func _drag(points_in: Array) -> PackedVector2Array:
	var path := PackedVector2Array()
	for p in points_in:
		path = MoveLedger.extend_path(path, (p as Vector2) * INCH)
	return path


## Reproduce ObjectManager's STRICT "dry brush" cap loop over a sequence of desired anchor
## positions (inches): retrace toward the target (frees budget), clamp the head to the cap,
## then commit the (capped) head forward. Returns the net traveled arc in inches — the same
## number the HUD shows and the trail stamps. The first point seeds the drag start.
func _capped_drag(desireds_in: Array, cap_inches: float) -> float:
	var cap_m := cap_inches * INCH
	var committed := PackedVector2Array()
	var head := Vector2.ZERO
	for i in range(desireds_in.size()):
		var desired: Vector2 = (desireds_in[i] as Vector2) * INCH
		if committed.is_empty():
			committed = PackedVector2Array([desired])   # drag start
			head = desired
			continue
		committed = MoveLedger.retrace(committed, desired)
		head = desired
		if cap_m > 0.0:
			var used := MoveLedger.length_meters(committed)
			var from_pt: Vector2 = committed[committed.size() - 1] if not committed.is_empty() else desired
			var remaining := cap_m - used
			if remaining <= 0.0:
				committed = MoveLedger.truncate_to_length(committed, cap_m)
				head = committed[committed.size() - 1]
			elif from_pt.distance_to(desired) > remaining:
				head = from_pt + (desired - from_pt).normalized() * remaining
		if committed.is_empty():
			committed = PackedVector2Array([head])
		elif committed[committed.size() - 1].distance_to(head) >= MoveLedger.PATH_SAMPLE_MIN_M:
			committed.append(head)
	var tail := committed[committed.size() - 1].distance_to(head) if not committed.is_empty() else 0.0
	return (MoveLedger.length_meters(committed) + tail) / INCH


# ===== Arc length (the measured truth) =====

func test_length_inches_straight_line() -> void:
	assert_float(MoveLedger.length_inches(_line([Vector2(0, 0), Vector2(6, 0)]))) \
		.is_equal_approx(6.0, TOL)


func test_length_inches_l_path_sums_the_legs() -> void:
	# 3" east then 4" north = 7" of consumed path (NOT the 5" crow-flight diagonal).
	assert_float(MoveLedger.length_inches(_line([Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)]))) \
		.is_equal_approx(7.0, TOL)


func test_length_inches_degenerate() -> void:
	assert_float(MoveLedger.length_inches(PackedVector2Array())).is_equal_approx(0.0, TOL)
	assert_float(MoveLedger.length_inches(_line([Vector2(1, 1)]))).is_equal_approx(0.0, TOL)


func test_length_inches_wiggle_counts_full_arc() -> void:
	# Out 4" and back 4" = 8" consumed, even though the displacement is zero.
	assert_float(MoveLedger.length_inches(_line([Vector2(0, 0), Vector2(4, 0), Vector2(0, 0)]))) \
		.is_equal_approx(8.0, TOL)


# ===== Simplification (drop sample noise, never re-route) =====

func test_simplify_drops_collinear_midpoints() -> void:
	var noisy := _line([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0)])
	var out := MoveLedger.simplify(noisy)
	assert_int(out.size()).is_equal(2)
	assert_that(out[0]).is_equal(noisy[0])
	assert_that(out[1]).is_equal(noisy[4])
	# The measured arc is unchanged by simplification.
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(4.0, TOL)


func test_simplify_keeps_a_real_corner() -> void:
	var l_path := _line([Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)])
	var out := MoveLedger.simplify(l_path)
	assert_int(out.size()).is_equal(3)
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(7.0, TOL)


func test_simplify_never_reroutes_a_detour() -> void:
	# A drag around an obstacle: the detour points are deliberate bends and must stay —
	# simplify may drop noise, never shorten the route the player actually painted.
	var detour := _line([Vector2(0, 0), Vector2(2, 0), Vector2(2, 3), Vector2(5, 3), Vector2(5, 0), Vector2(7, 0)])
	var out := MoveLedger.simplify(detour)
	assert_int(out.size()).is_equal(detour.size())
	assert_float(MoveLedger.length_inches(out)) \
		.is_equal_approx(MoveLedger.length_inches(detour), TOL)


func test_simplify_collapses_near_duplicates_keeps_exact_endpoint() -> void:
	# Jittery samples well under the min sample distance collapse; the exact final
	# position (drop-resolved) is always kept.
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(0.001, 0.0005), Vector2(0.002, 0.0), Vector2(0.1, 0.0),
		Vector2(0.1004, 0.0004)])
	var out := MoveLedger.simplify(pts)
	assert_that(out[0]).is_equal(Vector2(0, 0))
	assert_that(out[out.size() - 1]).is_equal(Vector2(0.1004, 0.0004))
	assert_int(out.size()).is_equal(2)


# ===== Backtrack erasing ("Rückwärtsmalen radiert" — you can't inflate by wiggling) =====

func test_forward_extends_normally() -> void:
	# A plain forward drag records the straight travel — nothing to erase.
	var path := _drag([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(6, 0)])
	assert_float(MoveLedger.length_inches(path)).is_equal_approx(6.0, 0.05)


func test_forward_then_back_to_start_measures_near_zero() -> void:
	# Out 6" then all the way back: the retrace erases the outgoing path and refunds the
	# budget — the model is back where it started, so net travel ≈ 0 (NOT 12").
	var path := _drag([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(6, 0),
			Vector2(4, 0), Vector2(2, 0), Vector2(0.1, 0)])
	assert_float(MoveLedger.length_inches(path)).is_less(0.3)


func test_forward_back_forward_measures_the_net_taut_path() -> void:
	# Out 6", back to 3", out again to 5": the net taut path is 5" (final position), NOT
	# the wiggle sum (6 + 3 + 2 = 11").
	var path := _drag([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(6, 0),
			Vector2(5, 0), Vector2(4, 0), Vector2(3, 0), Vector2(4, 0), Vector2(5, 0)])
	assert_float(MoveLedger.length_inches(path)).is_equal_approx(5.0, 0.1)


func test_backtrack_is_robust_to_lateral_jitter() -> void:
	# The return drag is offset ~2 mm sideways (< the retrace tolerance) — imperfect
	# retracing must still erase, so a jittery there-and-back can't inflate the distance.
	var jz := 0.002 / INCH   # ~2 mm expressed in the helper's inch units
	var path := _drag([Vector2(0, 0), Vector2(3, 0), Vector2(6, 0),
			Vector2(5, jz), Vector2(4, jz), Vector2(3, jz), Vector2(2, jz),
			Vector2(1, jz), Vector2(0.1, jz)])
	assert_float(MoveLedger.length_inches(path)).is_less(0.5)


func test_genuine_detour_is_preserved_not_erased() -> void:
	# A wide sidestep (offset far beyond the tolerance) is a REAL detour, not a backtrack:
	# the return leg is parallel but 3" away, so the path keeps its arc (not collapsed).
	var path := _drag([Vector2(0, 0), Vector2(4, 0), Vector2(4, 3), Vector2(0, 3)])
	# 4 (east) + 3 (north) + 4 (west) = 11" of real travel around the detour.
	assert_float(MoveLedger.length_inches(path)).is_greater(9.0)


func test_extend_from_empty_seeds_the_start() -> void:
	var path := MoveLedger.extend_path(PackedVector2Array(), _p(1, 1))
	assert_int(path.size()).is_equal(1)
	assert_that(path[0]).is_equal(_p(1, 1))


# ===== Per-model path derivation =====

func test_translated_shifts_every_point() -> void:
	var out := MoveLedger.translated(_line([Vector2(0, 0), Vector2(3, 0)]), _p(0, 2))
	assert_that(out[0]).is_equal(_p(0, 2))
	assert_that(out[1]).is_equal(_p(3, 2))


func test_with_final_appends_a_real_nudge() -> void:
	# Anti-stacking pushed the base 0.5" past the last sample: a final leg is added.
	var out := MoveLedger.with_final(_line([Vector2(0, 0), Vector2(3, 0)]), _p(3.5, 0))
	assert_int(out.size()).is_equal(3)
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(3.5, TOL)


func test_with_final_snaps_a_micro_difference() -> void:
	# Sub-millimetre delta: the endpoint is REPLACED (exact drop spot), no extra leg.
	var out := MoveLedger.with_final(_line([Vector2(0, 0), Vector2(3, 0)]),
			_p(3, 0) + Vector2(0.0005, 0))
	assert_int(out.size()).is_equal(2)
	assert_that(out[1]).is_equal(_p(3, 0) + Vector2(0.0005, 0))


func test_distance_to_polyline() -> void:
	var path := _line([Vector2(0, 0), Vector2(6, 0)])
	# 1" beside the middle of the band; and beyond the end cap.
	assert_float(MoveLedger.distance_to_polyline_m(_p(3, 1), path)).is_equal_approx(INCH, 0.0001)
	assert_float(MoveLedger.distance_to_polyline_m(_p(7, 0), path)).is_equal_approx(INCH, 0.0001)


# ===== Recording (P1) =====

func test_record_entry_carries_the_measured_arc() -> void:
	var ledger := MoveLedger.new()
	var entry := ledger.record(1, "u1", "Snipers", 42, _line([Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)]), 2)
	assert_float(float(entry["inches"])).is_equal_approx(7.0, TOL)
	assert_str(str(entry["unit"])).is_equal("u1")
	assert_int(int(entry["model"])).is_equal(42)
	assert_int(int(entry["round"])).is_equal(2)
	assert_int(ledger.entries.size()).is_equal(1)
	assert_int(ledger.entries_for_unit("u1").size()).is_equal(1)
	assert_int(ledger.entries_for_unit("other").size()).is_equal(0)


# ===== Activation-end clearing (what fades when) =====

func test_same_unit_drops_accumulate_without_fading() -> void:
	var ledger := MoveLedger.new()
	# Moving a unit model by model = several drops of the SAME unit: nothing fades.
	assert_array(Array(ledger.note_commit(1, "u1", 100))).is_empty()
	assert_array(Array(ledger.note_commit(1, "u1", 101))).is_empty()
	assert_array(Array(ledger.note_commit(1, "u1", 102))).is_empty()


func test_new_unit_drop_ends_the_previous_activation() -> void:
	var ledger := MoveLedger.new()
	ledger.note_commit(1, "u1", 100)
	var faded := Array(ledger.note_commit(1, "u2", 101))
	assert_array(faded).contains_exactly(["u1"])
	# And the next unit ends u2 in turn.
	assert_array(Array(ledger.note_commit(1, "u3", 102))).contains_exactly(["u2"])


func test_one_drop_spanning_units_never_fades_itself() -> void:
	var ledger := MoveLedger.new()
	# A multi-unit box-drag commits several units under ONE drop_id (also how the MP
	# messages arrive) — they form one set and do not fade each other.
	assert_array(Array(ledger.note_commit(1, "u1", 100))).is_empty()
	assert_array(Array(ledger.note_commit(1, "u2", 100))).is_empty()
	# The NEXT drop ends both.
	var faded := Array(ledger.note_commit(1, "u3", 101))
	assert_array(faded).contains_exactly_in_any_order(["u1", "u2"])


func test_owners_are_independent() -> void:
	var ledger := MoveLedger.new()
	# Alternating activations: my move, the opponent's move, my next move.
	assert_array(Array(ledger.note_commit(1, "mine_a", 100))).is_empty()
	assert_array(Array(ledger.note_commit(2, "theirs_x", 101))).is_empty()   # does NOT fade mine
	assert_array(Array(ledger.note_commit(1, "mine_b", 102))).contains_exactly(["mine_a"])
	assert_array(Array(ledger.note_commit(2, "theirs_y", 103))).contains_exactly(["theirs_x"])


func test_activation_done_removes_the_unit_from_tracking() -> void:
	var ledger := MoveLedger.new()
	ledger.note_commit(1, "u1", 100)
	ledger.note_activation_done("u1")
	# u1's activation already ended (its trails already faded): the next commit must
	# not report it again.
	assert_array(Array(ledger.note_commit(1, "u2", 101))).is_empty()


func test_round_advance_clears_tracking_but_keeps_entries() -> void:
	var ledger := MoveLedger.new()
	ledger.record(1, "u1", "Unit 1", 7, _line([Vector2(0, 0), Vector2(6, 0)]), 1)
	ledger.note_commit(1, "u1", 100)
	ledger.note_round_advance()
	# No stale fade reported into the new round...
	assert_array(Array(ledger.note_commit(1, "u2", 101))).is_empty()
	# ...but the recorded proof persists (receipt/replay stages read it later).
	assert_int(ledger.entries.size()).is_equal(1)


func test_same_unit_continues_across_a_new_drop_id() -> void:
	var ledger := MoveLedger.new()
	ledger.note_commit(1, "u1", 100)
	ledger.note_commit(1, "u2", 100)
	# A follow-up drop of u2 alone: u2's activation CONTINUES (it never fades itself),
	# while u1 — no longer part of the active set — ends.
	assert_array(Array(ledger.note_commit(1, "u2", 101))).contains_exactly(["u1"])


# ===== truncate_to_length (the "dry brush" boundary) =====

func test_truncate_shortens_a_long_line() -> void:
	var out := MoveLedger.truncate_to_length(_line([Vector2(0, 0), Vector2(10, 0)]), 6.0 * INCH)
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(6.0, TOL)
	assert_float(out[out.size() - 1].x / INCH).is_equal_approx(6.0, TOL)


func test_truncate_leaves_a_short_path_untouched() -> void:
	var path := _line([Vector2(0, 0), Vector2(3, 0)])
	var out := MoveLedger.truncate_to_length(path, 6.0 * INCH)
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(3.0, TOL)


func test_truncate_across_a_corner_keeps_the_bend() -> void:
	# 3" east + 4" north; truncate to 5" lands 2" up the north leg (3 + 2 = 5).
	var out := MoveLedger.truncate_to_length(_line([Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)]), 5.0 * INCH)
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(5.0, TOL)
	assert_float(out[out.size() - 1].y / INCH).is_equal_approx(2.0, 0.02)


func test_retrace_shortens_without_appending() -> void:
	# retrace erases the walked-back head but never adds the cursor point.
	var path := _line([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0)])
	var out := MoveLedger.retrace(path, _p(3, 0))   # cursor back between 2 and 4
	assert_float(MoveLedger.length_inches(out)).is_equal_approx(2.0, 0.05)


# ===== STRICT cap x backtrack interop (the "dry brush" runs dry, retrace refills) =====

func test_cap_hard_stops_at_the_band() -> void:
	# Drag straight out to 10" with a 6" band: the brush runs dry — the net arc holds at 6".
	assert_float(_capped_drag([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0),
			Vector2(6, 0), Vector2(8, 0), Vector2(10, 0)], 6.0)).is_equal_approx(6.0, 0.05)


func test_cap_never_limits_a_move_within_budget() -> void:
	# A 4" drag under a 6" band is unaffected — the cap only bites at the max.
	assert_float(_capped_drag([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0)], 6.0)) \
		.is_equal_approx(4.0, 0.05)


func test_backtrack_refunds_capped_budget() -> void:
	# Push past the 6" cap (dry), then drag all the way back: retrace frees the budget so the
	# net collapses to ~0 — the enforcement composes with the backtrack-erase.
	assert_float(_capped_drag([Vector2(0, 0), Vector2(4, 0), Vector2(6, 0), Vector2(8, 0),
			Vector2(10, 0), Vector2(6, 0), Vector2(3, 0), Vector2(0.1, 0)], 6.0)).is_less(0.4)


func test_backtrack_then_repaint_reaches_full_band_again() -> void:
	# Dry at 6", retrace back to 1", then paint forward again: the freed budget lets the brush
	# reach the full 6" band once more (it is not permanently stuck at the old cap point).
	assert_float(_capped_drag([Vector2(0, 0), Vector2(10, 0), Vector2(1, 0), Vector2(6, 0)], 6.0)) \
		.is_equal_approx(6.0, 0.05)


func test_cap_off_allows_moving_past_the_band() -> void:
	# cap 0 = Casual (free drag): a straight 10" move is NOT truncated to any band — the full
	# arc is recorded. (Backtrack-erase still applies independently; it is not the cap.)
	assert_float(_capped_drag([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0),
			Vector2(6, 0), Vector2(8, 0), Vector2(10, 0)], 0.0)).is_equal_approx(10.0, 0.05)
