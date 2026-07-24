extends GdUnitTestSuite
## Solo-AI M2 (goal 001 P2): AiDeployment — the pure OPR v3.5.0 AI-deployment core. Seeded RNG per the
## solo conventions, so every assertion is reproducible.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_split_into_groups_equal_as_possible_and_complete() -> void:
	var groups := AiDeployment.split_into_groups(10, _rng(7))
	assert_int(groups.size()).is_equal(3)
	# 10 → 4/3/3 and every index exactly once.
	var sizes: Array = [groups[0].size(), groups[1].size(), groups[2].size()]
	sizes.sort()
	assert_array(sizes).is_equal([3, 3, 4])
	var seen := {}
	for g in groups:
		for i in g:
			seen[int(i)] = true
	assert_int(seen.size()).is_equal(10)


func test_split_is_deterministic_under_a_seed() -> void:
	assert_array(AiDeployment.split_into_groups(9, _rng(42))).is_equal(AiDeployment.split_into_groups(9, _rng(42)))


func test_assign_sections_never_all_same_and_in_range() -> void:
	for seed_value in range(30):
		var sections := AiDeployment.assign_sections(3, _rng(seed_value))
		assert_int(sections.size()).is_equal(3)
		var all_same := true
		for s in sections:
			assert_int(int(s)).is_between(1, 3)
			if int(s) != int(sections[0]):
				all_same = false
		assert_bool(all_same).is_false()


func test_section_rect_splits_zone_into_thirds_along_edge() -> void:
	var zone := Rect2(Vector2(-0.6, 0.3), Vector2(1.2, 0.3))   # 4x1 ft strip in metres
	assert_that(AiDeployment.section_rect(zone, 1)).is_equal(Rect2(Vector2(-0.6, 0.3), Vector2(0.4, 0.3)))
	assert_that(AiDeployment.section_rect(zone, 2)).is_equal(Rect2(Vector2(-0.2, 0.3), Vector2(0.4, 0.3)))
	assert_that(AiDeployment.section_rect(zone, 3)).is_equal(Rect2(Vector2(0.2, 0.3), Vector2(0.4, 0.3)))


func test_placement_order_scouts_last_ambush_reserved() -> void:
	var units: Array = [
		{"id": "a", "scout": false, "ambush": false},
		{"id": "s1", "scout": true, "ambush": false},
		{"id": "b", "scout": false, "ambush": false},
		{"id": "amb", "scout": false, "ambush": true},
		{"id": "s2", "scout": true, "ambush": false},
	]
	var order := AiDeployment.placement_order(units, _rng(3))
	assert_int(order.size()).is_equal(4)          # ambush excluded (reserve)
	assert_bool(order.has("amb")).is_false()
	# The two scouts occupy the LAST two slots (order among them random but after all others).
	var tail: Array = [str(order[2]), str(order[3])]
	tail.sort()
	assert_array(tail).is_equal(["s1", "s2"])


func test_best_spot_moves_toward_nearest_objective_and_respects_occupancy() -> void:
	var section := Rect2(Vector2(0, 0), Vector2(1, 1))
	var objective := [Vector2(0.5, 2.0)]   # south of the section → best spot hugs the south edge, centred
	var spot := AiDeployment.best_spot(section, objective, [], 0.05, Callable(), 0.05)
	assert_float(spot.y).is_greater(0.85)
	assert_float(absf(spot.x - 0.5)).is_less(0.11)
	# Occupy that spot → the next unit settles beside it, not on top.
	var spot2 := AiDeployment.best_spot(section, objective, [{"pos": spot, "radius": 0.05}], 0.05, Callable(), 0.05)
	assert_bool(spot2.distance_to(spot) >= 0.1).is_true()


func test_best_spot_respects_terrain_callback() -> void:
	var section := Rect2(Vector2(0, 0), Vector2(1, 1))
	var objective := [Vector2(0.5, 2.0)]
	# The whole south half is difficult terrain → a normal unit must stay in the north half.
	var blocked := func(p: Vector2) -> bool: return p.y > 0.5
	var spot := AiDeployment.best_spot(section, objective, [], 0.05, blocked, 0.05)
	assert_float(spot.y).is_less_equal(0.5)
	# A Strider/Flying unit (no callback) ignores it and gets the closer southern spot.
	var free_spot := AiDeployment.best_spot(section, objective, [], 0.05, Callable(), 0.05)
	assert_float(free_spot.y).is_greater(0.5)


## Field-test finding 3: a unit's FOOTPRINT (not just its centre) must clear blocking terrain — the check
## samples the footprint's diagonal CORNERS, so a spot whose corner dips into a wall/forest is rejected
## even when its centre and cardinal edges are clear.
func test_best_spot_rejects_footprint_corner_in_blocking_terrain() -> void:
	var section := Rect2(Vector2(0, 0), Vector2(1, 1))
	var objective := [Vector2(1.0, 1.0)]   # SE corner — pulls placement toward the blocked wedge
	var probe := 0.1
	# A blocking wedge in the far SE: reachable only by a footprint whose NE/SE corner overlaps it.
	var blocked := func(p: Vector2) -> bool: return p.x > 0.82 and p.y > 0.82
	var spot := AiDeployment.best_spot(section, objective, [], 0.05, blocked, 0.05, probe)
	assert_bool(spot != Vector2.INF).is_true()
	# The centre is clear AND no sampled footprint point (incl. the diagonal corners) lands in the wedge.
	assert_bool(bool(blocked.call(spot))).is_false()
	assert_bool(AiDeployment._blocked_at(spot, blocked, probe)).is_false()


## Field-test finding 1: with an explicit per-model FOOTPRINT (the offsets each model will occupy) EVERY
## model's base — centre plus its base-edge points — must clear blocking terrain, so a spread-formation
## model can't land in terrain that sits between coarse footprint-circle samples.
func test_blocked_at_checks_every_model_of_a_footprint() -> void:
	# A blocking strip at x >= 0.09. The anchor (0.0) is clear, but a model at offset +0.10 lands in it.
	var blocked := func(p: Vector2) -> bool: return p.x >= 0.09
	var footprint := [Vector2(0.0, 0.0), Vector2(0.10, 0.0), Vector2(-0.10, 0.0)]
	# Centre-only would pass (0.0 clear), but the +0.10 model is inside the strip → blocked.
	assert_bool(AiDeployment._blocked_at(Vector2(0.0, 0.0), blocked, 0.0, footprint, 0.016)).is_true()
	# Shift the anchor west so every model (incl. base edge at +0.016) stays clear of the strip.
	assert_bool(AiDeployment._blocked_at(Vector2(-0.20, 0.0), blocked, 0.0, footprint, 0.016)).is_false()
	# A model whose BASE edge (radius) just touches the strip is caught even if its centre is clear.
	var edge_case := func(p: Vector2) -> bool: return p.x >= 0.105
	assert_bool(AiDeployment._blocked_at(Vector2(0.0, 0.0), edge_case, 0.0, [Vector2(0.10, 0.0)], 0.016)).is_true()


# === Terrain-choked last resort: least-blocked ground, never a blind dump into terrain (finding 1) ===

func test_least_blocked_spot_prefers_clear_ground_over_blocking() -> void:
	# The left half of the zone is blocking terrain; the least-blocked spot must land on the CLEAR right half
	# (zero blocked footprint points), never inside the blocked strip (field-test finding 1: the old last
	# resort dumped the unit at the section centre, which sat inside a ruin).
	var zone := Rect2(Vector2(0.0, 0.0), Vector2(4.0, 2.0))
	var blocked := func(p: Vector2) -> bool: return p.x < 2.0
	var spot := AiDeployment.least_blocked_spot(zone, [], 0.2, blocked, 0.2, 0.1, [])
	assert_float(spot.x).is_greater_equal(2.0)


func test_least_blocked_spot_always_returns_a_finite_spot() -> void:
	# Even when the WHOLE zone blocks (a terrain-choked table), a unit MUST still deploy — a finite spot is
	# returned (the least-bad ground), never Vector2.INF.
	var zone := Rect2(Vector2(0.0, 0.0), Vector2(2.0, 2.0))
	var all_blocked := func(_p: Vector2) -> bool: return true
	var spot := AiDeployment.least_blocked_spot(zone, [], 0.5, all_blocked, 0.5, 0.1, [])
	assert_bool(spot.x != INF and spot.y != INF).is_true()


# === Bug 29: the terrain check must fully cover a LARGE base disc (no dangerous cell hides under it) ===

func test_blocked_at_catches_dangerous_under_a_large_base() -> void:
	# A single 3"x3" (0.0762m) dangerous cell centred ~1" from a large 2" base's centre — it overlaps the
	# base disc but sits BETWEEN the old 9 edge/centre samples. The dense disc sampler must catch it.
	var base_r := 0.0508   # 2" radius (a large monster base)
	var danger_c := Vector2(0.03, 0.0)   # ~1.2" off-centre — interior of the disc, missed by the 9-point check
	var half := 0.0381     # half a 3" cell
	var blocked := func(p: Vector2) -> bool:
		return absf(p.x - danger_c.x) <= half and absf(p.y - danger_c.y) <= half
	# Single-model footprint at the base centre.
	assert_bool(AiDeployment._blocked_at(Vector2.ZERO, blocked, base_r, [Vector2.ZERO], base_r)).is_true()


func test_disc_sampler_reduces_to_nine_points_for_a_small_base() -> void:
	# A small base (radius below one sample step) keeps the cheap 9-point check — no needless densifying.
	var small := AiDeployment._disc_sample_offsets(0.02)
	assert_int(small.size()).is_equal(9)
	# A large base densifies well beyond 9 samples.
	assert_int(AiDeployment._disc_sample_offsets(0.0508).size()).is_greater(9)


# === Bug-19-Deploy-Welle (2026-07-22): per-Achsen-Ränder statt Umkreis-Inset ===

func test_footprint_margins_use_per_axis_extents() -> void:
	# Breite einreihige Linie: 5 Basen quer (x ±0.1), Tiefe nur Basenradius.
	var line := [Vector2(-0.1, 0), Vector2(-0.05, 0), Vector2(0, 0), Vector2(0.05, 0), Vector2(0.1, 0)]
	var m := AiDeployment.footprint_margins(0.12, line, 0.016)
	assert_float(m.x).is_equal_approx(0.116, 0.001)   # halbe Breite + Basenradius
	assert_float(m.y).is_equal_approx(0.016, 0.001)   # nur Basenradius — an die Kante darf sie!
	# Ohne Footprint: Rückfall auf den Umkreis (altes Verhalten).
	var f := AiDeployment.footprint_margins(0.12, [], 0.016)
	assert_float(f.x).is_equal_approx(0.12, 0.001)
	assert_float(f.y).is_equal_approx(0.12, 0.001)


func test_best_spot_reaches_front_edge_with_wide_line() -> void:
	# Zone 24"x12" (0.61x0.305 m), Ziel-Marker VOR der Zone (Tischmitte) — die breite Linie muss
	# mit ihrer Front an die Vorderkante (y-Ende) können, nicht Umkreis-weit dahinter bleiben.
	var zone := Rect2(Vector2(0, 0), Vector2(0.61, 0.305))
	var line := [Vector2(-0.1, 0), Vector2(0, 0), Vector2(0.1, 0)]
	var free := func(_p: Vector2) -> bool: return false
	var spot := AiDeployment.best_spot(zone, [Vector2(0.3, 0.6)], [], 0.116, free, 0.02, 0.0, line, 0.016)
	# Alt (Umkreis 0.116): max y = 0.189. Neu: bis 0.289 (Kante minus Basenradius).
	assert_float(spot.y).is_greater(0.27)
