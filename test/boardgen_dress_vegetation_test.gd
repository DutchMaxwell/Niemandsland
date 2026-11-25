extends GdUnitTestSuite
## The vegetation planner (look review R11) on the stub kit: clumps, wall-foot runs and plot beds
## stand only on level-0 earth, ruin yards and garden plots; nothing touches a street, a kept-clear
## cell (ladders, landmarks), a ladder strip, a doorway or the 1 in in front of a door; every board
## gets some of each; no honesty rule breaks.

const SEEDS := [41, 25]
const IN := 0.0254
const TOL_IN := 0.02


func _layout(board_seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(board_seed, "ruintown")


func _ctx(layout: Dictionary) -> DressContext:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	var dress := BoardgenDressKit.new(kit, true)
	return DressContext.new(layout, dress, BoardgenDressStory.of(layout), int(layout["seed"]))


## The XZ rect (board inches) a placement's module aabb covers through its transform.
func _rect(ctx: DressContext, p: DressPlacement) -> Rect2:
	var spec := ctx.spec(p.module)
	var r := Rect2()
	for k in 8:
		var c := Vector3(
			spec.aabb_hi.x if k & 1 else spec.aabb_lo.x,
			spec.aabb_hi.y if k & 2 else spec.aabb_lo.y,
			spec.aabb_hi.z if k & 4 else spec.aabb_lo.z
		)
		var q := p.transform * (c * IN) / IN
		r = Rect2(q.x, q.z, 0.0, 0.0) if k == 0 else r.expand(Vector2(q.x, q.z))
	return r


## The cells a rect (shrunk by TOL_IN) overlaps, as indices.
func _cells(ctx: DressContext, r: Rect2) -> Array[int]:
	var s := r.grow(-TOL_IN)
	var out: Array[int] = []
	var x0 := clampi(floori((s.position.x - ctx.origin_in.x) / ctx.cell_in), 0, ctx.nx - 1)
	var x1 := clampi(floori((s.end.x - ctx.origin_in.x) / ctx.cell_in), 0, ctx.nx - 1)
	var z0 := clampi(floori((s.position.y - ctx.origin_in.y) / ctx.cell_in), 0, ctx.nz - 1)
	var z1 := clampi(floori((s.end.y - ctx.origin_in.y) / ctx.cell_in), 0, ctx.nz - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			out.append(z * ctx.nx + x)
	return out


## Whether vegetation may cover cell `i`, read from the layout alone (not from the planner): a
## level-0 non-street cell of plain earth, a ruin yard or a garden plot, walkable, not kept clear.
func _green(ctx: DressContext, i: int) -> bool:
	var cell: Dictionary = ctx.layout["cells"][i]
	return (
		int(cell["level"]) == 0
		and not cell["street"]
		and ["Street", "Terrace", "Rough"].has(str(cell["lot_kind"]))
		and BoardgenDressRules.walkable(ctx.layout, i)
		and not BoardgenDressRules.kept_clear(ctx.layout).has(i)
	)


## Every placement covers only vegetation ground (earth, yard, plot), never a street, a raised,
## solid or kept-clear cell.
func test_vegetation_stands_only_on_earth_yards_and_plots() -> void:
	for board_seed: int in SEEDS:
		var ctx := _ctx(_layout(board_seed))
		var plan := BoardgenDressVegetation.new().plan(ctx)
		assert_int(plan.size()).is_greater(0)
		for p: DressPlacement in plan:
			for i in _cells(ctx, _rect(ctx, p)):
				(
					assert_bool(_green(ctx, i))
					. override_failure_message(
						(
							"seed %d: %s over cell %d (%s)"
							% [board_seed, p.module, i, ctx.layout["cells"][i]]
						)
					)
					. is_true()
				)


## No placement reaches into a ladder strip, a doorway or the 1 in in front of a door; the door
## zones exist (every board has doors), so the check can fail.
func test_vegetation_keeps_off_ladder_strips_and_doorways() -> void:
	for board_seed: int in SEEDS:
		var ctx := _ctx(_layout(board_seed))
		var doors := BoardgenDressVegetation.door_zones(ctx)
		assert_int(doors.size()).is_greater(0)
		var zones: Array[Rect2] = BoardgenDressRules._ladder_zones(ctx.layout)
		zones.append_array(doors)
		for p: DressPlacement in BoardgenDressVegetation.new().plan(ctx):
			var r := _rect(ctx, p).grow(-TOL_IN)
			for z: Rect2 in zones:
				(
					assert_bool(z.intersects(r))
					. override_failure_message(
						"seed %d: %s at %s in a keep-out %s" % [board_seed, p.module, r, z]
					)
					. is_false()
				)


## A door's zone covers the 1 in in front of it: a point 0.9 in out from the middle of the door's
## edge lies inside it (the zone is not a thin line at the face).
func test_a_door_zone_reaches_an_inch_out_of_the_door() -> void:
	var ctx := _ctx(_layout(41))
	var zones := BoardgenDressVegetation.door_zones(ctx)
	var n := 0
	for p: DressPlacement in BoardgenDressHouses.new().plan(ctx):
		if not p.module.ends_with("_door"):
			continue
		var o := p.transform.origin / IN
		var mid := o + p.transform.basis.x.normalized() * ctx.cell_in * 0.5
		var out := mid + p.transform.basis.z.normalized() * 0.9
		(
			assert_bool(
				zones.any(func(z: Rect2) -> bool: return z.has_point(Vector2(out.x, out.z)))
			)
			. is_true()
		)
		n += 1
	assert_int(n).is_greater(0)


## Every board on seeds 1-20 carries clumps and wall-foot runs, garden boards a plot bed, and the
## honesty rules hold.
func test_every_board_is_green_and_honest() -> void:
	var totals := {"clump": 0, "foot": 0, "plot": 0}
	for board_seed in range(1, 21):
		var ctx := _ctx(_layout(board_seed))
		var plan := BoardgenDressVegetation.new().plan(ctx)
		var kinds := {"clump": 0, "foot": 0, "plot": 0}
		for p: DressPlacement in plan:
			var kind := (
				"foot"
				if p.module.contains("foot_run")
				else "plot" if p.module.contains("plot") else "clump"
			)
			kinds[kind] += 1
			totals[kind] += 1
		(
			assert_int(kinds["clump"])
			. override_failure_message("seed %d: no clump" % board_seed)
			. is_greater(20)
		)
		(
			assert_int(kinds["foot"])
			. override_failure_message("seed %d: no foot run" % board_seed)
			. is_greater(0)
		)
		var lines := BoardgenDressRules.violations(ctx, plan)
		(
			assert_array(Array(lines))
			. override_failure_message("seed %d: %s" % [board_seed, lines])
			. is_empty()
		)
	print("VEG over boards 1-20: %s" % totals)
	assert_int(totals["plot"]).is_greater(0)


## Density pass (lead 25.11.): the clump pieces stand at about 1.5 x their kit size but never over
## 0.4 in, and the wall feet carry weeds (heads within 0.8 in of a raised or solid neighbour).
func test_pieces_are_larger_but_soft_and_wall_feet_carry_weeds() -> void:
	for board_seed: int in SEEDS:
		var ctx := _ctx(_layout(board_seed))
		var scales: Array[float] = []
		var weeds := 0
		for p: DressPlacement in BoardgenDressVegetation.new().plan(ctx):
			if p.module.contains("foot_run") or p.module.contains("plot"):
				continue
			var sc := p.transform.basis.get_scale().x
			scales.append(sc)
			assert_float(ctx.spec(p.module).aabb_hi.y * sc).is_less_equal(0.4)
			var q := p.transform.origin / IN
			var cell := Vector2i(((Vector2(q.x, q.z) - ctx.origin_in) / ctx.cell_in).floor())
			var f := Vector2(q.x, q.z) - (ctx.origin_in + Vector2(cell) * ctx.cell_in)
			for k in 4:
				var d: Vector2i = BoardgenDressVegetation.DIRS[k]
				var n := cell + d
				var gap := [f.y, ctx.cell_in - f.x, ctx.cell_in - f.y, f.x][k] as float
				if gap < 0.8 and ctx.top_in(n.x, n.y) > 0.0:
					weeds += 1
					break
		scales.sort()
		assert_float(scales[scales.size() / 2]).is_greater_equal(1.2)
		(
			assert_int(weeds)
			. override_failure_message("seed %d: %d weeds" % [board_seed, weeds])
			. is_greater(60)
		)
