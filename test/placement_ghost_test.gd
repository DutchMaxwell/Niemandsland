extends GdUnitTestSuite
## #210 — the cursor-placement ghost's rule check, pure (PlacementGhost.validate):
## every base FULLY within 6" of the transport's base edge (GF v3.5.1 p.15), no base
## overlap, inside the table. The interactive half is maintainer-tested (Testcenter);
## headless flows bypass the ghost entirely (pinned in the e2e embark suite).

const INCH := 0.0254
const R := 0.016
const BOUNDS := Rect2(-2.0, -2.0, 4.0, 4.0)

var _shape := [{"off": Vector2(-0.03, 0.0), "r": R}, {"off": Vector2(0.03, 0.0), "r": R}]
var _zone_c := Vector3.ZERO
var _zone_m := 6.0 * INCH + R   # 6" + transport base radius


func test_inside_the_zone_is_legal() -> void:
	assert_bool(PlacementGhost.validate(_shape, Vector3(0.05, 0, 0.05), 0.0,
		_zone_c, _zone_m, [], BOUNDS)).is_true()


func test_a_base_sticking_out_of_the_zone_is_illegal() -> void:
	# Centre chosen so the OUTER edge of the far model crosses the 6" boundary.
	assert_bool(PlacementGhost.validate(_shape, Vector3(_zone_m - R - 0.02, 0, 0), 0.0,
		_zone_c, _zone_m, [], BOUNDS)) \
		.override_failure_message("#210 — a model base sticking past the fully-within-6\" boundary counted as legal") \
		.is_false()


func test_rotation_moves_a_base_back_into_the_zone() -> void:
	# At the same centre, rotating the two-model line by 90° pulls the far model inside.
	assert_bool(PlacementGhost.validate(_shape, Vector3(_zone_m - R - 0.02, 0, 0), PI / 2.0,
		_zone_c, _zone_m, [], BOUNDS)).is_true()


func test_overlap_with_a_standing_base_is_illegal() -> void:
	var blockers := [{"p": Vector3(0.05 - 0.03, 0.0, 0.05), "r": R}]
	assert_bool(PlacementGhost.validate(_shape, Vector3(0.05, 0, 0.05), 0.0,
		_zone_c, _zone_m, blockers, BOUNDS)).is_false()


func test_outside_the_table_is_illegal() -> void:
	assert_bool(PlacementGhost.validate(_shape, Vector3(0.05, 0, 0.05), 0.0,
		_zone_c, _zone_m, [], Rect2(1.0, 1.0, 0.5, 0.5))).is_false()
