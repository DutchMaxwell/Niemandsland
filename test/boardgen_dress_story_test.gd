extends GdUnitTestSuite
## The board story of the dressing: one seeded decay story per town board - a fire direction, a shade side and the wall breaches - gives a damage field D(p)
## in 0..1 and a shade field S, plus a well-mixed pick and one accent per lot. Pure data: no node, no mesh, no collider is touched.

const SEEDS_50 := 50


func _layout(seed: int) -> Dictionary:
	var core: Object = ClassDB.instantiate("NmlCore")
	return core.boardgen_layout_themed(seed, "ruintown")


## The centre of every cell in board inches (origin at the board centre, x right, z down), as the story reads positions.
func _cell_centres(layout: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cell := float(layout["cell_in"])
	for c: Dictionary in layout["cells"]:
		out.append((Vector2(c["x"], c["z"]) + Vector2(0.5, 0.5) - Vector2(layout["nx"], layout["nz"]) * 0.5) * cell)
	return out


func test_the_story_is_deterministic_per_seed_and_differs_between_seeds() -> void:
	var fires := {}
	for s in SEEDS_50:
		var a := BoardgenDressStory.of(_layout(s))
		var b := BoardgenDressStory.of(_layout(s))
		assert_that(a).is_equal(b)
		assert_float(a["fire"].length()).is_equal_approx(1.0, 0.001)
		assert_float(a["shade"].length()).is_equal_approx(1.0, 0.001)
		assert_float(a["fire"].dot(a["shade"])).is_equal_approx(0.0, 0.001)   # the shade side is a quarter turn off the fire
		fires[snappedf(a["fire"].angle(), 0.01)] = true
	assert_int(fires.size()).is_greater(30)


func test_breaches_are_the_level_0_wall_cells_in_board_inches() -> void:
	var seen := 0
	for s in [41, 25, 3, 7]:
		var layout := _layout(s)
		var want := 0
		for c: Dictionary in layout["cells"]:
			want += 1 if c["lot_kind"] == "Wall" and int(c["level"]) == 0 else 0
		var st := BoardgenDressStory.of(layout)
		assert_int(st["breaches"].size()).is_equal(want)
		for b: Vector2 in st["breaches"]:
			assert_float(absf(b.x)).is_less(24.0)
			assert_float(absf(b.y)).is_less(24.0)
		seen += want
	assert_int(seen).is_greater(0)   # the check can fail: a story without breaches would pass the loop above with zero rows


func test_damage_stays_in_0_to_1_everywhere() -> void:
	var lo := 1.0
	var hi := 0.0
	for s in SEEDS_50:
		var layout := _layout(s)
		var st := BoardgenDressStory.of(layout)
		for p in _cell_centres(layout) + [Vector2(-30, -30), Vector2(30, 30), Vector2.ZERO]:
			var d := BoardgenDressStory.damage(st, p)
			lo = minf(lo, d)
			hi = maxf(hi, d)
	assert_float(lo).is_greater_equal(0.0)
	assert_float(hi).is_less_equal(1.0)
	assert_float(hi - lo).is_greater(0.4)   # a field, not a constant


func test_both_board_halves_have_the_same_mean_damage() -> void:
	var sum := [0.0, 0.0]
	var n := [0, 0]
	for s in SEEDS_50:
		var layout := _layout(s)
		var st := BoardgenDressStory.of(layout)
		for p in _cell_centres(layout):
			var half := 1 if p.y >= 0.0 else 0
			sum[half] += BoardgenDressStory.damage(st, p)
			n[half] += 1
	var north: float = sum[0] / n[0]
	var south: float = sum[1] / n[1]
	print("DRESS_STORY mean damage north %.4f south %.4f" % [north, south])
	assert_float(absf(north - south) / maxf(north, south)).is_less(0.15)


func test_the_fire_term_folds_so_both_halves_see_the_same_story() -> void:
	var st := {"seed": 1, "fire": Vector2(1, 0), "shade": Vector2(0, 1), "breaches": []}
	assert_float(BoardgenDressStory._fire(st, Vector2(24, -12))).is_equal_approx(1.0, 0.0001)   # the fire's side, the north half
	assert_float(BoardgenDressStory._fire(st, Vector2(-24, -12))).is_equal_approx(0.0, 0.0001)
	for p in [Vector2(5, -7), Vector2(-13, 3), Vector2(20, 20), Vector2(-2, -22)]:
		assert_float(BoardgenDressStory._fire(st, p)).is_equal_approx(BoardgenDressStory._fire(st, -p), 0.0001)


func test_the_breach_term_falls_from_1_at_a_breach_to_0_at_18_inches_and_is_0_without_one() -> void:
	var st := {"seed": 1, "fire": Vector2(1, 0), "shade": Vector2(0, 1), "breaches": [Vector2(10, 10)] as Array[Vector2]}
	assert_float(BoardgenDressStory._breach(st, Vector2(10, 10))).is_equal_approx(1.0, 0.0001)
	assert_float(BoardgenDressStory._breach(st, Vector2(19, 10))).is_equal_approx(0.5, 0.0001)
	assert_float(BoardgenDressStory._breach(st, Vector2(28, 10))).is_equal_approx(0.0, 0.0001)
	assert_float(BoardgenDressStory._breach(st, Vector2(-20, -20))).is_equal_approx(0.0, 0.0001)
	st["breaches"] = [] as Array[Vector2]
	assert_float(BoardgenDressStory._breach(st, Vector2(10, 10))).is_equal_approx(0.0, 0.0001)


func test_the_noise_is_smooth_and_seeded() -> void:
	var rough := 0.0
	for k in 200:
		var p := Vector2(k * 0.37 - 30.0, k * 0.21 - 20.0)
		rough = maxf(rough, absf(BoardgenDressStory._noise(7, p) - BoardgenDressStory._noise(7, p + Vector2(0.1, 0.1))))
	assert_float(rough).is_less(0.1)   # 0.1 in of movement never jumps the value (a 9 in lattice)
	assert_float(BoardgenDressStory._noise(7, Vector2(3, 4))).is_not_equal(BoardgenDressStory._noise(8, Vector2(3, 4)))


func test_a_breach_makes_its_surroundings_more_damaged() -> void:
	var st := {"seed": 5, "fire": Vector2(1, 0), "shade": Vector2(0, 1), "breaches": [Vector2(0, 0)] as Array[Vector2]}
	var bare := {"seed": 5, "fire": Vector2(1, 0), "shade": Vector2(0, 1), "breaches": [] as Array[Vector2]}
	assert_float(BoardgenDressStory.damage(st, Vector2(1, 1)) - BoardgenDressStory.damage(bare, Vector2(1, 1))).is_equal_approx(0.35 * (1.0 - sqrt(2.0) / 18.0), 0.0001)


func test_shade_is_1_on_the_shade_side_0_opposite_and_half_across() -> void:
	var st := BoardgenDressStory.of(_layout(41))
	var s: Vector2 = st["shade"]
	assert_float(BoardgenDressStory.shade(st, s)).is_equal_approx(1.0, 0.0001)
	assert_float(BoardgenDressStory.shade(st, -s)).is_equal_approx(0.0, 0.0001)
	assert_float(BoardgenDressStory.shade(st, s.orthogonal())).is_equal_approx(0.5, 0.0001)


func test_pick_is_in_range_deterministic_and_does_not_repeat_along_neighbours_more_than_chance() -> void:
	for n in [2, 3, 4]:
		var pairs := 0
		var same := 0
		for salt in 50:
			var prev := -1
			for id in 16:
				var v := BoardgenDressStory.pick(id, salt, n)
				assert_int(v).is_between(0, n - 1)
				assert_int(v).is_equal(BoardgenDressStory.pick(id, salt, n))
				if prev >= 0:
					pairs += 1
					same += 1 if v == prev else 0
				prev = v
		var rate := float(same) / float(pairs)
		print("DRESS_STORY pick n=%d adjacent repeats %.3f (chance %.3f)" % [n, rate, 1.0 / n])
		assert_float(rate).is_less(1.0 / n + 0.06)
	assert_int(BoardgenDressStory.pick(5, 3, 0)).is_equal(0)   # n <= 0 never divides by zero


func test_accents_are_one_of_five_and_each_appears() -> void:
	var seen := {}
	for lot in 400:
		var a := BoardgenDressStory.accent(lot)
		assert_bool(["jetty", "lean", "sag", "ragged", ""].has(a)).is_true()
		assert_str(a).is_equal(BoardgenDressStory.accent(lot))
		seen[a] = int(seen.get(a, 0)) + 1
	assert_int(seen.size()).is_equal(5)
	for k: String in seen:
		assert_int(seen[k]).is_between(30, 130)   # shares near 0.2 / 0.15, never a monoculture


func test_the_knobs_carry_the_planned_numbers() -> void:
	var k: Dictionary = BoardgenDressStory.KNOBS
	assert_float(k["roof_holed_from"]).is_equal(0.45)
	assert_float(k["roof_rafters_from"]).is_equal(0.7)
	assert_float(k["roof_whole_share"]).is_equal(0.6)
	assert_float(k["lean_base_deg"] + k["lean_gain_deg"]).is_equal_approx(1.5, 0.0001)   # LEAN_MAX of the honesty rules
	assert_float(k["merlon_loss_base"]).is_equal(0.2)
	assert_float(k["merlon_loss_gain"]).is_equal(0.5)


func test_most_roofs_stay_whole_in_both_halves() -> void:
	var whole := [0, 0]
	var total := [0, 0]
	for s in SEEDS_50:
		var layout := _layout(s)
		var st := BoardgenDressStory.of(layout)
		var cell := float(layout["cell_in"])
		for lot: Dictionary in layout["lots"]:
			if lot["kind"] != "Roofed":
				continue
			var p := (Vector2(lot["x"], lot["z"]) + Vector2(lot["w"], lot["h"]) * 0.5 - Vector2(layout["nx"], layout["nz"]) * 0.5) * cell
			var half := 1 if p.y >= 0.0 else 0
			total[half] += 1
			whole[half] += 1 if BoardgenDressStory.damage(st, p) < float(BoardgenDressStory.KNOBS["roof_holed_from"]) else 0
	print("DRESS_STORY whole-roof share north %.3f south %.3f (%d / %d roofs)" % [float(whole[0]) / total[0], float(whole[1]) / total[1], total[0], total[1]])
	# the planner's whole-roof floor (KNOBS roof_whole_share 0.6) only has to promote a few: the raw field already keeps about 60 % whole
	assert_float(float(whole[0]) / total[0]).is_greater(0.5)
	assert_float(float(whole[1]) / total[1]).is_greater(0.5)
