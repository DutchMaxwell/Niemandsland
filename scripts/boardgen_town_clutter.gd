class_name BoardgenTownClutter
extends RefCounted
## Where the authored clutter modules of the ruin town stand (plans A2 / A2b / A6 of PLAN_RUINTOWN_AAA, the assets lane's batches): lamp posts with their glass, the pieces of the wall strip
## (barrels, crates, sacks, a woodpile, a cart wreck ...), flat debris and weeds on open ground, brambles and dead trees on garden plots, ivy on wall faces. Pure data: `plan(layout)` is
## {module: [{xf, colour}]} in metres off the board centre, consumed by BoardgenTownKit. The look must not lie: FLAT pieces (<= 0.08 in) on open ground only, STRIP pieces (<= 0.75 in deep) with
## their origin on a wall face, PLOT pieces on FOREST plots (garden plots) and RUINS yards, WALL pieces (ivy) on faces without a ladder - never on standing room that would read as cover.

const INCHES_TO_METERS := 0.0254
## The pieces of the wall strip, with their extent along the wall (min, max inches off the piece's origin): a piece is moved along the edge so that it stays inside its 3 in cell edge.
const STRIP := {
	"barrel": Vector2(-0.3, 0.3), "crate": Vector2(-0.25, 0.25), "sack_pile": Vector2(-0.51, 0.75), "trough": Vector2(-0.65, 0.65), "bucket": Vector2(-0.15, 0.15),
	"woodpile": Vector2(-0.31, 0.75), "barrel_broken": Vector2(-0.33, 0.78), "crate_broken": Vector2(-0.4, 0.4), "cart_wreck": Vector2(-1.46, 0.73), "loose_wheel": Vector2(-0.34, 0.34),
}
const STRIP_WEIGHTS := ["barrel", "barrel", "crate", "crate", "sack_pile", "trough", "bucket", "woodpile", "woodpile", "barrel_broken", "crate_broken", "cart_wreck", "loose_wheel"]
const FLAT := ["debris_flat_a", "debris_flat_b", "splinters_flat", "weeds_flat", "cloth_flat", "weeds_flat"]
const PLOT_TREES := ["dead_tree_a", "dead_tree_b", "dead_tree_c"]
const PLOT_BRAMBLES := ["bramble_a", "bramble_b"]
const LAMP_MODULES := ["lantern_post", "lantern_glow"]


static func _item(yaw: float, at_in: Vector3) -> Dictionary:
	return {"xf": Transform3D(Basis(Vector3.UP, yaw), at_in * INCHES_TO_METERS), "colour": Color.WHITE}


static func _add(out: Dictionary, module: String, item: Dictionary) -> void:
	if not out.has(module):
		out[module] = []
	out[module].append(item)


## The strip piece a prop box of BoardgenTownDressing.props() is drawn as (its module name); "" for a box that is not a strip prop. Deterministic from the box's cell and wall side.
static func prop_module(box: Dictionary) -> String:
	if not box.get("prop", false) or typeof(box.get("face")) != TYPE_VECTOR2I or not box.has("at"):
		return ""   # (a lean-to box also has a "face": its is a letter)
	var cell: Vector2 = box["at"]
	var i := int(cell.y) * 16 + int(cell.x)
	return STRIP_WEIGHTS[int(BoardgenTownDressing._hash(i, int(box["face"].x + 2 * box["face"].y + 3), 71) * STRIP_WEIGHTS.size()) % STRIP_WEIGHTS.size()]


## {module: [item]}: the whole clutter plan of a layout.
static func plan(layout: Dictionary) -> Dictionary:
	var out := {}
	var cell_in := float(layout["cell_in"])
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var origin := Vector2(nx, nz) * cell_in * -0.5
	# lamp posts: one post and its glass at every lantern (the head at 2.55 in, where the OmniLight is)
	for l: Dictionary in BoardgenTownDressing.lanterns(layout):
		var at: Vector2 = l["at"]
		var yaw := BoardgenTownDressing._hash(int(at.x * 7.0), int(at.y * 7.0), 72) * TAU
		for m in LAMP_MODULES:
			_add(out, m, _item(yaw, Vector3(at.x, 0.0, at.y)))
	# the wall strip: every prop box of the procedural plan becomes one piece, its origin on the wall face, +z away from the wall, kept inside its cell edge
	for b: Dictionary in BoardgenTownDressing.props(layout):
		var m := prop_module(b)
		if m == "":
			continue
		var d: Vector2i = b["face"]
		var cell: Vector2 = b["at"]
		var lo := origin + cell * cell_in
		var along: float = b["along"]
		var span: Vector2 = STRIP[m]
		along = clampf(along, 0.08 - span.x, cell_in - 0.08 - span.y)
		var pos := Vector2(lo.x + along, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y + along)
		# local +x runs along the wall; the yaw turns +z away from it, +x follows (for a north wall +x = +x of the board)
		_add(out, m, _item(atan2(-float(d.x), -float(d.y)), Vector3(pos.x, 0.0, pos.y)))
	_flat(layout, out)
	_plots(layout, out)
	_ivy(layout, out)
	return out


## Cells nothing may be put on: both ends of every ladder, a landmark's footprint.
static func _kept_clear(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var clear := {}
	for c: Dictionary in layout["connectors"]:
		clear[int(c["low"])] = true
		clear[int(c["high"])] = true
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				clear[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	return clear


static func _wall_span(layout: Dictionary) -> Vector2i:
	var cols := []
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] == "Wall" and cd["level"] >= 2:
			cols.append(cd["x"])
	return Vector2i(cols.min(), cols.max()) if not cols.is_empty() else Vector2i(-1, 99)


## FLAT pieces (<= 0.08 in): debris, splinters, cloth, weeds on bare open ground - one cell in seven inside the walls, one in two OUTSIDE the wall and in the deployment bands (the emptiest earth
## of the board), never beside a wall (the strip has its own pieces), on a ladder end, a landmark, a pool, a plot or a lot.
static func _flat(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	var span := _wall_span(layout)
	var cells: Array = layout["cells"]
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 0 or clear.has(i) or ["Hazard", "Rough", "Wall", "Roofed", "Terrace", "Block", "Deck"].has(cd["lot_kind"]):
			continue
		var by_wall := false
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n := Vector2i(cd["x"], cd["z"]) + d
			by_wall = by_wall or (n.x >= 0 and n.y >= 0 and n.x < nx and n.y < nz and int(cells[n.y * nx + n.x]["level"]) > 0)
		if by_wall:
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		var outer: bool = cd["deploy"] != 0 or cd["x"] < span.x or cd["x"] > span.y
		if BoardgenTownDressing._hash(i, half, 73) > (0.5 if outer else (0.07 if cd["street"] else 0.16)):
			continue
		var m: String = FLAT[int(BoardgenTownDressing._hash(i, half, 74) * FLAT.size()) % FLAT.size()]
		var at := origin + Vector2(cd["x"], cd["z"]) * cell_in + Vector2(0.8 + 1.4 * BoardgenTownDressing._hash(i, half, 75), 0.8 + 1.4 * BoardgenTownDressing._hash(i, half, 76))
		_add(out, m, _item(BoardgenTownDressing._hash(i, half, 77) * TAU, Vector3(at.x, 0.0, at.y)))


## PLOT pieces: a garden plot is FOREST (cover already): a dead tree on a third of them, brambles on most of the rest; a RUINS yard (the level-0 rest of a Terrace) gets brambles on one in five.
static func _plots(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	for cd: Dictionary in layout["cells"]:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 0 or clear.has(i) or cd["street"] or not ["Rough", "Terrace"].has(cd["lot_kind"]):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		var h := BoardgenTownDressing._hash(i, half, 78)
		var m := ""
		if cd["lot_kind"] == "Rough":
			m = PLOT_TREES[int(BoardgenTownDressing._hash(i, half, 79) * 3.0) % 3] if h < 0.33 else (PLOT_BRAMBLES[int(BoardgenTownDressing._hash(i, half, 80) * 2.0) % 2] if h < 0.85 else "")
		elif h < 0.2:
			m = PLOT_BRAMBLES[int(BoardgenTownDressing._hash(i, half, 80) * 2.0) % 2]
		if m == "":
			continue
		var at := origin + (Vector2(cd["x"], cd["z"]) + Vector2(0.5, 0.5)) * cell_in + Vector2(BoardgenTownDressing._hash(i, half, 81) - 0.5, BoardgenTownDressing._hash(i, half, 82) - 0.5) * 0.6
		_add(out, m, _item(BoardgenTownDressing._hash(i, half, 83) * TAU, Vector3(at.x, 0.0, at.y)))


## WALL pieces: ivy strands up a wall face (<= 0.12 in off it), on one face in eight of a raised cell that looks at open ground, never on a ladder's face.
static func _ivy(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	var cells: Array = layout["cells"]
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] < 1 or cd["lot_kind"] == "Roofed" or clear.has(i):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			var d: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
			var n := Vector2i(cd["x"], cd["z"]) + d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz:
				continue
			var nb: Dictionary = cells[n.y * nx + n.x]
			var j: int = n.y * nx + n.x
			if nb["level"] != 0 or nb["street"] or clear.has(j) or BoardgenTownDressing._hash(i, half, 84 + side) > 0.125:
				continue
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var along := 0.8 + 1.4 * BoardgenTownDressing._hash(i, half, 90 + side)
			var pos := Vector2(lo.x + along, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y + along)
			_add(out, "ivy_strand_a" if BoardgenTownDressing._hash(i, half, 95 + side) < 0.5 else "ivy_strand_b", _item(atan2(float(d.x), float(d.y)), Vector3(pos.x, 0.0, pos.y)))
