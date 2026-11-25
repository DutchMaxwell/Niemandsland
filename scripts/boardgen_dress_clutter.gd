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
	"dr_litter_planks_flat",
	"dr_litter_staves_flat"
]
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
