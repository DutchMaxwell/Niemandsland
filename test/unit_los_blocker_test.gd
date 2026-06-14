extends GdUnitTestSuite
## LosRules unit-as-LOS-blocker (Asgard tournament standard): models block sight
## lines at their Height category, <1" gaps inside a unit count as closed, the
## endpoint units never block their own line. Pure 2D geometry — fully headless.

const INCH := LosRules.INCHES_TO_METERS
const R := 0.016  # 32 mm round base radius (metres)


func _blocker(x: float, z: float, height: int, unit_key: int, radius: float = R) -> LosRules.Blocker:
	return LosRules.Blocker.new(Vector2(x, z), radius, height, unit_key)

# ===== Geometry =====


func test_segment_intersects_circle() -> void:
	# Straight through the centre.
	assert_bool(LosRules.segment_intersects_circle(
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, 0), R)).is_true()
	# Passes well beside it.
	assert_bool(LosRules.segment_intersects_circle(
		Vector2(-1, 0.5), Vector2(1, 0.5), Vector2(0, 0), R)).is_false()
	# Segment ends before reaching the circle.
	assert_bool(LosRules.segment_intersects_circle(
		Vector2(-1, 0), Vector2(-0.5, 0), Vector2(0, 0), R)).is_false()


func test_segments_intersect() -> void:
	assert_bool(LosRules.segments_intersect(
		Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0))).is_true()
	assert_bool(LosRules.segments_intersect(
		Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(2, 0))).is_false()

# ===== Direct base hits =====


func test_model_on_line_blocks() -> void:
	var blockers: Array[LosRules.Blocker] = [_blocker(0, 0, 2, 100)]
	assert_bool(LosRules.units_block_line(
		Vector2(-1, 0), Vector2(1, 0), 2, 2, blockers, [])).is_true()


func test_taller_endpoints_see_over_smaller_blocker() -> void:
	# H2 infantry between two H4 walkers: both endpoints see over it.
	var blockers: Array[LosRules.Blocker] = [_blocker(0, 0, 2, 100)]
	assert_bool(LosRules.units_block_line(
		Vector2(-1, 0), Vector2(1, 0), 4, 4, blockers, [])).is_false()
	# Mixed H2/H4 endpoints: the taller end still sees over (a blocker stops the
	# line only when its Height >= BOTH endpoints, mirroring the terrain rule).
	assert_bool(LosRules.units_block_line(
		Vector2(-1, 0), Vector2(1, 0), 2, 4, blockers, [])).is_false()


func test_blocker_must_match_both_endpoint_heights() -> void:
	# H4 blocker vs H2 endpoints: blocks (4 >= 2 on both ends).
	var blockers: Array[LosRules.Blocker] = [_blocker(0, 0, 4, 100)]
	assert_bool(LosRules.units_block_line(
		Vector2(-1, 0), Vector2(1, 0), 2, 2, blockers, [])).is_true()


func test_own_unit_never_blocks() -> void:
	var blockers: Array[LosRules.Blocker] = [_blocker(0, 0, 4, 100)]
	assert_bool(LosRules.units_block_line(
		Vector2(-1, 0), Vector2(1, 0), 2, 2, blockers, [100])).is_false()

# ===== Closed 1" gaps =====


func test_sub_inch_gap_in_same_unit_is_closed() -> void:
	# Two 32 mm bases 0.05 m apart centre-to-centre -> gap = 0.018 m (~0.7") < 1".
	var blockers: Array[LosRules.Blocker] = [
		_blocker(0.0, 0.0, 2, 100), _blocker(0.05, 0.0, 2, 100)]
	# Line threads exactly through the middle of the gap (touches neither base).
	assert_bool(LosRules.units_block_line(
		Vector2(0.025, -1), Vector2(0.025, 1), 2, 2, blockers, [])).is_true()


func test_wide_gap_in_same_unit_stays_open() -> void:
	# Centre distance 0.1 m -> gap = 0.068 m (~2.7") >= 1": the line passes.
	var blockers: Array[LosRules.Blocker] = [
		_blocker(0.0, 0.0, 2, 100), _blocker(0.1, 0.0, 2, 100)]
	assert_bool(LosRules.units_block_line(
		Vector2(0.05, -1), Vector2(0.05, 1), 2, 2, blockers, [])).is_false()


func test_gap_between_different_units_never_closes() -> void:
	var blockers: Array[LosRules.Blocker] = [
		_blocker(0.0, 0.0, 2, 100), _blocker(0.05, 0.0, 2, 200)]
	assert_bool(LosRules.units_block_line(
		Vector2(0.025, -1), Vector2(0.025, 1), 2, 2, blockers, [])).is_false()


func test_closed_gap_height_is_the_lower_model() -> void:
	# H4 + H2 pair: the gap "wall" is H2 — H4 endpoints see over it.
	var blockers: Array[LosRules.Blocker] = [
		_blocker(0.0, 0.0, 4, 100), _blocker(0.05, 0.0, 2, 100)]
	assert_bool(LosRules.units_block_line(
		Vector2(0.025, -1), Vector2(0.025, 1), 4, 4, blockers, [])).is_false()
	# Infantry endpoints cannot see through it.
	assert_bool(LosRules.units_block_line(
		Vector2(0.025, -1), Vector2(0.025, 1), 2, 2, blockers, [])).is_true()


func test_no_blockers_means_clear_line() -> void:
	assert_bool(LosRules.units_block_line(
		Vector2(-1, 0), Vector2(1, 0), 2, 2, [] as Array[LosRules.Blocker], [])).is_false()
