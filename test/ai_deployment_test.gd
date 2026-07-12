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
