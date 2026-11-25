extends GdUnitTestSuite
## The bulky-junk planner (SPEC_RUINTOWN_DRESSING step 33, D-DR3 (a) strict) on the stub kit: junk
## clusters stand wholly inside terrain cells (ruin yards: Rough, or a level-0 off-street Terrace),
## never on a street, a kept-clear cell, a ladder strip or a doorway; the flat site pieces stay
## under FLAT; nothing overlaps; no honesty rule breaks; every board gets clusters and yard pieces.

const SEEDS := [41, 25, 7]
const IN := 0.0254
const TOL_IN := 0.02


func _ctx(board_seed: int) -> DressContext:
	var layout: Dictionary = (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(
		board_seed, "ruintown"
	)
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	return DressContext.new(
		layout, BoardgenDressKit.new(kit, true), BoardgenDressStory.of(layout), board_seed
	)


## The XZ rect (board inches) of a placement's module aabb.
func _rect(ctx: DressContext, p: DressPlacement) -> Rect2:
	var spec := ctx.spec(p.module)
	var r := Rect2()
	for k in 4:
		var c := Vector3(
			spec.aabb_hi.x if k & 1 else spec.aabb_lo.x,
			0.0,
			spec.aabb_hi.z if k & 2 else spec.aabb_lo.z
		)
		var q := p.transform * (c * IN) / IN
		r = Rect2(q.x, q.z, 0.0, 0.0) if k == 0 else r.expand(Vector2(q.x, q.z))
	return r


func _terrain(ctx: DressContext, i: int) -> bool:
	var cell: Dictionary = ctx.layout["cells"][i]
	return (
		str(cell["lot_kind"]) == "Rough"
		or (str(cell["lot_kind"]) == "Terrace" and int(cell["level"]) == 0 and not cell["street"])
	)


func test_bulky_junk_stands_wholly_inside_terrain_cells_and_never_on_a_street() -> void:
	for s: int in SEEDS:
		var ctx := _ctx(s)
		var placements := BoardgenDressClutter.new().plan(ctx)
		var bulky := placements.filter(
			func(p: DressPlacement) -> bool:
				return p.module.begins_with("dr_junk") or p.module.begins_with("dr_yard")
		)
		assert_int(bulky.size()).override_failure_message("seed %d: no junk" % s).is_greater(0)
		for p: DressPlacement in bulky:
			var r := _rect(ctx, p).grow(-TOL_IN)
			var c0 := Vector2i(((r.position - ctx.origin_in) / ctx.cell_in).floor())
			var c1 := Vector2i(((r.end - ctx.origin_in) / ctx.cell_in).floor())
			(
				assert_bool(c0 == c1)
				. override_failure_message("seed %d: %s spans two cells" % [s, p.module])
				. is_true()
			)
			var i := c0.y * ctx.nx + c0.x
			(
				assert_bool(_terrain(ctx, i) and not ctx.kept_clear_cell(i))
				. override_failure_message(
					"seed %d: %s on cell %s, not a ruin yard" % [s, p.module, c0]
				)
				. is_true()
			)


func test_no_rule_breaks_no_overlap_no_ladder_strip_or_doorway_and_flat_sites_stay_flat() -> void:
	var yards := 0
	for s: int in SEEDS:
		var ctx := _ctx(s)
		var placements := BoardgenDressClutter.new().plan(ctx)
		assert_array(BoardgenDressRules.violations(ctx, placements)).is_empty()
		var zones: Array[Rect2] = BoardgenDressRules._ladder_zones(ctx.layout)
		zones.append_array(BoardgenDressVegetation.door_zones(ctx))
		var seen: Array[Rect2] = []
		var yard := 0
		for p: DressPlacement in placements:
			if (
				BoardgenDressClutter.FLAT_SITES.has(p.module)
				or BoardgenDressClutter.LITTER.has(p.module)
			):
				var o := p.transform.origin / IN
				var at := Vector2i(((Vector2(o.x, o.z) - ctx.origin_in) / ctx.cell_in).floor())
				var top := o.y + ctx.spec(p.module).aabb_hi.y - ctx.top_in(at.x, at.y)
				assert_float(top).is_less_equal(BoardgenDressRules.FLAT + TOL_IN)
				continue
			yard += 1 if p.module.begins_with("dr_yard") else 0
			var r := _rect(ctx, p).grow(-TOL_IN)
			assert_bool(zones.any(func(z: Rect2) -> bool: return z.intersects(r))).is_false()
			assert_bool(seen.any(func(o: Rect2) -> bool: return o.intersects(r))).is_false()
			seen.append(r)
		yards += yard
	assert_int(yards).override_failure_message("no ruin-yard piece on any seed").is_greater(0)


## Step 32: flat litter lies under FLAT, never on a kept-clear cell or in a ladder strip, and a
## street cell carries at least twice the litter of an open-earth cell (over 20 seeds).
func test_flat_litter_stays_flat_off_kept_clear_cells_and_streets_get_twice_the_earths() -> void:
	var per := {"street": [0, 0], "earth": [0, 0]}  # [pieces, cells]
	for s in range(1, 21):
		var ctx := _ctx(s)
		var strips: Array[Rect2] = BoardgenDressRules._ladder_zones(ctx.layout)
		var litter := BoardgenDressClutter.new().plan(ctx).filter(
			func(p: DressPlacement) -> bool: return BoardgenDressClutter.LITTER.has(p.module)
		)
		assert_int(litter.size()).override_failure_message("seed %d: little litter" % s).is_greater(
			50
		)
		for p: DressPlacement in litter:
			var o := p.transform.origin / IN
			var cell := Vector2i(((Vector2(o.x, o.z) - ctx.origin_in) / ctx.cell_in).floor())
			var i := cell.y * ctx.nx + cell.x
			var top := o.y + ctx.spec(p.module).aabb_hi.y - ctx.top_in(cell.x, cell.y)
			assert_float(top).is_less_equal(BoardgenDressRules.FLAT + TOL_IN)
			assert_bool(ctx.kept_clear_cell(i)).is_false()
			(
				assert_bool(
					strips.any(func(z: Rect2) -> bool: return z.has_point(Vector2(o.x, o.z)))
				)
				. is_false()
			)
			var c: Dictionary = ctx.layout["cells"][i]
			if int(c["level"]) == 0 and str(c["lot_kind"]) != "Hazard":
				per["street" if c["street"] else "earth"][0] += 1
		for i in (ctx.layout["cells"] as Array).size():
			var c: Dictionary = ctx.layout["cells"][i]
			if (
				int(c["level"]) == 0
				and ctx.walkable(i)
				and not ctx.kept_clear_cell(i)
				and str(c["lot_kind"]) != "Hazard"
			):
				per["street" if c["street"] else "earth"][1] += 1
	var street := float(per["street"][0]) / maxf(per["street"][1], 1.0)
	var earth := float(per["earth"][0]) / maxf(per["earth"][1], 1.0)
	(
		assert_float(street)
		. override_failure_message("street %.2f vs earth %.2f per cell" % [street, earth])
		. is_greater_equal(2.0 * earth)
	)
