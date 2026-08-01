extends GdUnitTestSuite
## #210 — the cursor-placement ghost's rule check, pure (PlacementGhost.validate):
## every base FULLY within 6" of the transport's base edge (GF v3.5.1 p.15), no base
## overlap, inside the table. The interactive half is maintainer-tested (Testcenter);
## headless flows bypass the ghost entirely (pinned in the e2e embark suite).
##
## #reinforcement — the zone itself is now a DATA DESCRIPTOR (PlacementGhost.zone_contains):
## circle_zone() covers the disembark case above; edge_strip_zone() covers the OPR rule
## "Reinforcement" — a base FULLY within 12" of any table edge, and FULLY on the table.

const INCH := 0.0254
const R := 0.016
const BOUNDS := Rect2(-2.0, -2.0, 4.0, 4.0)

var _shape := [{"off": Vector2(-0.03, 0.0), "r": R}, {"off": Vector2(0.03, 0.0), "r": R}]
var _zone_c := Vector3.ZERO
var _zone_m := 6.0 * INCH + R   # 6" + transport base radius


func test_inside_the_zone_is_legal() -> void:
	assert_bool(PlacementGhost.validate(_shape, Vector3(0.05, 0, 0.05), 0.0,
		PlacementGhost.circle_zone(_zone_c, _zone_m), [], BOUNDS)).is_true()


func test_a_base_sticking_out_of_the_zone_is_illegal() -> void:
	# Centre chosen so the OUTER edge of the far model crosses the 6" boundary.
	assert_bool(PlacementGhost.validate(_shape, Vector3(_zone_m - R - 0.02, 0, 0), 0.0,
		PlacementGhost.circle_zone(_zone_c, _zone_m), [], BOUNDS)) \
		.override_failure_message("#210 — a model base sticking past the fully-within-6\" boundary counted as legal") \
		.is_false()


func test_rotation_moves_a_base_back_into_the_zone() -> void:
	# At the same centre, rotating the two-model line by 90° pulls the far model inside.
	assert_bool(PlacementGhost.validate(_shape, Vector3(_zone_m - R - 0.02, 0, 0), PI / 2.0,
		PlacementGhost.circle_zone(_zone_c, _zone_m), [], BOUNDS)).is_true()


func test_overlap_with_a_standing_base_is_illegal() -> void:
	var blockers := [{"p": Vector3(0.05 - 0.03, 0.0, 0.05), "r": R}]
	assert_bool(PlacementGhost.validate(_shape, Vector3(0.05, 0, 0.05), 0.0,
		PlacementGhost.circle_zone(_zone_c, _zone_m), blockers, BOUNDS)).is_false()


func test_outside_the_table_is_illegal() -> void:
	assert_bool(PlacementGhost.validate(_shape, Vector3(0.05, 0, 0.05), 0.0,
		PlacementGhost.circle_zone(_zone_c, _zone_m), [], Rect2(1.0, 1.0, 0.5, 0.5))).is_false()


# ---- edge_strip_zone() — OPR "Reinforcement": FULLY within 12" of any table edge ----

const EDGE_INCH := 0.0254
const EDGE_R := 0.016
const EDGE_M := 12.0 * EDGE_INCH   # 12" reinforcement strip
# A 4ft x 6ft-style table: x spans 6ft (1.8288m), z spans 4ft (1.2192m).
const EDGE_BOUNDS := Rect2(-0.9144, -0.6096, 1.8288, 1.2192)
var _edge_shape := [{"off": Vector2.ZERO, "r": EDGE_R}]


func test_edge_strip_a_base_touching_the_near_edge_is_legal() -> void:
	# The near/top (z) edge — the base sits right up against the table's edge (with a small
	# margin so this pins the 12" boundary, not the separate on-the-table knife-edge).
	var p := Vector3(0.0, 0, EDGE_BOUNDS.position.y + EDGE_R + 0.002)
	assert_bool(PlacementGhost.validate(_edge_shape, p, 0.0,
		PlacementGhost.edge_strip_zone(EDGE_M), [], EDGE_BOUNDS)).is_true()


func test_edge_strip_a_base_just_inside_twelve_inches_is_legal() -> void:
	# Far side of the base sits a hair inside 12" of the near/top edge.
	var z: float = EDGE_BOUNDS.position.y + EDGE_M - EDGE_R - 0.001
	assert_bool(PlacementGhost.validate(_edge_shape, Vector3(0.0, 0, z), 0.0,
		PlacementGhost.edge_strip_zone(EDGE_M), [], EDGE_BOUNDS)).is_true()


func test_edge_strip_a_base_just_past_twelve_inches_is_illegal() -> void:
	# Mirror of the above, a hair OUTSIDE 12" — this pair pins the boundary.
	var z: float = EDGE_BOUNDS.position.y + EDGE_M - EDGE_R + 0.001
	assert_bool(PlacementGhost.validate(_edge_shape, Vector3(0.0, 0, z), 0.0,
		PlacementGhost.edge_strip_zone(EDGE_M), [], EDGE_BOUNDS)) \
		.override_failure_message("Reinforcement — a base a hair past the fully-within-12\" boundary counted as legal") \
		.is_false()


func test_edge_strip_every_edge_qualifies() -> void:
	# A small margin off the physical table edge keeps this pinned to the 12" boundary,
	# not the separate (float-precision-sensitive) on-the-table knife-edge.
	var zone := PlacementGhost.edge_strip_zone(EDGE_M)
	# Left edge.
	assert_bool(PlacementGhost.validate(_edge_shape,
		Vector3(EDGE_BOUNDS.position.x + EDGE_R + 0.002, 0, 0.0), 0.0, zone, [], EDGE_BOUNDS)).is_true()
	# Right edge.
	assert_bool(PlacementGhost.validate(_edge_shape,
		Vector3(EDGE_BOUNDS.end.x - EDGE_R - 0.002, 0, 0.0), 0.0, zone, [], EDGE_BOUNDS)).is_true()
	# Near/top edge.
	assert_bool(PlacementGhost.validate(_edge_shape,
		Vector3(0.0, 0, EDGE_BOUNDS.position.y + EDGE_R + 0.002), 0.0, zone, [], EDGE_BOUNDS)).is_true()
	# Far/bottom edge.
	assert_bool(PlacementGhost.validate(_edge_shape,
		Vector3(0.0, 0, EDGE_BOUNDS.end.y - EDGE_R - 0.002), 0.0, zone, [], EDGE_BOUNDS)).is_true()


func test_edge_strip_table_centre_is_illegal() -> void:
	# The table is 6ft wide / 4ft deep — its centre is far past 12" from every edge.
	assert_bool(PlacementGhost.validate(_edge_shape, Vector3(0.0, 0, 0.0), 0.0,
		PlacementGhost.edge_strip_zone(EDGE_M), [], EDGE_BOUNDS)).is_false()


func test_edge_strip_a_base_hanging_off_the_table_is_illegal() -> void:
	# Centre is inside bounds, but the base's left edge (p.x - r) pokes past the table edge.
	var x: float = EDGE_BOUNDS.position.x + EDGE_R - 0.005
	assert_bool(PlacementGhost.validate(_edge_shape, Vector3(x, 0, 0.0), 0.0,
		PlacementGhost.edge_strip_zone(EDGE_M), [], EDGE_BOUNDS)).is_false()


func test_edge_strip_still_rejects_overlap_with_a_standing_base() -> void:
	var p := Vector3(EDGE_BOUNDS.position.x + EDGE_R + 0.002, 0, 0.0)
	var blockers := [{"p": p, "r": EDGE_R}]
	assert_bool(PlacementGhost.validate(_edge_shape, p, 0.0,
		PlacementGhost.edge_strip_zone(EDGE_M), blockers, EDGE_BOUNDS)).is_false()
