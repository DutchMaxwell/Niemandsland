class_name BoardgenDressVegetation
extends DressPlanner
## The vegetation planner of the ruin-town dressing (look review R11): the dr_veg_* modules (kit
## batch K5b, soft_veg) on the level-0 earth, ruin yards and garden plots. Clumps grow in seeded
## patches and thicken by the feet of raised or solid neighbours; a foot run lines each wall foot on
## earth; a garden plot is one plot bed plus nettles. Never in a kept-clear cell (both ladder cells,
## landmarks), a ladder strip, a doorway or the DOOR_CLEAR_IN in front of a door; never on a street,
## a pool or dangerous ground. Placements only: the earth shader underneath is unchanged.

const MODULES: Array[String] = [
	"dr_veg_grass_tuft",
	"dr_veg_grass_tussock",
	"dr_veg_grass_stubble",
	"dr_veg_card_a",
	"dr_veg_card_b",
	"dr_veg_card_c",
	"dr_veg_moss_cushion",
	"dr_veg_nettle",
	"dr_veg_dead_stalks",
	"dr_veg_foot_run_a",
	"dr_veg_foot_run_b",
	"dr_veg_plot_a",
	"dr_veg_plot_b",
]
## Clump picks, weighted by repetition: the open-ground mix and the extra mix by a wall foot.
const OPEN_MIX: Array[String] = [
	"dr_veg_grass_tuft",
	"dr_veg_grass_tuft",
	"dr_veg_grass_tussock",
	"dr_veg_grass_stubble",
	"dr_veg_card_a",
	"dr_veg_card_b",
	"dr_veg_card_c",
	"dr_veg_card_a"
]
const FOOT_MIX: Array[String] = [
	"dr_veg_grass_tussock",
	"dr_veg_nettle",
	"dr_veg_moss_cushion",
	"dr_veg_card_b",
	"dr_veg_grass_tuft"
]
const DOOR_CLEAR_IN := 1.0  # inches in front of a door kept free (lead 25.11.)
const MARGIN_IN := 0.33  # a piece stays this far inside its cell (a turned card reaches 0.3)
const RADIUS_IN := 0.25  # a clump's reach, for the ladder / door keep-outs
const BASE_CLUMPS := 2
const PATCH_CLUMPS := 3  # extra clumps in a thick patch (half the 2 x 2 cell blocks)
const FOOT_CLUMPS := 2  # extra clumps on a cell beside a raised or solid neighbour
const CLUMP_CARDS := 2  # cards round each clump's head piece (10 tris each)
const CARDS: Array[String] = ["dr_veg_card_a", "dr_veg_card_b", "dr_veg_card_c"]
const FOOT_RUN_IN_TEN := 7  # share of the wall-foot edges that carry a run
const SALT := 0x7E6
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func plan(context: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var keep_out: Array[Rect2] = BoardgenDressRules._ladder_zones(context.layout)
	keep_out.append_array(door_zones(context))
	var cells: Array = context.layout["cells"]
	for i in cells.size():
		var kind := ground_kind(context, i)
		if kind == "":
			continue
		var cx := i % context.nx
		var cz := floori(i / float(context.nx))
		var lo := context.origin_in + Vector2(cx, cz) * context.cell_in
		if kind == "rough" and not _hits(Rect2(lo, Vector2.ONE * context.cell_in), keep_out):
			out.append(_plot(context, cx, cz, lo))
		var foot := 0
		for k in 4:
			var n: Vector2i = Vector2i(cx, cz) + DIRS[k]
			if n.x < 0 or n.y < 0 or n.x >= context.nx or n.y >= context.nz:
				continue
			if context.top_in(n.x, n.y) <= 0.0 and context.walkable(n.y * context.nx + n.x):
				continue
			foot += 1
			var run := _foot_run(context, i, k, lo)
			if run != null and not _hits(_run_rect(context, run), keep_out):
				out.append(run)
		var count := BASE_CLUMPS + (FOOT_CLUMPS if foot > 0 else 0)
		count += PATCH_CLUMPS if _pick(floori(cx / 2.0) * 131 + floori(cz / 2.0), 1, 2) == 0 else 0
		if kind == "rough":
			count = 2
		for c in count:
			var at := (
				lo
				+ Vector2(
					MARGIN_IN + _unit(i, 10 + c * 3) * (context.cell_in - 2.0 * MARGIN_IN),
					MARGIN_IN + _unit(i, 11 + c * 3) * (context.cell_in - 2.0 * MARGIN_IN)
				)
			)
			var mix := FOOT_MIX if (foot > 0 and c >= BASE_CLUMPS) or kind == "rough" else OPEN_MIX
			var head: String = mix[_pick(i, 12 + c * 3, mix.size())]
			if kind == "yard" and _pick(i, 40 + c, 3) == 0:
				head = "dr_veg_dead_stalks"
			# a clump reads from the play camera: the head piece and CLUMP_CARDS cards round it
			for m in CLUMP_CARDS + 1:
				var off := Vector2.ZERO
				if m > 0:
					var ang := _unit(i, 70 + c * 7 + m) * TAU
					off = Vector2(cos(ang), sin(ang)) * (0.12 + 0.2 * _unit(i, 90 + c * 7 + m))
				var q := (at + off).clamp(
					lo + Vector2.ONE * MARGIN_IN, lo + Vector2.ONE * (context.cell_in - MARGIN_IN)
				)
				if _hits(
					Rect2(q - Vector2.ONE * RADIUS_IN, Vector2.ONE * 2.0 * RADIUS_IN), keep_out
				):
					continue
				var module := head if m == 0 else CARDS[_pick(i, 110 + c * 7 + m, CARDS.size())]
				var yaw := _unit(i, 13 + c * 3 + m * 17) * TAU
				var sc := 0.85 + 0.35 * _unit(i, 60 + c + m * 19)
				var xf := Transform3D(
					Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(q.x, 0, q.y)
				)
				out.append(DressPlacement.new(module, _metres(xf), "vegetation"))
	return out


## The ground a cell offers vegetation: "earth", "yard" (a ruined house's level-0 rest) or "rough"
## (a garden plot); "" for a street, a raised, solid, dangerous or kept-clear cell.
static func ground_kind(context: DressContext, i: int) -> String:
	var cell: Dictionary = context.layout["cells"][i]
	if int(cell["level"]) != 0 or cell["street"] or context.kept_clear_cell(i):
		return ""
	if not context.walkable(i):
		return ""
	match str(cell["lot_kind"]):
		"Rough":
			return "rough"
		"Terrace":
			return "yard"
		"Street":
			return "earth"  # plain level-0 ground off the streets
	return ""


## The keep-out rect in front of every house door: the door's cell edge, from just inside the face
## to DOOR_CLEAR_IN out of it (plus a clump's reach). Board inches.
static func door_zones(context: DressContext) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for p: DressPlacement in BoardgenDressHouses.new().plan(context):
		if not p.module.ends_with("_door"):
			continue
		var o := p.transform.origin / Units.INCHES_TO_METERS
		var along := p.transform.basis.x.normalized()
		var away := p.transform.basis.z.normalized()
		var a := Vector2(o.x, o.z) - Vector2(along.x, along.z) * RADIUS_IN
		var b := Vector2(o.x, o.z) + Vector2(along.x, along.z) * (context.cell_in + RADIUS_IN)
		var c := Vector2(away.x, away.z) * (DOOR_CLEAR_IN + RADIUS_IN)
		var d := -Vector2(away.x, away.z) * 0.3
		out.append(Rect2(a + d, Vector2.ZERO).expand(b + d).expand(a + c).expand(b + c))
	return out


## A garden-plot bed filling cell (cx, cz), turned a seeded quarter about the cell centre.
func _plot(context: DressContext, cx: int, cz: int, lo: Vector2) -> DressPlacement:
	var i := cz * context.nx + cx
	var centre := lo + Vector2.ONE * context.cell_in * 0.5
	var turn := Basis(Vector3.UP, _pick(i, 2, 4) * PI * 0.5)
	var half := context.cell_in * 0.5
	var xf := (
		Transform3D(turn, Vector3(centre.x, 0, centre.y))
		* Transform3D(Basis(), Vector3(-half, 0, half))
	)
	var module := "dr_veg_plot_a" if _pick(i, 3, 2) == 0 else "dr_veg_plot_b"
	return DressPlacement.new(module, _metres(xf), "vegetation")


## A foot run along edge `k` of earth cell `i` (the neighbour is raised or solid): origin at the
## edge's start, x along it, +z out into the earth cell. null when the edge carries none.
func _foot_run(context: DressContext, i: int, k: int, lo: Vector2) -> DressPlacement:
	if _pick(i, 20 + k, 10) >= FOOT_RUN_IN_TEN:
		return null
	var c := context.cell_in
	var starts := [lo, lo + Vector2(c, 0), lo + Vector2(c, c), lo + Vector2(0, c)]
	var alongs := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	var start: Vector2 = starts[k]
	var along: Vector2 = alongs[k]
	var away := -Vector2(DIRS[k])
	var xf: Transform3D
	var module := "dr_veg_foot_run_a" if _pick(i, 30 + k, 2) == 0 else "dr_veg_foot_run_b"
	var spec := context.spec(module)
	var back := spec.aabb_lo.z if spec != null else 0.0
	xf = BoardgenDressRules.face_xf(
		Vector3(start.x, 0, start.y),
		Vector3(along.x, 0, along.y),
		Vector3(away.x, 0, away.y),
		back - 0.01,  # out by the run's back reach: nothing tucks under the wall face
		0.0
	)
	return DressPlacement.new(module, xf, "vegetation")


## The XZ rect (board inches) of a placed module's aabb.
func _run_rect(context: DressContext, p: DressPlacement) -> Rect2:
	var spec := context.spec(p.module)
	var r := Rect2()
	for k in 8:
		var q := Vector3(
			spec.aabb_hi.x if k & 1 else spec.aabb_lo.x,
			0.0,
			spec.aabb_hi.z if k & 4 else spec.aabb_lo.z
		)
		var w := p.transform * (q * Units.INCHES_TO_METERS) / Units.INCHES_TO_METERS
		r = Rect2(w.x, w.z, 0, 0) if k == 0 else r.expand(Vector2(w.x, w.z))
	return r


static func _hits(r: Rect2, zones: Array[Rect2]) -> bool:
	for z: Rect2 in zones:
		if z.intersects(r):
			return true
	return false


## An inch transform as the metre transform a placement carries.
static func _metres(xf: Transform3D) -> Transform3D:
	return Transform3D(xf.basis, xf.origin * Units.INCHES_TO_METERS)


static func _pick(i: int, salt: int, n: int) -> int:
	return BoardgenDressStory.pick(i, SALT + salt, n)


static func _unit(i: int, salt: int) -> float:
	return BoardgenDressStory.pick(i, SALT + salt, 1000) / 1000.0
