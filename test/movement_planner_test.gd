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
