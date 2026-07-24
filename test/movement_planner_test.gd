extends GdUnitTestSuite
## MovementPlanner is the pure, shared plan-WHERE brain the Solo sim uses for AI moves: individual-model
## steering that stays in coherency, treats thin wall segments as impassable (models slide around them), and
## falls back to a local 3" A* when a model is boxed in. These prove the geometry (wall-segment intersection
## incl. corners/gaps), the coherency predicate (mirrors CoherencyChecker), the open-field fast path
## (byte-identical to a rigid slide — why the mirror stays fair), the allowance clamp, wall avoidance, and
## the stuck→A* rescue in a U-pocket.



# === Segment / wall geometry ===

func test_segments_cross_basic_cases() -> void:
	# Proper X crossing.
	assert_bool(MovementPlanner.segments_cross(Vector2(0, 0), Vector2(4, 4), Vector2(0, 4), Vector2(4, 0))).is_true()
	# Parallel, apart → never.
	assert_bool(MovementPlanner.segments_cross(Vector2(0, 0), Vector2(4, 0), Vector2(0, 2), Vector2(4, 2))).is_false()
	# T-junction: an endpoint touching the other segment counts as crossing (safe side).
	assert_bool(MovementPlanner.segments_cross(Vector2(0, 0), Vector2(4, 0), Vector2(2, 0), Vector2(2, 3))).is_true()
	# Collinear overlap counts; collinear disjoint does not.
	assert_bool(MovementPlanner.segments_cross(Vector2(0, 0), Vector2(4, 0), Vector2(2, 0), Vector2(6, 0))).is_true()
	assert_bool(MovementPlanner.segments_cross(Vector2(0, 0), Vector2(4, 0), Vector2(5, 0), Vector2(9, 0))).is_false()


func test_path_crosses_wall_through_gap_and_corner() -> void:
	# Two collinear wall pieces along y=20 with a 4" gap (x 14→18).
	var walls := [[Vector2(10, 20), Vector2(14, 20)], [Vector2(18, 20), Vector2(22, 20)]]
	# Straight through the GAP (x=16) crosses nothing.
	assert_bool(MovementPlanner.path_crosses_wall(Vector2(16, 15), Vector2(16, 25), walls)).is_false()
	# Straight through a wall piece (x=12) is blocked.
	assert_bool(MovementPlanner.path_crosses_wall(Vector2(12, 15), Vector2(12, 25), walls)).is_true()
	# Exactly at a wall END (x=14) — touching the corner is treated as blocked.
	assert_bool(MovementPlanner.path_crosses_wall(Vector2(14, 15), Vector2(14, 25), walls)).is_true()
	# No walls at all → never blocked.
	assert_bool(MovementPlanner.path_crosses_wall(Vector2(0, 0), Vector2(48, 48), [])).is_false()


# === Coherency predicate (mirrors CoherencyChecker, point-model form) ===

func test_is_coherent_connected_split_and_overspread() -> void:
	# A tight 3-model chain (≤ link distance apart) — connected + within spread.
	assert_bool(MovementPlanner.is_coherent([Vector2(10, 10), Vector2(11.5, 10), Vector2(13, 10)])).is_true()
	# One model marooned 19" away → two components → incoherent.
	assert_bool(MovementPlanner.is_coherent([Vector2(10, 10), Vector2(11, 10), Vector2(30, 10)])).is_false()
	# A connected chain (2.5" links) whose ends are 12.5" apart → over the 9"(+base) spread → incoherent.
	assert_bool(MovementPlanner.is_coherent([Vector2(0, 0), Vector2(2.5, 0), Vector2(5, 0), Vector2(7.5, 0),
		Vector2(10, 0), Vector2(12.5, 0)])).is_false()
	# 0/1 models are trivially coherent.
	assert_bool(MovementPlanner.is_coherent([])).is_true()
	assert_bool(MovementPlanner.is_coherent([Vector2(5, 5)])).is_true()


func test_enforce_coherency_reconnects_a_strayed_model() -> void:
	# Model 4 has drifted 5" out (broken link). The reconnect pass pulls it back in (no walls to clip it).
	var strayed := [Vector2(10, 10), Vector2(11.5, 10), Vector2(13, 10), Vector2(18, 10)]
	assert_bool(MovementPlanner.is_coherent(strayed)).is_false()
	var fixed := MovementPlanner._enforce_coherency(strayed, [], 48.0)
	assert_bool(MovementPlanner.is_coherent(fixed)).is_true()


# === Open-field fast path (byte-identical to the rigid slide) ===

func test_rigid_blocked_only_when_a_wall_is_in_the_path() -> void:
	var walls := [[Vector2(13, 20), Vector2(19, 20)]]
	assert_bool(MovementPlanner.rigid_blocked([Vector2(16, 18)], Vector2(0, 4), walls)).is_true()    # straight into the wall
	assert_bool(MovementPlanner.rigid_blocked([Vector2(16, 18)], Vector2(4, 0), walls)).is_false()   # sideways, misses it
	assert_bool(MovementPlanner.rigid_blocked([Vector2(16, 18)], Vector2(0, 4), [])).is_false()      # no walls


func test_no_wall_move_is_the_exact_rigid_translation() -> void:
	# With no wall in the path every model shifts by exactly delta — this is why the mirror oracle is unchanged.
	var models := [Vector2(10, 10), Vector2(11.5, 10), Vector2(10, 11.5), Vector2(11.5, 11.5)]
	var out := MovementPlanner.plan_unit_step(models, Vector2(0, 6), [], {}, false, 48.0)
	for i in range(models.size()):
		assert_vector(out[i]).is_equal_approx((models[i] as Vector2) + Vector2(0, 6), Vector2(0.0001, 0.0001))


# === Wall avoidance ===

func test_advance_substep_never_crosses_a_wall() -> void:
	# The steering primitive must never return a substep whose segment cuts through a wall.
	var walls := [[Vector2(13, 20), Vector2(19, 20)]]
	for start in [Vector2(16, 19.5), Vector2(15, 19.9), Vector2(17, 19.0)]:
		var np: Vector2 = MovementPlanner._advance_model(start, Vector2(16, 26), 0.75, walls, 48.0)
		assert_bool(MovementPlanner.path_crosses_wall(start, np, walls)).is_false()


func test_long_wall_keeps_the_unit_on_the_near_side() -> void:
	# A wide wall the unit cannot get around within its allowance: it slides ALONG the wall and never crosses it.
	var walls := [[Vector2(5, 20), Vector2(25, 20)]]
	var out := MovementPlanner.plan_unit_step([Vector2(16, 16)], Vector2(0, 8), walls, {}, false, 48.0)
	var final: Vector2 = out[0]
	assert_float(final.y).is_less(20.0)                                  # stayed south of the wall
	assert_bool(MovementPlanner.path_crosses_wall(Vector2(16, 16), final, walls)).is_false()


func test_allowance_is_never_exceeded() -> void:
	# Even while detouring around a wall, no model is displaced further than its move allowance.
	var walls := [[Vector2(13, 20), Vector2(19, 20)]]
	var out := MovementPlanner.plan_unit_step([Vector2(16, 16)], Vector2(0, 12), walls, {}, false, 48.0)
	assert_float((out[0] as Vector2).distance_to(Vector2(16, 16))).is_less_equal(12.0 + 0.01)


func test_unit_slides_around_a_short_wall_and_stays_coherent() -> void:
	# A tight 4-model block marches at a short wall; the models funnel around one end and stay in coherency.
	var walls := [[Vector2(10, 20), Vector2(16, 20)]]
	var block := [Vector2(12, 17), Vector2(14, 17), Vector2(12, 15), Vector2(14, 15)]
	var out := MovementPlanner.plan_unit_step(block, Vector2(4, 9), walls, {}, false, 48.0)
	assert_bool(MovementPlanner.is_coherent(out)).is_true()
	# The formation advanced north overall (its centroid moved toward the goal side).
	assert_float(MovementPlanner._centroid(out).y).is_greater(MovementPlanner._centroid(block).y)


# === Stuck → local A* rescue (U-pocket) ===

func test_astar_finds_a_corridor_out_of_a_u_pocket() -> void:
	var walls := _u_pocket()
	var corridor := MovementPlanner.astar_corridor(Vector2(24, 24), Vector2(24, 40), walls, {}, 48.0)
	assert_int(corridor.size()).is_greater(0)   # a way out exists (down through the opening, around, up)


func test_boxed_in_unit_uses_astar_to_escape_toward_goal() -> void:
	# Straight steering north is walled off; the A* rescue routes the unit out of the pocket (it moves, instead
	# of pinning uselessly against the top wall).
	var walls := _u_pocket()
	var unit := [Vector2(23, 24), Vector2(25, 24)]
	var out := MovementPlanner.plan_unit_step(unit, Vector2(0, 14), walls, {}, false, 48.0)
	var moved: float = MovementPlanner._centroid(out).distance_to(MovementPlanner._centroid(unit))
	assert_float(moved).is_greater(3.0)          # the rescue got the unit moving out of the pocket
	assert_bool(MovementPlanner.is_coherent(out)).is_true()


func test_astar_routes_around_an_impassable_container_cell() -> void:
	# No walls, but a CONTAINER cell blocks the A* node directly between start and goal → it routes around.
	var grid := {Vector2i(5, 5): TerrainRules.TerrainType.CONTAINER}   # inches [15,18) on both axes
	var corridor := MovementPlanner.astar_corridor(Vector2(16.5, 10), Vector2(16.5, 22), [], grid, 48.0)
	assert_int(corridor.size()).is_greater(0)
	for w in corridor:
		assert_int(int(TerrainRules.terrain_at(grid, w as Vector2))).is_not_equal(int(TerrainRules.TerrainType.CONTAINER))


# === Helpers ===

## A U-shaped impassable pocket open to the south (−y): top + left + right walls, unit sits inside.
func _u_pocket() -> Array:
	return [
		[Vector2(18, 30), Vector2(30, 30)],   # top (north) wall — blocks the direct route to a northern goal
		[Vector2(18, 20), Vector2(18, 30)],   # left wall
		[Vector2(30, 20), Vector2(30, 30)],   # right wall
	]


func test_trails_record_the_route_without_changing_the_plan() -> void:
	# The presentation layer's trail capture is pure observation: same walls, same delta — the planned
	# positions with and without a trails out-array are identical, and each trail runs start → final.
	var walls := [[Vector2(10.0, 6.0), Vector2(14.0, 6.0)]]
	var pos := [Vector2(11.0, 2.0), Vector2(12.5, 2.0)]
	var delta := Vector2(0, 8.0)
	var plain := MovementPlanner.plan_unit_step(pos, delta, walls)
	var trails: Array = []
	var traced := MovementPlanner.plan_unit_step(pos, delta, walls, {}, false, 48.0, trails)
	assert_array(traced).is_equal(plain)
	assert_int(trails.size()).is_equal(2)
	for i in range(2):
		var t := trails[i] as Array
		assert_bool(t.size() >= 2).is_true()
		assert_that(t.front()).is_equal(pos[i])
		assert_float((t.back() as Vector2).distance_to(traced[i])).is_less(0.001)


# === Base-aware obstacles (opts: clearance / zones / avoid_cells) + distance truth (final package) ===

func test_step_blocked_clearance_inflates_walls() -> void:
	# Wall along y=20 (x 10..20). A step ending 0.5" above it: fine for a point model, a clip for a
	# 1"-radius base (GF v3.5.1 p.7 — the base's outer edge may not shave the wall).
	var walls := [[Vector2(10, 20), Vector2(20, 20)]]
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 21.5), Vector2(15, 20.5), walls, {})).is_false()
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 21.5), Vector2(15, 20.5), walls, {"clearance": 1.0})).is_true()
	# A step staying 1.5" away is legal even with the 1" clearance.
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 22.5), Vector2(15, 21.5), walls, {"clearance": 1.0})).is_false()


func test_step_blocked_clearance_allows_escape_from_inside_band() -> void:
	# A model already standing 0.3" from the wall (legacy state) may step AWAY but not closer.
	var walls := [[Vector2(10, 20), Vector2(20, 20)]]
	var opts := {"clearance": 1.0}
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 20.3), Vector2(15, 20.8), walls, opts)).is_false()
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 20.3), Vector2(15, 20.1), walls, opts)).is_true()


func test_step_blocked_zone_end_pass_and_escape() -> void:
	# Enemy no-go circle at (20,20), r=3 (GF v3.5.1 p.7: never within 1" of models from other units — inflated).
	var opts := {"zones": [{"c": Vector2(20, 20), "r": 3.0}]}
	# Ending inside the zone is blocked; staying clear is free.
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 20), Vector2(19, 20), [], opts)).is_true()
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 20), Vector2(16, 20), [], opts)).is_false()
	# Passing THROUGH the zone (both endpoints outside) is blocked too.
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 20), Vector2(25, 20), [], opts)).is_true()
	# A model already inside (post-melee state) may move OUT but not deeper in.
	assert_bool(MovementPlanner.step_blocked(Vector2(19, 20), Vector2(17.5, 20), [], opts)).is_false()
	assert_bool(MovementPlanner.step_blocked(Vector2(19, 20), Vector2(19.5, 20), [], opts)).is_true()


func test_step_blocked_avoid_cells_with_escape() -> void:
	# Cell (5,5) spans x/y 15..18 (3" grid). Entering it is blocked; a model already inside may leave.
	var opts := {"avoid_cells": {Vector2i(5, 5): true}}
	assert_bool(MovementPlanner.step_blocked(Vector2(13.0, 16.5), Vector2(16.0, 16.5), [], opts)).is_true()
	assert_bool(MovementPlanner.step_blocked(Vector2(16.0, 16.5), Vector2(13.0, 16.5), [], opts)).is_false()
	assert_bool(MovementPlanner.step_blocked(Vector2(13.0, 16.5), Vector2(14.0, 16.5), [], opts)).is_false()


func test_plan_unit_step_never_ends_inside_a_zone() -> void:
	# One model heading straight at an enemy: the planned end must stay OUTSIDE the 1"-spacing zone
	# (r=3 here), and the recorded trail must never dip into it.
	var opts := {"zones": [{"c": Vector2(20, 20), "r": 3.0}]}
	var trails: Array = []
	var out := MovementPlanner.plan_unit_step([Vector2(10, 20)], Vector2(10, 0), [], {}, false, 48.0, trails, opts)
	assert_float((out[0] as Vector2).distance_to(Vector2(20, 20))).is_greater_equal(3.0 - 0.01)
	for leg_i in range(1, (trails[0] as Array).size()):
		var a: Vector2 = (trails[0] as Array)[leg_i - 1]
		var b: Vector2 = (trails[0] as Array)[leg_i]
		assert_float(MovementPlanner.point_seg_distance(Vector2(20, 20), a, b)).is_greater_equal(3.0 - 0.01)


func test_plan_unit_step_no_zones_moves_straight() -> void:
	# A board with no other units yields no zones — the pure module moves the model straight to its goal
	# (the charge call site builds body-only target zones; with nothing around, nothing deflects).
	var out := MovementPlanner.plan_unit_step([Vector2(10, 20)], Vector2(10, 0), [], {}, true, 48.0, [], {"clearance": 0.5})
	assert_float((out[0] as Vector2).distance_to(Vector2(20, 20))).is_less(0.01)


func test_plan_unit_step_charge_contacts_target_and_respects_friendly_zone() -> void:
	# Amendment ruling (GF/AoF v3.5.1 p.7): on a Charge the TARGET's model is a body-only obstacle (both
	# base radii, no 1" buffer) — the charge ends at base contact but never passes THROUGH — while every
	# OTHER unit (here a friendly bystander) keeps its full 1" zone the path must route around.
	var target_body := {"c": Vector2(20, 20), "r": 1.0}       # 0.5" + 0.5" bases, no buffer
	var friendly_full := {"c": Vector2(15, 21.5), "r": 2.0}   # 0.5" + 1" + 0.5"
	var opts := {"zones": [target_body, friendly_full]}
	var trails: Array = []
	var out := MovementPlanner.plan_unit_step([Vector2(10, 20)], Vector2(9.5, 0), [], {}, true, 48.0, trails, opts)
	var endp := out[0] as Vector2
	# Never inside the target's body; close enough for the 2" melee gate (base contact at ~1").
	assert_float(endp.distance_to(Vector2(20, 20))).is_greater_equal(1.0 - 0.01)
	assert_float(endp.distance_to(Vector2(20, 20))).is_less_equal(2.0)
	# The friendly bystander's 1" zone was never clipped along the whole route.
	var leg: Array = trails[0]
	for i in range(1, leg.size()):
		assert_float(MovementPlanner.point_seg_distance(Vector2(15, 21.5), leg[i - 1], leg[i])).is_greater_equal(2.0 - 0.01)


func test_plan_trails_arc_length_never_exceeds_allowance() -> void:
	# A wall forces a detour; the actual steered polyline still spends at most the 8" allowance.
	var walls := [[Vector2(15, 15), Vector2(15, 25)]]
	var trails: Array = []
	MovementPlanner.plan_unit_step([Vector2(10, 20)], Vector2(8, 0), walls, {}, false, 48.0, trails)
	assert_float(MovementPlanner.polyline_length(trails[0] as Array)).is_less_equal(8.0 + 0.05)


func test_polyline_length_and_trim() -> void:
	var line: Array = [Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)]
	assert_float(MovementPlanner.polyline_length(line)).is_equal_approx(7.0, 0.0001)
	# Trim to 5": the final leg is cut exactly 2" in → (3, 2); arc becomes 5.
	var cut := MovementPlanner.trim_polyline(line, 5.0)
	assert_float(MovementPlanner.polyline_length(cut)).is_equal_approx(5.0, 0.0001)
	assert_float((cut.back() as Vector2).distance_to(Vector2(3, 2))).is_less(0.0001)
	# A polyline within budget is returned whole; Vector3 points work the same (the world-trail form).
	assert_int(MovementPlanner.trim_polyline(line, 10.0).size()).is_equal(3)
	var world: Array = [Vector3(0, 0.01, 0), Vector3(0.3, 0.01, 0), Vector3(0.3, 0.01, 0.4)]
	assert_float(MovementPlanner.polyline_length(world)).is_equal_approx(0.7, 0.0001)
	var wcut := MovementPlanner.trim_polyline(world, 0.5)
	assert_float(MovementPlanner.polyline_length(wcut)).is_equal_approx(0.5, 0.0001)


func test_default_opts_keep_legacy_wall_behaviour() -> void:
	# step_blocked with {} equals path_crosses_wall — the sim's byte-identical guarantee.
	var walls := [[Vector2(10, 20), Vector2(20, 20)]]
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 19), Vector2(15, 21), walls, {})).is_true()
	assert_bool(MovementPlanner.step_blocked(Vector2(15, 20.2), Vector2(15, 21), walls, {})).is_false()
	assert_bool(MovementPlanner.rigid_blocked([Vector2(15, 19)], Vector2(0, 2), walls)).is_true()
	assert_bool(MovementPlanner.rigid_blocked([Vector2(5, 19)], Vector2(0, 2), walls)).is_false()


# === Finding 2: no model left behind (real-game opts path only) ===

func test_gather_laggards_pulls_a_parked_model_up_to_the_formation() -> void:
	# Models 0 and 1 advanced +8" north; model 2 was left parked at its start — the "only half the unit
	# moved" state. The gather pass (opts present) must pull the parked model up toward the moved pair.
	var before: Array = [Vector2(10, 10), Vector2(11, 10), Vector2(12, 10)]
	var result: Array = [Vector2(10, 18), Vector2(11, 18), Vector2(12, 10)]
	var out := MovementPlanner._gather_laggards(before, result, Vector2(0, 8), [], 48.0, {"clearance": 0.5})
	assert_float((out[2] as Vector2).y).is_greater(12.0)                                   # advanced north
	assert_float((out[2] as Vector2).distance_to(out[1] as Vector2)).is_less(MovementPlanner.SPREAD_IN)


func test_plan_unit_step_leaves_no_model_behind_around_a_zone() -> void:
	# A no-go zone squarely on the left column's northward path. A naive per-model steer would strand the
	# blocked models while the right column advances; with opts, EVERY model must advance and the unit
	# must stay coherent at the destination — within the 8" allowance (distance truth).
	var pos: Array = [Vector2(10, 10), Vector2(11.5, 10), Vector2(10, 11.5), Vector2(11.5, 11.5)]
	var opts := {"clearance": 0.4, "zones": [{"c": Vector2(10, 15), "r": 2.5}]}
	var trails: Array = []
	var out := MovementPlanner.plan_unit_step(pos, Vector2(0, 8), [], {}, false, 48.0, trails, opts)
	for i in range(pos.size()):
		assert_float((out[i] as Vector2).distance_to(pos[i])).is_greater(1.5)
		assert_float((out[i] as Vector2).distance_to(pos[i])).is_less_equal(8.0 + 0.01)
	assert_bool(MovementPlanner.is_coherent(out)).is_true()


# === Final formation guarantees: no intra-unit overlap (finding 6) + coherency shorten (finding 4) ===

func test_separate_overlaps_pushes_own_bases_apart() -> void:
	# Two 1"-radius bases only 1" apart overlap by 1"; after separation their centre gap is >= the sum of
	# radii (edge gap >= 0) — GF/AoF v3.5.1 p.7 "may never move through other models … friendly or enemy".
	var out := MovementPlanner.separate_overlaps([Vector2(10, 10), Vector2(11, 10)], [1.0, 1.0], [])
	assert_float((out[0] as Vector2).distance_to(out[1] as Vector2)).is_greater_equal(2.0 - 0.02)


func test_separate_overlaps_no_op_when_clear() -> void:
	var out := MovementPlanner.separate_overlaps([Vector2(10, 10), Vector2(13, 10)], [1.0, 1.0], [])
	assert_float((out[0] as Vector2).distance_to(out[1] as Vector2)).is_equal_approx(3.0, 0.001)


func test_separate_overlaps_splits_coincident_centres() -> void:
	# Two bases at the SAME point must still be driven apart (a deterministic axis), never left overlapping.
	var out := MovementPlanner.separate_overlaps([Vector2(5, 5), Vector2(5, 5)], [0.5, 0.5], [])
	assert_float((out[0] as Vector2).distance_to(out[1] as Vector2)).is_greater_equal(1.0 - 0.02)


func test_shorten_to_coherent_restores_a_broken_chain() -> void:
	# Start: a tight coherent pair. Planned: model 1 flung 30" out (>> SPREAD_IN) → incoherent. The shorten
	# pulls it back toward the coherent start until the 1"/9" chain holds again (GF/AoF v3.5.1 p.7; finding 4).
	var start := [Vector2(10, 10), Vector2(12, 10)]
	var planned := [Vector2(10, 10), Vector2(40, 10)]
	assert_bool(MovementPlanner.is_coherent(planned)).is_false()
	var out := MovementPlanner.shorten_to_coherent(start, planned)
	assert_bool(MovementPlanner.is_coherent(out)).is_true()
	assert_float((out[1] as Vector2).x).is_less(40.0)   # the move WAS shortened


func test_shorten_to_coherent_no_op_when_already_coherent() -> void:
	var start := [Vector2(10, 10), Vector2(12, 10)]
	var planned := [Vector2(14, 10), Vector2(16, 10)]   # advanced together, still linked
	assert_bool(MovementPlanner.is_coherent(planned)).is_true()
	var out := MovementPlanner.shorten_to_coherent(start, planned)
	assert_float((out[0] as Vector2).distance_to(planned[0])).is_less(0.001)
	assert_float((out[1] as Vector2).distance_to(planned[1])).is_less(0.001)


# === Unified pipeline: C-space inflation + Theta*/funnel + the unified constraint solver ======
# (the pathfinding-research rewrite; real-game path, gated on opts["radii"])

func test_cspace_theta_star_routes_clear_of_an_inflated_wall() -> void:
	# Configuration-space inflation (research §1.6): a vertical wall the straight line would cross. With
	# base-radius clearance the any-angle route + string-pull rounds the wall END no closer than the base
	# radius — so a POINT that clears the inflated wall clears the REAL wall by >= radius (no shaving/snag).
	var walls := [[Vector2(20, 14), Vector2(20, 26)]]
	var opts := {"clearance": 1.0}
	var route := MovementPlanner.theta_star(Vector2(16, 20), Vector2(24, 20), walls, {}, 48.0, opts)
	var taut := MovementPlanner.string_pull(route, walls, {}, opts)
	assert_int(taut.size()).is_greater(2)   # it bent AROUND the wall (not a straight shot through it)
	var wa := Vector2(20, 14)
	var wb := Vector2(20, 26)
	for i in range(1, taut.size()):
		# every taut leg keeps the base radius clear of the real wall (the c-space guarantee, by construction)
		assert_float(MovementPlanner.seg_seg_distance(taut[i - 1], taut[i], wa, wb)).is_greater_equal(1.0 - 0.1)
	# and no leg actually crosses the wall
	for i in range(1, taut.size()):
		assert_bool(MovementPlanner.path_crosses_wall(taut[i - 1], taut[i], walls)).is_false()


func test_theta_star_funnel_taut_path_routes_around_terrain_within_band() -> void:
	# Container-Welle (2026-07-22): die Kiste ist EXAKTE Wand-Geometrie, keine INF-Zelle mehr —
	# der Planner umfährt ihre OBB-Kanten (dieselbe Ein-Wahrheits-Pipeline wie das echte Spiel).
	# Szenario unverändert: 3x3-Box quer auf der Direktlinie, Route muss taut außen herum.
	var walls := [
		[Vector2(21, 18), Vector2(24, 18)], [Vector2(24, 18), Vector2(24, 21)],
		[Vector2(24, 21), Vector2(21, 21)], [Vector2(21, 21), Vector2(21, 18)],
	]
	var start := Vector2(22.5, 16.0)
	var goal := Vector2(22.5, 23.0)
	var opts := {"clearance": 0.2}
	var route := MovementPlanner.theta_star(start, goal, walls, {}, 48.0, opts)
	var taut := MovementPlanner.string_pull(route, walls, {}, opts)
	assert_int(taut.size()).is_greater(2)                          # detoured (not the blocked straight line)
	for i in range(1, taut.size()):
		assert_bool(MovementPlanner.path_crosses_wall(taut[i - 1], taut[i], walls)).is_false()
	assert_float((taut[0] as Vector2).distance_to(start)).is_less(0.001)
	assert_float((taut.back() as Vector2).distance_to(goal)).is_less(0.001)
	assert_float(MovementPlanner.polyline_length(taut)).is_less(12.0)   # taut, well within a 12" rush band


func test_theta_star_routes_around_dangerous_ground_when_detour_is_cheap() -> void:
	# Dangerous ground never hard-blocks, so the OLD early-out returned the straight line without ever
	# searching — the soft costs were dead code on the direct path and the unit walked through and took
	# wounds (field report). With the path-integral segment costs + the soft-cost-aware early-out the search
	# runs and prefers the cheap open-ground detour, and string_pull must not drag it back through.
	var grid := {}
	for cx in range(5, 9):   # dangerous strip x[15,27), y[18,21)
		grid[Vector2i(cx, 6)] = TerrainRules.TerrainType.DANGEROUS
	var start := Vector2(21.0, 16.0)
	var goal := Vector2(21.0, 23.0)
	var route := MovementPlanner.theta_star(start, goal, [], grid, 48.0, {})
	var taut := MovementPlanner.string_pull(route, [], grid, {})
	assert_int(taut.size()).is_greater(2)   # it detoured — not the straight line through the field
	# The straight line spends ~3" inside the field; the detour must spend (almost) none. Measure by sampling.
	assert_float(_dangerous_length(grid, [start, goal])).is_greater(2.5)   # sanity: the direct line crosses it
	assert_float(_dangerous_length(grid, taut)).is_less(1.0)              # the planned route stays (nearly) clear


func test_dangerous_detour_still_found_under_the_sweep_cap() -> void:
	# The interactive game runs the BOUNDED planner (fast_planner, 320-expansion cap): the detour must still
	# form under the cap. The cap was NOT the cause of the dangerous walk-through (the soft-cost blindness
	# was), and raising it costs ~5x runtime (measured 320→88s vs 2400→456s per arena game) — so this test
	# pins the fast path's route quality at the tight cap.
	var grid := {}
	for cx in range(5, 9):
		grid[Vector2i(cx, 6)] = TerrainRules.TerrainType.DANGEROUS
	MovementPlanner.fast_planner = true
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	var route := MovementPlanner.theta_star(Vector2(21.0, 16.0), Vector2(21.0, 23.0), [], grid, 48.0, {})
	var taut := MovementPlanner.string_pull(route, [], grid, {})
	MovementPlanner.fast_planner = false   # reset the static BEFORE asserting — a failure must not leak state
	assert_float(_dangerous_length(grid, taut)).is_less(1.0)


func test_untangle_endpoints_swaps_crossed_pairs_only_when_legal() -> void:
	# Crossed pair (A→B's spot, B→A's spot): the swap shortens both chords → untangled.
	var starts: Array = [Vector2(0, 0), Vector2(4, 0)]
	var ends: Array = [Vector2(4, 6), Vector2(0, 6)]
	var swapped := MovementPlanner.untangle_endpoints(starts, ends, [0.5, 0.5], 12.0)
	assert_bool(swapped).is_true()
	assert_vector(ends[0] as Vector2).is_equal(Vector2(0, 6))
	assert_vector(ends[1] as Vector2).is_equal(Vector2(4, 6))
	# Unequal radii: never swapped (a big base must not inherit a small base's spot).
	var ends2: Array = [Vector2(4, 6), Vector2(0, 6)]
	assert_bool(MovementPlanner.untangle_endpoints(starts, ends2, [0.5, 1.0], 12.0)).is_false()
	# Over-allowance: a swap that would grant an illegal move length is rejected.
	var ends3: Array = [Vector2(4, 6), Vector2(0, 6)]
	assert_bool(MovementPlanner.untangle_endpoints(starts, ends3, [0.5, 0.5], 5.0)).is_false()
	# Already parallel: nothing to do.
	var ends4: Array = [Vector2(0, 6), Vector2(4, 6)]
	assert_bool(MovementPlanner.untangle_endpoints(starts, ends4, [0.5, 0.5], 12.0)).is_false()


func test_untangle_endpoints_rejects_wall_cutting_swaps() -> void:
	# Mirror-ladder audit (ONIs/Warriors): the swap chord must not tunnel a ruin corner the original
	# routes went around. Wall between the crossed pair: swapping would send BOTH chords through it.
	var starts: Array = [Vector2(0, 0), Vector2(4, 0)]
	var ends: Array = [Vector2(4, 6), Vector2(0, 6)]
	var wall := [[Vector2(-1.0, 3.0), Vector2(1.0, 3.0)]]   # bar across model 0's swap chord (0,0)→(0,6)
	var oi := {"clearance": 0.5}
	assert_bool(MovementPlanner.untangle_endpoints(starts, ends, [0.5, 0.5], 12.0, wall, oi)).is_false()
	assert_vector(ends[0] as Vector2).is_equal(Vector2(4, 6))   # untouched — swap rejected
	# The same crossed pair with the wall far away still untangles (wall gate is not a blanket off-switch).
	var ends2: Array = [Vector2(4, 6), Vector2(0, 6)]
	var far_wall := [[Vector2(20.0, 3.0), Vector2(22.0, 3.0)]]
	assert_bool(MovementPlanner.untangle_endpoints(starts, ends2, [0.5, 0.5], 12.0, far_wall, oi)).is_true()
	assert_vector(ends2[0] as Vector2).is_equal(Vector2(0, 6))


## Sampled length (inches) of `poly` spent inside DANGEROUS cells of `grid` — the test's route-quality probe.
func _dangerous_length(grid: Dictionary, poly: Array) -> float:
	var total := 0.0
	for i in range(1, poly.size()):
		var a: Vector2 = poly[i - 1]
		var b: Vector2 = poly[i]
		var steps := maxi(2, int(ceil(a.distance_to(b) / 0.25)))
		var sub := a.distance_to(b) / float(steps)
		for s in range(steps):
			var p := a.lerp(b, (float(s) + 0.5) / float(steps))
			if int(grid.get(TerrainRules.cell_of(p, TerrainRules.CELL_IN), TerrainRules.TerrainType.NONE)) == TerrainRules.TerrainType.DANGEROUS:
				total += sub
	return total


func test_unified_solver_resolves_overlap_coherency_and_terrain_together() -> void:
	# The hard cluster the OLD passes could not solve without a trade (nightloop evidence): three overlapping
	# bases ALL sitting in one forbidden (no-rest) cell. The unified solver must end with NO base overlap AND
	# unit coherency AND no model resting in forbidden terrain — all three simultaneously.
	var forbid := {Vector2i(20, 20): true}   # the 1" cell x[20,21), y[20,21)
	var desired: Array = [Vector2(20.4, 20.0), Vector2(20.8, 20.0), Vector2(20.0, 20.0)]   # overlap + all in cell
	var radii: Array = [0.5, 0.5, 0.5]
	var opts := {"radii": radii, "forbid_cells": forbid}
	var out := MovementPlanner.solve_formation(desired, radii, [], opts, 48.0, false)
	for i in range(out.size()):
		for j in range(i + 1, out.size()):
			assert_float((out[i] as Vector2).distance_to(out[j])).is_greater_equal(radii[i] + radii[j] - 0.05)
	assert_bool(MovementPlanner.is_coherent(out)).is_true()
	for p in out:
		assert_bool(forbid.has(TerrainRules.cell_of(p as Vector2, MovementPlanner.PLAN_CELL_IN))).is_false()


func test_collinear_pin_escapes_via_cspace_inflation() -> void:
	# The collinear-pin degenerate (research §3.2): two wall ends leave a 1" gap straight ahead — narrower
	# than the base DIAMETER (2 × 0.85"). A point planner threads it and freezes; c-space inflation merges the
	# gap so the model advances to the barrier and STOPS CLEANLY (never stalls), without crossing the wall.
	var walls := [[Vector2(10, 20), Vector2(19.5, 20)], [Vector2(20.5, 20), Vector2(30, 20)]]
	var opts := {"radii": [0.75], "clearance": 0.85}
	var trails: Array = []
	var out := MovementPlanner.plan_unit_step([Vector2(20, 24)], Vector2(0, -8), walls, {}, false, 48.0, trails, opts)
	var final: Vector2 = out[0]
	assert_float(Vector2(20, 24).distance_to(final)).is_greater(1.0)   # it advanced (did NOT freeze in place)
	assert_float(final.y).is_greater(20.0)                             # stopped on the near side of the wall
	assert_bool(MovementPlanner.path_crosses_wall(Vector2(20, 24), final, walls)).is_false()


# === Sequential per-model flow (field-test round 6, finding 7 — the maintainer's design) ===

func test_sequential_flow_threads_a_narrow_gap_that_the_rigid_slide_jams() -> void:
	# A wall along y=20 with a single 2" gap at x∈[19,21]; a coherent 3-model line (2" spacing) must reach the
	# far side. The RIGID translation jams — the two flanking models' straight paths drive INTO the wall. The
	# sequential flow orders the models nearest-destination-first and files them THROUGH the gap one at a time,
	# so all three clear the wall, no route crosses it, and the unit ends coherent (progressive coherency).
	var walls := [[Vector2(6, 20), Vector2(19, 20)], [Vector2(21, 20), Vector2(30, 20)]]
	var start := [Vector2(18, 26), Vector2(20, 26), Vector2(22, 26)]
	var delta := Vector2(0, -12)
	var radii: Array = [0.5, 0.5, 0.5]
	var opts := {"radii": radii, "clearance": 0.6}
	assert_bool(MovementPlanner.is_coherent(start)).is_true()                       # premise: starts coherent
	# The naive rigid slide jams: both flanking models' straight paths cross the wall.
	assert_bool(MovementPlanner.path_crosses_wall(start[0], (start[0] as Vector2) + delta, walls)).is_true()
	assert_bool(MovementPlanner.path_crosses_wall(start[2], (start[2] as Vector2) + delta, walls)).is_true()
	var trails: Array = []
	var order: Array = []
	var out := MovementPlanner.plan_sequential_flow(start, delta, radii, walls, {}, opts, 48.0, false, trails, order)
	for p in out:
		assert_float((p as Vector2).y).is_less(20.0)                                # every model cleared the wall
	for leg in trails:
		var poly := leg as Array
		for i in range(1, poly.size()):
			assert_bool(MovementPlanner.path_crosses_wall(poly[i - 1], poly[i], walls)).is_false()
	assert_bool(MovementPlanner.is_coherent(out)).is_true()                         # ends coherent (filed together)


func test_sequential_flow_order_is_nearest_destination_first_and_deterministic() -> void:
	# Destination = centroid + delta = (10, 19). Models at y 30/20/25 → distances 11/1/6 → order 1, 2, 0.
	# Re-running yields the identical order (the sort's index tie-break makes it a total order).
	var start := [Vector2(10, 30), Vector2(10, 20), Vector2(10, 25)]
	var delta := Vector2(0, -6)
	var radii: Array = [0.5, 0.5, 0.5]
	var opts := {"radii": radii}
	var order1: Array = []
	MovementPlanner.plan_sequential_flow(start, delta, radii, [], {}, opts, 48.0, false, [], order1)
	assert_array(order1).is_equal([1, 2, 0])
	var order2: Array = []
	MovementPlanner.plan_sequential_flow(start, delta, radii, [], {}, opts, 48.0, false, [], order2)
	assert_array(order2).is_equal(order1)


func test_sequential_flow_open_field_matches_the_rigid_slide() -> void:
	# With nothing in the way each model files straight to its slot, so the flow equals the rigid translation
	# (why an unobstructed AI move is unchanged and the presentation just glides them in order).
	var start := [Vector2(10, 20), Vector2(11, 20), Vector2(12, 20)]
	var delta := Vector2(5, 0)
	var radii: Array = [0.5, 0.5, 0.5]
	var out := MovementPlanner.plan_sequential_flow(start, delta, radii, [], {}, {"radii": radii}, 48.0, false, [], [])
	for i in range(3):
		assert_float((out[i] as Vector2).distance_to((start[i] as Vector2) + delta)).is_less(0.05)
	assert_bool(MovementPlanner.is_coherent(out)).is_true()


# === Round 7, finding 2: flow-movement quality (packed squads must COMMIT to their advance) ===

func test_packed_ten_model_squad_advances_close_to_full_band() -> void:
	# A 10-model squad in two ranks of five, bases (r = 0.5") packed to EXACT contact — precisely what the
	# deploy grid produces. Before the fix the lead model's tangent first step read as blocked (its
	# neighbours' un-shaved body zones), it stalled at its start, and the progressive coherency then pulled
	# every later model back to it: the whole advance collapsed to a token sub-inch move (the maintainer's
	# "10-model squad moves half an inch"). Open field → the centroid must cover close to the 6" band.
	var pos: Array = []
	var radii: Array = []
	for row in range(2):
		for col in range(5):
			pos.append(Vector2(20.0 + col * 1.0, 20.0 + row * 1.0))
			radii.append(0.5)
	var out := MovementPlanner.plan_unit_step(pos, Vector2(0, 6), [], {}, false, 48.0, [], {"radii": radii})
	var moved: Vector2 = MovementPlanner._centroid(out) - MovementPlanner._centroid(pos)
	assert_float(moved.y).is_greater(5.0)
	# No residual overlap: every pair keeps at least its bases' contact distance (minus float noise).
	for i in range(out.size()):
		for j in range(i + 1, out.size()):
			assert_float((out[i] as Vector2).distance_to(out[j] as Vector2)).is_greater(0.9)


func test_exact_contact_pair_slides_forward_full_band() -> void:
	# Two bases at exact contact moving in parallel: the tangent step along each other's body zone must
	# not read as blocked (CONTACT_SLIDE_EPS_IN) — both models cover the full band.
	var pos: Array = [Vector2(20, 20), Vector2(21, 20)]
	var out := MovementPlanner.plan_unit_step(pos, Vector2(0, 6), [], {}, false, 48.0, [], {"radii": [0.5, 0.5]})
	assert_float((out[0] as Vector2).y).is_greater(25.5)
	assert_float((out[1] as Vector2).y).is_greater(25.5)


func test_boxed_lead_model_is_deferred_and_the_unit_still_advances() -> void:
	# The model NEAREST the destination sits in a U-shaped wall pocket opening backward: its own route is
	# genuinely stuck. Before the fix it filed FIRST, achieved ~nothing, and anchored the whole unit (every
	# later model was coherency-pulled back to it). With the lead-stall deferral it files LAST and the other
	# nine models commit to the advance — the unit centroid still covers most of the band.
	var pos: Array = []
	var radii: Array = []
	for row in range(2):
		for col in range(5):
			pos.append(Vector2(20.0 + col * 1.0, 20.0 + row * 1.0))
			radii.append(0.5)
	# U-pocket around the front-middle model at (22, 21): walls left/right/top, open to the south.
	var walls := [
		[Vector2(21.3, 20.3), Vector2(21.3, 22.3)],
		[Vector2(22.7, 20.3), Vector2(22.7, 22.3)],
		[Vector2(21.3, 22.3), Vector2(22.7, 22.3)],
	]
	var opts := {"radii": radii, "clearance": 0.5}
	var out := MovementPlanner.plan_unit_step(pos, Vector2(0, 6), walls, {}, false, 48.0, [], opts)
	var moved: Vector2 = MovementPlanner._centroid(out) - MovementPlanner._centroid(pos)
	# Without the deferral this centroid managed ~1.8" (measured on the pre-fix planner); with the boxed
	# lead filing last the unit commits to ~3" while staying chained to the marooned model (coherency).
	assert_float(moved.y).is_greater(2.5)


# === Bug-31 charge battery (maintainer image spec 2026-07-19): a charge must fan into a battle
# line at base CONTACT, on a near-direct path, and may never route THROUGH the target's bases. ===

func _charge_flow(mpos: Array, radii: Array, tgt_bases: Array, band_in: float,
		walls: Array = []) -> Dictionary:
	var centre := Vector2.ZERO
	for tb in tgt_bases:
		centre += tb[0] as Vector2
	centre /= float(tgt_bases.size())
	var ucentre := Vector2.ZERO
	for p in mpos:
		ucentre += p as Vector2
	ucentre /= float(mpos.size())
	var delta := (centre - ucentre).limit_length(band_in)
	var opts := {"clearance": float(radii[0]) + 0.05, "radii": radii,
		"charge_allowance": band_in, "charge_goal": centre,
		"charge_tgt_bases": tgt_bases,
		"charge_slots": MovementPlanner.charge_contact_slots(mpos, radii, tgt_bases)}
	var trails: Array = []
	trails.resize(mpos.size())
	var order: Array = []
	var out := MovementPlanner.plan_sequential_flow(mpos, delta, radii, walls, {}, opts, 48.0, true, trails, order)
	return {"out": out, "trails": trails}


func test_charge_slots_are_distinct_and_on_contact_circles() -> void:
	var mpos := [Vector2(10, 10), Vector2(12, 10), Vector2(14, 10)]
	var radii := [0.5, 0.5, 0.5]
	var tgt := [[Vector2(12, 19), 0.5], [Vector2(14, 19), 0.5]]
	var slots := MovementPlanner.charge_contact_slots(mpos, radii, tgt)
	assert_int(slots.size()).is_equal(3)
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			assert_float((slots[i] as Vector2).distance_to(slots[j] as Vector2)).is_greater(0.9)
		var on_circle := false
		for tb in tgt:
			var d: float = (slots[i] as Vector2).distance_to(tb[0] as Vector2)
			if absf(d - (float(tb[1]) + 0.5)) < 0.01:
				on_circle = true
		assert_bool(on_circle).override_failure_message("slot %d not on a contact circle" % i).is_true()


func test_charge_line_ends_in_contact_not_column() -> void:
	# 5 orcs, 3" gap to a 3-model line — the fixed charge must kiss (gap ~0) and fan WIDE, not queue.
	var mpos := [Vector2(8, 10), Vector2(10, 10), Vector2(12, 10), Vector2(14, 10), Vector2(16, 10)]
	var radii := [0.5, 0.5, 0.5, 0.5, 0.5]
	var tgt := [[Vector2(10, 14), 0.5], [Vector2(12, 14), 0.5], [Vector2(14, 14), 0.5]]
	var r := _charge_flow(mpos, radii, tgt, 12.0)
	var out: Array = r["out"]
	var contacts := 0
	for i in out.size():
		var best := INF
		for tb in tgt:
			best = minf(best, (out[i] as Vector2).distance_to(tb[0] as Vector2) - 0.5 - float(tb[1]))
		if best <= 0.15:
			contacts += 1
		# never INSIDE a target base (deeper than the slide eps)
		for tb in tgt:
			assert_float((out[i] as Vector2).distance_to(tb[0] as Vector2))\
				.is_greater(0.5 + float(tb[1]) - 0.12)
	assert_int(contacts).override_failure_message("nur %d/5 in Kontakt: %s" % [contacts, str(out)]).is_greater_equal(3)
	# battle line, not Säule: lateral spread must beat approach depth
	var xs: Array = []
	var ys: Array = []
	for p in out:
		xs.append((p as Vector2).x)
		ys.append((p as Vector2).y)
	var spread: float = xs.max() - xs.min()
	var depth: float = ys.max() - ys.min()
	assert_float(spread / maxf(depth, 0.001)).override_failure_message(
		"Säule: spread %.1f depth %.1f" % [spread, depth]).is_greater(1.0)


func test_charge_path_never_cuts_through_target_unit() -> void:
	# Goal centre sits BEHIND the target's front line — routes must bend to the near face, not
	# tunnel between/through the front bases (the maintainer's 'hinter die Einheit gelaufen').
	var mpos := [Vector2(11, 8), Vector2(13, 8)]
	var radii := [0.5, 0.5]
	var tgt := [[Vector2(11, 14), 0.6], [Vector2(12.5, 14), 0.6], [Vector2(14, 14), 0.6]]
	var r := _charge_flow(mpos, radii, tgt, 12.0)
	for t in r["trails"]:
		var pts := t as Array
		for i in range(maxi(0, pts.size() - 1)):
			var a := pts[i] as Vector2
			var b := pts[i + 1] as Vector2
			for tb in tgt:
				var c := tb[0] as Vector2
				var dmin := absf((b - a).normalized().orthogonal().dot(c - a)) if a.distance_to(b) > 0.001 else a.distance_to(c)
				var t_par := clampf((c - a).dot(b - a) / maxf(a.distance_squared_to(b), 0.0001), 0.0, 1.0)
				var closest := a + (b - a) * t_par
				assert_float(closest.distance_to(c)).override_failure_message(
					"Pfad schneidet Ziel-Base bei %s" % str(c)).is_greater(0.5 + float(tb[1]) - 0.15)


func test_charge_direct_path_stays_near_direct() -> void:
	# Open field, 6" gap, full 12" band available: the arc must not balloon (16"-Bogen defect).
	var mpos := [Vector2(10, 10), Vector2(12, 10)]
	var radii := [0.5, 0.5]
	var tgt := [[Vector2(10, 17), 0.5], [Vector2(12, 17), 0.5]]
	var r := _charge_flow(mpos, radii, tgt, 12.0)
	for i in mpos.size():
		var pts := r["trails"][i] as Array
		if pts.size() < 2:
			continue
		var plen := 0.0
		for k in range(pts.size() - 1):
			plen += (pts[k] as Vector2).distance_to(pts[k + 1] as Vector2)
		var direct := (pts[0] as Vector2).distance_to(pts[pts.size() - 1] as Vector2)
		assert_float(plen / maxf(direct, 0.001)).override_failure_message(
			"Bogen: Pfad %.1f vs direkt %.1f" % [plen, direct]).is_less(1.25)


func test_charge_horde_surrounds_a_single_big_base() -> void:
	# 6 movers vs ONE vehicle base: the slot fan must wrap around so at least 5 reach contact.
	var mpos := [Vector2(8, 10), Vector2(10, 10), Vector2(12, 10), Vector2(14, 10), Vector2(16, 10), Vector2(12, 8)]
	var radii := [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
	var tgt := [[Vector2(12, 15), 1.2]]
	var r := _charge_flow(mpos, radii, tgt, 12.0)
	var contacts := 0
	for p in r["out"]:
		if (p as Vector2).distance_to(Vector2(12, 15)) - 0.5 - 1.2 <= 0.15:
			contacts += 1
	assert_int(contacts).override_failure_message("nur %d/6 am Ring" % contacts).is_greater_equal(5)


# === Testspiel-Welle 3 (2026-07-22): base-kanten-bewusste Terrain-Vermeidung (avoid_fine) ===

func test_step_blocked_honours_fine_avoid_set_with_escape() -> void:
	var fine := {Vector2i(10, 10): true}   # 1"-Zelle bei (10..11, 10..11)
	var opts := {"avoid_fine": fine}
	# Schritt IN die Fein-Zelle: blockiert.
	assert_bool(MovementPlanner.step_blocked(Vector2(9.5, 10.5), Vector2(10.5, 10.5), [], opts)).is_true()
	# Schritt AUS der Fein-Zelle heraus (Escape-Semantik): erlaubt.
	assert_bool(MovementPlanner.step_blocked(Vector2(10.5, 10.5), Vector2(12.5, 10.5), [], opts)).is_false()
	# Schritt fernab: frei.
	assert_bool(MovementPlanner.step_blocked(Vector2(20, 20), Vector2(21, 20), [], opts)).is_false()


func test_terrain_cost_inf_inside_fine_avoid_cell() -> void:
	var opts := {"avoid_fine": {Vector2i(5, 5): true}}
	var grid := {Vector2i(0, 0): TerrainRules.TerrainType.NONE}   # non-empty → kein Early-Out
	assert_bool(is_inf(MovementPlanner._terrain_cost_at(Vector2(5.5, 5.5), grid, opts))).is_true()
	assert_bool(is_inf(MovementPlanner._terrain_cost_at(Vector2(8.5, 5.5), grid, opts))).is_false()


# === Container-Welle (2026-07-22): die 6x3-Box ist exakte Wand-Geometrie, kein Zell-Fettfeld ===

func test_container_edges_block_crossing_but_allow_tight_hug() -> void:
	# Box-Kanten als Wände: 6" x 3" Rechteck um (20, 20).
	var walls := [
		[Vector2(17, 18.5), Vector2(23, 18.5)], [Vector2(23, 18.5), Vector2(23, 21.5)],
		[Vector2(23, 21.5), Vector2(17, 21.5)], [Vector2(17, 21.5), Vector2(17, 18.5)],
	]
	var opts := {"clearance": 0.55}
	# Quer durch die Box: blockiert.
	assert_bool(MovementPlanner.step_blocked(Vector2(20, 15), Vector2(20, 25), walls, opts)).is_true()
	# Enges Vorbeifahren mit Basen-Clearance: 0.7" neben der Kante ist frei (exakt, kein 3"-Aufschlag).
	assert_bool(MovementPlanner.step_blocked(Vector2(24.0, 15), Vector2(24.0, 25), walls, opts)).is_false()
	# Streifen INNERHALB der Clearance (0.3" neben der Kante): blockiert.
	assert_bool(MovementPlanner.step_blocked(Vector2(23.3, 15), Vector2(23.3, 25), walls, opts)).is_true()
