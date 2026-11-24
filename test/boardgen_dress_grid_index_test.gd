extends GdUnitTestSuite
## The packed grid index of the dressing: every cell agrees with the layout-based rule helpers, the
## kept-clear view of the context is the rules' dict, and the index serves violations() with the
## same answers as the scanning context. The timings are printed, not asserted: a load spike must
## not turn this run red.

const SEEDS: Array[int] = [41, 25, 3]
const TIMED_SEEDS: Array[int] = [41, 25]
const RUNS := 5
const R := preload("res://scripts/boardgen_dress_rules.gd")


func _layout(seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, "ruintown")


func _kit() -> BoardgenDressKit:
	var town := BoardgenKit.new("ruintown")
	add_child(town)
	auto_free(town)
	return BoardgenDressKit.new(town, true)


## The houses planner's placements on a board, the same set the snapshot test pins.
func _placements(layout: Dictionary, kit: BoardgenDressKit, seed: int) -> Array[DressPlacement]:
	var story := BoardgenDressStory.of(layout)
	var ctx := {"kit": kit, "story": story, "meta": kit.meta, "seed": seed}
	var out: Array[DressPlacement] = []
	for p: Dictionary in BoardgenDressHouses.plan(layout, ctx):
		out.append(DressPlacement.from_dict(p))
	return out


## The best of `RUNS` single-call timings in milliseconds, each run on a fresh context so every run
## pays what one board pays.
func _best_ms(context: Callable, placements: Array) -> float:
	var best := INF
	for r in RUNS:
		var ctx: DressContext = context.call()
		var t0 := Time.get_ticks_usec()
		R.violations(ctx, placements)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best


func test_the_index_agrees_with_the_layout_helpers_cell_by_cell() -> void:
	for s in SEEDS:
		var layout := _layout(s)
		var kept := R.kept_clear(layout)
		var index := DressGridIndex.new(layout)
		assert_int(index.size()).is_equal((layout["cells"] as Array).size())
		for i in index.size():
			var x := i % int(layout["nx"])
			var z := floori(i / float(layout["nx"]))
			assert_float(index.top_in(x, z)).is_equal(R.top_in(layout, x, z))
			assert_bool(index.walkable(i)).is_equal(R.walkable(layout, i))
			assert_bool(index.kept_clear(i)).is_equal(kept.has(i))
			assert_bool(index.is_ladder(i)).is_equal(kept.get(i, "") == "ladder")
		# off the board: no surface, nowhere to stand
		assert_float(index.top_in(-1, 0)).is_equal(0.0)
		assert_float(index.top_in(0, int(layout["nz"]))).is_equal(0.0)
		assert_bool(index.walkable(-1)).is_false()
		assert_bool(index.walkable(index.size())).is_false()
		for connector: Dictionary in layout["connectors"]:
			assert_bool(index.is_ladder(int(connector["low"]))).is_true()
			assert_bool(index.is_ladder(int(connector["high"]))).is_true()


func test_an_empty_layout_gives_an_empty_index_instead_of_an_error() -> void:
	var index := DressGridIndex.new({})
	assert_int(index.size()).is_equal(0)
	assert_float(index.top_in(0, 0)).is_equal(0.0)
	assert_bool(index.walkable(0)).is_false()
	assert_bool(index.kept_clear(0)).is_false()
	assert_bool(index.is_ladder(0)).is_false()


func test_the_context_kept_clear_view_is_the_rules_dict_with_ladder_cells_named() -> void:
	for s in SEEDS:
		var layout := _layout(s)
		var context := DressContext.new(layout, _kit(), {}, s)
		assert_dict(context.kept_clear()).is_equal(R.kept_clear(layout))
		for connector: Dictionary in layout["connectors"]:
			assert_str(context.kept_clear()[int(connector["low"])]).is_equal("ladder")


func test_violations_answers_the_same_and_faster_through_the_index() -> void:
	var kit := _kit()
	for s in TIMED_SEEDS:
		var layout := _layout(s)
		var placements := _placements(layout, kit, s)
		assert_int(placements.size()).is_greater(50)  # a real board, not an empty set
		var scanning := DressContext.new(layout, kit, {}, s, true)
		var indexed := DressContext.new(layout, kit, {}, s)
		assert_array(R.violations(indexed, placements)).is_equal(R.violations(scanning, placements))
		var ms_scan := _best_ms(
			func() -> DressContext: return DressContext.new(layout, kit, {}, s, true), placements
		)
		var ms_index := _best_ms(
			func() -> DressContext: return DressContext.new(layout, kit, {}, s), placements
		)
		print(
			(
				"DRESS_GRID seed %d: violations() over %d placements, scan %.1f ms -> index %.1f ms"
				% [s, placements.size(), ms_scan, ms_index]
			)
		)
