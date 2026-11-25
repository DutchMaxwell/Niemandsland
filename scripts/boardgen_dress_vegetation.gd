class_name BoardgenDressVegetation
extends DressPlanner
## The vegetation planner of the ruin-town dressing (look review R11): the dr_veg_* modules (kit
## batch K5b, soft_veg) on the level-0 earth, ruin yards and garden plots. Clumps (a solid head and
## cards round it) grow in seeded patches and thicken by the feet of raised or solid neighbours; a
## foot run lines most wall feet on earth; a garden plot gets a plot bed. Never in a kept-clear cell
## (both ladder cells, landmarks), a ladder strip, a doorway or the DOOR_CLEAR_IN in front of a
## door; never on a street, a pool or dangerous ground. Placements only: the earth shader stays.

const HEADS: Array[String] = ["dr_veg_grass_tuft", "dr_veg_grass_tussock", "dr_veg_grass_stubble"]
const FOOT_HEADS: Array[String] = ["dr_veg_grass_tussock", "dr_veg_nettle", "dr_veg_moss_cushion"]
const CARDS: Array[String] = ["dr_veg_card_a", "dr_veg_card_b", "dr_veg_card_c"]
const RUNS: Array[String] = ["dr_veg_foot_run_a", "dr_veg_foot_run_b"]
const PLOTS: Array[String] = ["dr_veg_plot_a", "dr_veg_plot_b"]
const STALKS: Array[String] = ["dr_veg_dead_stalks"]
const MODULES: Array[String] = HEADS + FOOT_HEADS + CARDS + RUNS + PLOTS + STALKS
const DOOR_CLEAR_IN := 1.0  # inches in front of a door kept free (lead 25.11.)
const MARGIN_IN := 0.33  # a piece stays this far inside its cell (a turned card reaches 0.3)
const RADIUS_IN := 0.25  # a piece's reach, for the ladder / door keep-outs
const RUN_DEPTH_IN := 0.7  # how far a foot run reaches out of its wall
const CLUMPS := [2, 5]  # clumps per cell outside / inside a thick patch (half the 2 x 2 blocks)
const FOOT_CLUMPS := 2  # extra clumps on a cell beside a raised or solid neighbour
const CLUMP_CARDS := 2  # cards round each clump's head (10 tris each)
const FOOT_RUN_IN_TEN := 7  # share of the wall-foot edges that carry a run
const SALT := 0x7E6
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func plan(ctx: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var keep_out: Array[Rect2] = BoardgenDressRules._ladder_zones(ctx.layout)
	keep_out.append_array(door_zones(ctx))
	var c := ctx.cell_in
	for i in (ctx.layout["cells"] as Array).size():
		var kind := ground_kind(ctx, i)
		if kind == "":
			continue
		var cell := Vector2i(i % ctx.nx, floori(i / float(ctx.nx)))
		var lo := ctx.origin_in + Vector2(cell) * c
		if kind == "rough" and not _hits(Rect2(lo, Vector2.ONE * c), keep_out):
			var turn := Basis(Vector3.UP, _pick(i, 2, 4) * PI * 0.5)
			var mid := lo + Vector2.ONE * c * 0.5
			var xf := Transform3D(turn, Vector3(mid.x, 0, mid.y)).translated_local(
				Vector3(-c * 0.5, 0, c * 0.5)
			)
			out.append(DressPlacement.new(PLOTS[_pick(i, 3, 2)], _metres(xf), "vegetation"))
		var foot := 0
		for k in 4:
			var n: Vector2i = cell + DIRS[k]
			if n.x < 0 or n.y < 0 or n.x >= ctx.nx or n.y >= ctx.nz:
				continue
			if ctx.top_in(n.x, n.y) <= 0.0 and ctx.walkable(n.y * ctx.nx + n.x):
				continue
			foot += 1
			# a run along edge k: x along the edge, +z out of the wall into this cell
			var along := Vector2(-DIRS[k].y, DIRS[k].x)
			var away := -Vector2(DIRS[k])
			var start := lo + c * (Vector2.ONE * 0.5 + Vector2(DIRS[k]) * 0.5 - along * 0.5)
			var run := Rect2(start, Vector2.ZERO).expand(start + along * c + away * RUN_DEPTH_IN)
			if _pick(i, 20 + k, 10) >= FOOT_RUN_IN_TEN or _hits(run, keep_out):
				continue
			var module: String = RUNS[_pick(i, 30 + k, 2)]
			var back := ctx.spec(module).aabb_lo.z if ctx.spec(module) != null else 0.0
			var a3 := Vector3(along.x, 0, along.y)
			var xf := BoardgenDressRules.face_xf(
				Vector3(start.x, 0, start.y), a3, Vector3(away.x, 0, away.y), back - 0.01, 0.0
			)
			out.append(DressPlacement.new(module, xf, "vegetation"))
		var patch := _pick(floori(cell.x / 2.0) * 131 + floori(cell.y / 2.0), 1, 2)
		var count: int = 2 if kind == "rough" else CLUMPS[patch] + (FOOT_CLUMPS if foot > 0 else 0)
		for j in count:
			var at := (
				lo + Vector2(_unit(i, 10 + j * 3), _unit(i, 11 + j * 3)) * (c - 2.0 * MARGIN_IN)
			)
			var heads := FOOT_HEADS if (foot > 0 and j >= 2) or kind == "rough" else HEADS
			var head: String = heads[_pick(i, 12 + j * 3, heads.size())]
			head = STALKS[0] if kind == "yard" and _pick(i, 40 + j, 3) == 0 else head
			for m in CLUMP_CARDS + 1:  # a clump reads from the play camera: a head and cards round it
				var ang := _unit(i, 70 + j * 7 + m) * TAU
				var off := Vector2(cos(ang), sin(ang)) * (0.12 + 0.2 * _unit(i, 90 + j * 7 + m))
				var q := (at + Vector2.ONE * MARGIN_IN + off * signf(m)).clamp(
					lo + Vector2.ONE * MARGIN_IN, lo + Vector2.ONE * (c - MARGIN_IN)
				)
				if _hits(
					Rect2(q - Vector2.ONE * RADIUS_IN, Vector2.ONE * 2.0 * RADIUS_IN), keep_out
				):
					continue
				var module := head if m == 0 else CARDS[_pick(i, 110 + j * 7 + m, CARDS.size())]
				var basis := Basis(Vector3.UP, _unit(i, 13 + j * 3 + m * 17) * TAU)
				var xf := Transform3D(
					basis.scaled(Vector3.ONE * (0.85 + 0.35 * _unit(i, 60 + j + m * 19))),
					Vector3(q.x, 0, q.y)
				)
				out.append(DressPlacement.new(module, _metres(xf), "vegetation"))
	return out


## The ground a cell offers vegetation: "earth" (plain level-0 ground off the streets), "yard" (a
## ruined house's level-0 rest) or "rough" (a garden plot); "" for any other cell.
static func ground_kind(ctx: DressContext, i: int) -> String:
	var cell: Dictionary = ctx.layout["cells"][i]
	if int(cell["level"]) != 0 or cell["street"] or ctx.kept_clear_cell(i) or not ctx.walkable(i):
		return ""
	return {"Rough": "rough", "Terrace": "yard", "Street": "earth"}.get(str(cell["lot_kind"]), "")


## The keep-out rect in front of every house door: the door's cell edge, from just inside the face
## to DOOR_CLEAR_IN out of it (plus a piece's reach). Board inches.
static func door_zones(ctx: DressContext) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for p: DressPlacement in BoardgenDressHouses.new().plan(ctx):
		if p.module.ends_with("_door"):
			var o := p.transform.origin / Units.INCHES_TO_METERS
			var along := Vector2(p.transform.basis.x.x, p.transform.basis.x.z).normalized()
			var away := Vector2(p.transform.basis.z.x, p.transform.basis.z.z).normalized()
			var a := Vector2(o.x, o.z) - along * RADIUS_IN - away * 0.3
			var b := a + along * (ctx.cell_in + 2.0 * RADIUS_IN)
			var out_by := away * (DOOR_CLEAR_IN + RADIUS_IN + 0.3)
			out.append(Rect2(a, Vector2.ZERO).expand(b).expand(a + out_by).expand(b + out_by))
	return out


static func _hits(r: Rect2, zones: Array[Rect2]) -> bool:
	return zones.any(func(z: Rect2) -> bool: return z.intersects(r))


## An inch transform as the metre transform a placement carries.
static func _metres(xf: Transform3D) -> Transform3D:
	return Transform3D(xf.basis, xf.origin * Units.INCHES_TO_METERS)


static func _pick(i: int, salt: int, n: int) -> int:
	return BoardgenDressStory.pick(i, SALT + salt, n)


static func _unit(i: int, salt: int) -> float:
	return BoardgenDressStory.pick(i, SALT + salt, 1000) / 1000.0
