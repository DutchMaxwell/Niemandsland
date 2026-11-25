class_name BoardgenDressClutter
extends DressPlanner
## The bulky-junk planner of the ruin-town dressing (SPEC_RUINTOWN_DRESSING step 33, rule D-DR3 (a)
## strict): every prop box of BoardgenTownDressing.props() becomes a small story cluster of kit junk
## against its wall (a store of barrels and sacks, a crate stack, a broken cart's planks and wheel)
## - but only where the rules call the cell terrain (a ruin yard); elsewhere the site keeps flat
## planks. A ruin yard (Rough) may get one yard piece (rubble, a fallen beam, a wall stub). Never in
## a kept-clear cell, a ladder strip or a doorway; every piece passes BoardgenDressRules alone and
## overlaps no other. The class hides the old prop boxes; no collider is touched.

const CLUSTERS := [
	["dr_junk_barrels", "dr_junk_sacks"],
	["dr_junk_planks", "dr_junk_cart_wheel"],
	["dr_junk_sacks", "dr_junk_crates"],
	["dr_junk_crates", "dr_junk_barrels"],
]
const YARD: Array[String] = [
	"dr_yard_rubble_a", "dr_yard_beam", "dr_yard_wallstub_a", "dr_yard_wallstub_b"
]
const FLAT_SITES: Array[String] = ["dr_litter_planks_flat", "dr_litter_staves_flat"]
const MODULES: Array[String] = [
	"dr_junk_barrels",
	"dr_junk_sacks",
	"dr_junk_planks",
	"dr_junk_cart_wheel",
	"dr_junk_crates",
	"dr_yard_rubble_a",
	"dr_yard_beam",
	"dr_yard_wallstub_a",
	"dr_yard_wallstub_b",
	"dr_litter_straw",
	"dr_litter_leaves",
	"dr_litter_shards",
	"dr_litter_slates_fallen",
	"dr_litter_rags",
	"dr_litter_mud",
	"dr_litter_planks_flat",
	"dr_litter_staves_flat"
]
const LITTER: Array[String] = [
	"dr_litter_straw",
	"dr_litter_leaves",
	"dr_litter_shards",
	"dr_litter_slates_fallen",
	"dr_litter_rags",
	"dr_litter_mud",
	"dr_litter_planks_flat",
	"dr_litter_staves_flat"
]
const BASE_STREET := 1.0  # litter clusters per cell: a street
const BASE_EARTH := 0.25  # open earth and ruin yards
const BASE_DECK := 0.4  # a tier top
const WALL_FOOT := 0.2  # per neighbour that stands higher
const EAVE := 0.15  # more when that neighbour is a roofed house
const LANE_MOUTH := 0.3  # a street cell with three or more street neighbours
const GATE := 0.4  # a street cell where the street passes the town wall
const LITTER_REACH_IN := 0.8  # a litter module's half extent at scale 1
const LITTER_LIFT_IN := 0.01  # the most a litter piece rises off its top (its top stays under FLAT)
const GAP_IN := 0.06  # off the wall, and between two pieces of a cluster
const YARD_IN_TEN := 10  # every other ruin-yard cell gets a yard piece
const CLUSTER_IN_TEN := 10  # every walled terrain cell gets a junk cluster at one wall
const SALT := 0x3C1


func plan(ctx: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var taken: Array[Rect2] = BoardgenDressRules._ladder_zones(ctx.layout)
	taken.append_array(BoardgenDressVegetation.door_zones(ctx))
	for box: Dictionary in BoardgenTownDressing.props(ctx.layout):  # open ground: flat refuse only
		var cell: Vector2 = box["at"]
		var d: Vector2i = box["face"]
		var mid := (Vector2(box["lo"].x, box["lo"].z) + Vector2(box["hi"].x, box["hi"].z)) * 0.5
		var i := int(cell.y) * ctx.nx + int(cell.x)
		_try(ctx, out, taken, FLAT_SITES[_pick(i, d.x + 2 * d.y + 3, 2)], mid, -Vector2(d))
	for i in (ctx.layout["cells"] as Array).size():
		if not BoardgenDressRules._terrain(ctx.layout, i) or ctx.kept_clear_cell(i):
			continue
		var cell := Vector2i(i % ctx.nx, floori(i / float(ctx.nx)))
		var mid := ctx.origin_in + (Vector2(cell) + Vector2.ONE * 0.5) * ctx.cell_in
		var walls: Array[Vector2i] = []
		for d: Vector2i in BoardgenDressVegetation.DIRS:
			var n := cell + d
			var inside := n.x >= 0 and n.y >= 0 and n.x < ctx.nx and n.y < ctx.nz
			if inside and (ctx.top_in(n.x, n.y) > 0.0 or not ctx.walkable(n.y * ctx.nx + n.x)):
				walls.append(d)
		if not walls.is_empty() and _pick(i, 5, 10) < CLUSTER_IN_TEN:
			var d: Vector2i = walls[_pick(i, 6, walls.size())]
			var out_dir := -Vector2(d)
			var along := Vector2(-out_dir.y, out_dir.x)
			var wall := mid + Vector2(d) * ctx.cell_in * 0.5
			var a := (_pick(i, 4, 7) - 3) * 0.2  # the hero's place along the wall
			var modules: Array = CLUSTERS[_pick(i, 3, CLUSTERS.size())]
			for k in modules.size():
				var spec := ctx.spec(modules[k])
				var half := (spec.aabb_hi.x - spec.aabb_lo.x) * 0.5
				var at := a if k == 0 else a + (-1.0 if a > 0.0 else 1.0) * (half + GAP_IN + 0.75)
				at = clampf(at, -ctx.cell_in * 0.5 + half + 0.05, ctx.cell_in * 0.5 - half - 0.05)
				var q := wall + along * at + out_dir * (GAP_IN - spec.aabb_lo.z)
				_try(ctx, out, taken, modules[k], q, out_dir)
		elif str(ctx.layout["cells"][i]["lot_kind"]) == "Rough" and _pick(i, 7, 10) < YARD_IN_TEN:
			var turn := Vector2.from_angle(_pick(i, 9, 4) * PI * 0.5)
			_try(ctx, out, taken, YARD[_pick(i, 8, YARD.size())], mid, turn)
	_litter(ctx, out, BoardgenDressRules._ladder_zones(ctx.layout))
	return out


## Places `module` at `q` (board inches, its +z along `out_dir`) when it breaks no rule and overlaps
## nothing taken; a flat site piece lies so its top stays under FLAT.
func _try(
	ctx: DressContext,
	out: Array[DressPlacement],
	taken: Array[Rect2],
	module: String,
	q: Vector2,
	out_dir: Vector2
) -> void:
	var z := Vector3(out_dir.x, 0.0, out_dir.y)
	var basis := Basis(Vector3.UP.cross(z), Vector3.UP, z)
	var spec := ctx.spec(module)
	var y := minf(0.0, BoardgenDressRules.FLAT - spec.aabb_hi.y) if FLAT_SITES.has(module) else 0.0
	var xf := Transform3D(basis, Vector3(q.x, y, q.y))
	var p := DressPlacement.new(module, BoardgenDressVegetation._metres(xf), "clutter")
	var r := Rect2(q, Vector2.ZERO)
	for k in 4:
		var corner := Vector3(
			spec.aabb_hi.x if k & 1 else spec.aabb_lo.x,
			0.0,
			spec.aabb_hi.z if k & 2 else spec.aabb_lo.z
		)
		var w := xf * corner
		r = r.expand(Vector2(w.x, w.z))
	if not FLAT_SITES.has(module) and BoardgenDressVegetation._hits(r.grow(-0.01), taken):
		return
	if not BoardgenDressRules.violations(ctx, [p]).is_empty():
		return
	taken.append(r)
	out.append(p)


static func _pick(i: int, salt: int, n: int) -> int:
	return BoardgenDressStory.pick(i, SALT + salt, n)


## Flat litter (step 32): per walkable cell (level-0 ground and tier tops, not hazard, not kept
## clear) a seeded count from a density = base (street, earth, deck) + wall feet + lane mouth +
## gate + eaves, times 1 + litter gain x damage; each a turned, stretched cluster inside its cell,
## its top under FLAT (the TRAP: origin at the cell's top + at most LITTER_LIFT_IN), never in a
## ladder strip.
func _litter(ctx: DressContext, out: Array[DressPlacement], strips: Array[Rect2]) -> void:
	var gates := _gate_cells(ctx)
	for i in (ctx.layout["cells"] as Array).size():
		var c: Dictionary = ctx.layout["cells"][i]
		if ctx.kept_clear_cell(i) or str(c["lot_kind"]) == "Hazard" or not ctx.walkable(i):
			continue
		var cell := Vector2i(i % ctx.nx, floori(i / float(ctx.nx)))
		var top := ctx.top_in(cell.x, cell.y)
		var base := BASE_STREET if c["street"] else (BASE_DECK if top > 0.0 else BASE_EARTH)
		var mid := ctx.origin_in + (Vector2(cell) + Vector2.ONE * 0.5) * ctx.cell_in
		var gain := (
			float(BoardgenDressStory.KNOBS["litter_gain"])
			* BoardgenDressStory.damage(ctx.story, mid)
		)
		var density := (base + _terms(ctx, c, cell, gates)) * (1.0 + gain)
		var n := (
			floori(density) + (1 if _pick(i, 11, 1000) < (density - floorf(density)) * 1000 else 0)
		)
		for k in n:
			var s := i * 16 + k
			var module: String = LITTER[_pick(s, 12, LITTER.size())]
			var yaw := TAU * _pick(s, 13, 1000) / 1000.0
			var size := Vector2(
				0.75 + 0.6 * _pick(s, 14, 100) / 100.0, 0.75 + 0.6 * _pick(s, 15, 100) / 100.0
			)
			var reach := size * LITTER_REACH_IN
			var room := Vector2.ONE * (ctx.cell_in * 0.5 - maxf(reach.x, reach.y) - 0.05)
			var off := Vector2(
				(_pick(s, 16, 1000) / 500.0 - 1.0) * maxf(room.x, 0.0),
				(_pick(s, 17, 1000) / 500.0 - 1.0) * maxf(room.y, 0.0)
			)
			var q := mid + off
			if BoardgenDressVegetation._hits(Rect2(q - reach, reach * 2.0), strips):
				continue
			var spec := ctx.spec(module)
			var lift := clampf(BoardgenDressRules.FLAT - spec.aabb_hi.y, 0.0, LITTER_LIFT_IN)
			var xf := Transform3D(
				Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, 1.0, size.y)),
				Vector3(q.x, top + lift, q.y)
			)
			out.append(DressPlacement.new(module, BoardgenDressVegetation._metres(xf), "clutter"))


## The extra density of a cell: wall feet (and the eaves of a roofed one), a lane mouth, a gate.
static func _terms(ctx: DressContext, c: Dictionary, cell: Vector2i, gates: Dictionary) -> float:
	var top := ctx.top_in(cell.x, cell.y)
	var t := 0.0
	var streets := 0
	for d: Vector2i in BoardgenDressVegetation.DIRS:
		var nb := cell + d
		if nb.x < 0 or nb.y < 0 or nb.x >= ctx.nx or nb.y >= ctx.nz:
			continue
		var n: Dictionary = ctx.layout["cells"][nb.y * ctx.nx + nb.x]
		streets += 1 if n["street"] else 0
		if ctx.top_in(nb.x, nb.y) > top:
			t += WALL_FOOT + (EAVE if str(n["lot_kind"]) == "Roofed" else 0.0)
	if c["street"] and streets >= 3:
		t += LANE_MOUTH
	return t + (GATE if gates.has(cell) else 0.0)


## The cells where a street passes the town wall (a level-0 street in a column of five or more
## raised wall cells, where BoardgenTownDressing stands its gate lamps).
static func _gate_cells(ctx: DressContext) -> Dictionary:
	var per_column := {}
	for c: Dictionary in ctx.layout["cells"]:
		if str(c["lot_kind"]) == "Wall" and int(c["level"]) >= 1:
			per_column[int(c["x"])] = int(per_column.get(int(c["x"]), 0)) + 1
	var out := {}
	for c: Dictionary in ctx.layout["cells"]:
		if c["street"] and int(c["level"]) == 0 and int(per_column.get(int(c["x"]), 0)) >= 5:
			out[Vector2i(int(c["x"]), int(c["z"]))] = true
	return out
