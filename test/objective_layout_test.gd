# GdUnit generated TestSuite
extends GdUnitTestSuite
## D8a (NML-1073 M5) — the rulebook objective layout: the book's three constraints,
## the pinned draw order, and determinism per seed.

const FRONT_LINE := {"zones": {
	"1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
	"2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]]}}
const DUEL := {"markers": {"count": "d3+2", "placement": "alternate"}}


func _cells(pairs: Array = []) -> Dictionary:
	var d := {}
	for p in pairs:
		d[Vector2i(p[0], p[1])] = p[2]
	return d


func test_the_count_is_d3_plus_2_and_the_layout_is_legal() -> void:
	for s in range(30):
		var lay := ObjectiveLayout.generate(20260710 + s, DUEL, FRONT_LINE, _cells(), 30)
		assert_int(int(lay["count_roll"])).is_between(3, 5)
		assert_int((lay["positions"] as Array).size()).is_equal(int(lay["count_roll"]))
		assert_int(int(lay["first_placer"])).is_between(1, 2)
		assert_int(int(lay["swept"])).is_equal(0)
		var pos: Array = lay["positions"]
		for i in range(pos.size()):
			# Every marker must be legal against every OTHER marker, so the placement
			# order cannot hide an illegal pair.
			var others: Array = []
			for j in range(pos.size()):
				if j != i:
					others.append(pos[j])
			assert_bool(ObjectiveLayout.is_legal(int(pos[i][0]), int(pos[i][1]),
				others, FRONT_LINE, _cells(), 30)).is_true()
			assert_int(absi(int(pos[i][0]))).is_less_equal(36 - ObjectiveLayout.EDGE_MARGIN_IN)
			assert_int(absi(int(pos[i][1]))).is_less_equal(24 - ObjectiveLayout.EDGE_MARGIN_IN)


func test_the_placers_alternate_from_the_roll_off_winner() -> void:
	var lay := ObjectiveLayout.generate(20260710, DUEL, FRONT_LINE, _cells(), 30)
	var by: Array = lay["placed_by"]
	var first := int(lay["first_placer"])
	assert_int(by.size()).is_equal(int(lay["count_roll"]))
	for i in range(by.size()):
		assert_int(int(by[i])).is_equal(first if i % 2 == 0 else 3 - first)


func test_the_same_seed_gives_the_same_layout_and_a_different_seed_does_not() -> void:
	var a := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30)
	var b := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30)
	assert_that(a["positions"]).is_equal(b["positions"])
	assert_int(int(a["count_roll"])).is_equal(int(b["count_roll"]))
	var c := ObjectiveLayout.generate(4243, DUEL, FRONT_LINE, _cells(), 30)
	assert_bool(a["positions"] == c["positions"]).is_false()


func test_over_nine_inches_means_nine_exactly_is_illegal() -> void:
	# The one boundary the book states in words, and the one an off-by-one passes.
	assert_bool(ObjectiveLayout.is_legal(9, 0, [[0, 0]], {}, _cells(), 30)).is_false()
	assert_bool(ObjectiveLayout.is_legal(10, 0, [[0, 0]], {}, _cells(), 30)).is_true()


func test_the_deployment_zone_boundary_counts_as_inside() -> void:
	assert_bool(ObjectiveLayout.is_legal(0, -12, [], FRONT_LINE, _cells(), 30)).is_false()
	assert_bool(ObjectiveLayout.is_legal(0, -20, [], FRONT_LINE, _cells(), 30)).is_false()
	assert_bool(ObjectiveLayout.is_legal(0, -11, [], FRONT_LINE, _cells(), 30)).is_true()


func test_an_impassable_cell_is_unreachable() -> void:
	# n = 30, 3" cells: inches (1, 1) fall in cell (15, 15).
	var blocked := _cells([[15, 15, TerrainRules.TerrainType.CONTAINER]])
	assert_bool(ObjectiveLayout.is_legal(1, 1, [], {}, blocked, 30)).is_false()
	var wood := _cells([[15, 15, TerrainRules.TerrainType.FOREST]])
	assert_bool(ObjectiveLayout.is_legal(1, 1, [], {}, wood, 30)).is_true()


func test_a_fixed_count_spec_draws_nothing_and_shifts_no_later_draw() -> void:
	# A NUMBER count must not consume a die — otherwise every later draw moves and the
	# Rust mirror's `count_of` (which mirrors the same type test) diverges.
	var fixed := {"markers": {"count": 4, "placement": "alternate"}}
	var lay := ObjectiveLayout.generate(99, fixed, FRONT_LINE, _cells(), 30)
	assert_int(int(lay["count_roll"])).is_equal(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# The first draw of the stream must therefore be the ROLL-OFF, not the count.
	assert_int(int(lay["first_placer"])).is_equal(ObjectiveLayout._roll_off(rng))
