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
## The yaw of a tower turret stub per corner of the tower top (NW, NE, SE, SW): the module fills the +x / +z quadrant of its origin, so each turns that quadrant inward.
const TURRET_YAW := [0.0, -PI * 0.5, PI, PI * 0.5]
## The share of towers that carry a heavy charred cap frame (lead 21.11.: fewer - the thin frames read as scaffolding when a third of the towers had one).
const BURNT_CAP_SHARE := 0.12
const LAMP_MODULES := ["lantern_post", "lantern_glow"]
## The fences of a garden plot (kit batch A7, PLOT-EDGE): a straight 3 in run, a run with a 1 in gap (the hurdle lying in the bed), a corner of two arms. One style per plot.
const FENCE_STYLES := [["fence_wattle", "fence_wattle_gap", "fence_wattle_corner"], ["fence_plank", "fence_plank_gap", "fence_plank_corner"]]
## The corner piece's yaw for two fenced sides that meet (side, side + 1; sides N, E, S, W): its arms run along local +x and +z from the plot corner.
const FENCE_CORNER_YAW := [-PI * 0.5, PI, PI * 0.5, 0.0]
const FOUNTAIN_MODULES := ["fountain_basin", "fountain_column", "fountain_leaves"]
const STATUE_MODULES := ["statue_plinth", "statue_stump"]


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
	var scenes := BoardgenTownScenes.plan(layout)   # story scenes (plan PLAN_RUINTOWN_GRIT S2): their cells carry no salted flat piece
	for m: String in scenes["items"]:
		for it: Dictionary in scenes["items"][m]:
			_add(out, m, it)
	_flat(layout, out, scenes["reserved"])
	_plots(layout, out)
	_fences(layout, out)
	var feet := wall_feet(layout)
	for m: String in feet:
		for it: Dictionary in feet[m]:
			_add(out, m, it)
	_ivy(layout, out)
	_ivy_clusters(layout, out, scenes["reserved"])
	_landmarks(layout, out)
	_hall_and_towers(layout, out)
	_square_and_walls(layout, out)
	_signs(layout, out)
	_yards(layout, out)
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
static func _flat(layout: Dictionary, out: Dictionary, reserved: Dictionary = {}) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	var span := _wall_span(layout)
	var cells: Array = layout["cells"]
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 0 or clear.has(i) or reserved.has(i) or ["Hazard", "Rough", "Wall", "Roofed", "Terrace", "Block", "Deck"].has(cd["lot_kind"]):
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


## FENCES round the garden plots (Rough, level 0, off the street; kit batch A7, PLOT-EDGE): on every plot edge that looks at open level-0 ground, inside the plot (the origin on the edge,
## +z into the plot, the fence line 0.15 in in), 0.8-0.91 in high - a border, not cover (the plot is forest already). An edge is a straight run, a broken run (one in six) or open (one in
## seven); two straight runs that meet become one corner piece; every plot keeps at least one gap. Never on a street cell, a ladder end or along a raised wall.
static func _fences(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	var cells: Array = layout["cells"]
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var plot := func(i: int) -> bool:
		var c: Dictionary = cells[i]
		return c["lot_kind"] == "Rough" and int(c["level"]) == 0 and not c["street"] and not clear.has(i)
	var group := {}   # cell -> the smallest cell index of its plot (one style per plot)
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if group.has(i) or not plot.call(i):
			continue
		var todo := [i]
		group[i] = i
		while not todo.is_empty():
			var k: int = todo.pop_back()
			for d: Vector2i in dirs:
				var n := Vector2i(k % nx, k / nx) + d
				var j := n.y * nx + n.x
				if n.x >= 0 and n.y >= 0 and n.x < nx and n.y < nz and not group.has(j) and plot.call(j):
					group[j] = i
					todo.append(j)
	var fates := {}   # cell -> [fate per side]: "" no fence, "run", "gap", "open"
	var opened := {}
	for i: int in group:
		var half := 1 if i / nx >= nz / 2 else 0
		var f := ["", "", "", ""]
		for side in 4:
			var n := Vector2i(i % nx, i / nx) + dirs[side]
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz:
				continue
			var j := n.y * nx + n.x
			if group.get(j, -1) == group[i] or int(cells[j]["level"]) != 0 or cells[j]["lot_kind"] == "Hazard":
				continue
			var h := BoardgenTownDressing._hash(i, half, 200 + side)
			f[side] = "gap" if h < 0.17 else ("open" if h < 0.31 else "run")
			if f[side] != "run":
				opened[group[i]] = true
		fates[i] = f
	for i: int in fates:   # a plot with no way in gets its first fenced edge broken
		if opened.has(group[i]):
			continue
		for side in 4:
			if fates[i][side] == "run":
				fates[i][side] = "gap"
				opened[group[i]] = true
				break
	for i: int in fates:
		var f: Array = fates[i]
		var half := 1 if i / nx >= nz / 2 else 0
		var style: Array = FENCE_STYLES[int(BoardgenTownDressing._hash(group[i], half, 205) * 2.0) % 2]
		var lo := origin + Vector2(i % nx, i / nx) * cell_in
		var cornered := [false, false, false, false]
		for side in 4:
			var nxt := (side + 1) % 4
			if f[side] == "run" and f[nxt] == "run" and not cornered[side] and not cornered[nxt]:
				cornered[side] = true
				cornered[nxt] = true
				var c := lo + Vector2(cell_in if side in [0, 1] else 0.0, cell_in if side in [1, 2] else 0.0)   # NE, SE, SW, NW
				_add(out, style[2], _item(FENCE_CORNER_YAW[side], Vector3(c.x, 0.0, c.y)))
		for side in 4:
			if cornered[side] or not ["run", "gap"].has(f[side]):
				continue
			var d := dirs[side]
			var mid := lo + (Vector2(0.5, 0.5) + Vector2(d) * 0.5) * cell_in
			_add(out, style[0] if f[side] == "run" else style[1], _item(atan2(-float(d.x), -float(d.y)), Vector3(mid.x, 0.0, mid.y)))   # +z into the plot


## The feet of the city wall (kit batch A7): a graded rubble spill (2.5 in, STRIP) at every open foot of the two wall cells beside a breach - the wall came down there -, and a buttress
## (2.6 in on a 3 in wall, 3.8 in on a higher one, 0.62 in deep, STRIP) on the FIELD face of long runs, every fourth cell counted from the board's middle row (half-turn twins), not beside
## a breach. Never on a ladder end, a hazard or a landmark. {module: [item]}.
static func wall_feet(layout: Dictionary) -> Dictionary:
	var out := {}
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	var cells: Array = layout["cells"]
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var open_foot := func(c: Vector2i) -> bool:
		if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz:
			return false
		var cd: Dictionary = cells[c.y * nx + c.x]
		return int(cd["level"]) == 0 and not clear.has(c.y * nx + c.x) and not ["Hazard", "Wall", "Rough"].has(cd["lot_kind"])
	var by_breach := {}
	for cd: Dictionary in cells:
		if cd["lot_kind"] != "Wall" or int(cd["level"]) != 0:
			continue
		for d: Vector2i in dirs:
			var w := Vector2i(cd["x"], cd["z"]) + d
			if w.x < 0 or w.y < 0 or w.x >= nx or w.y >= nz or int(cells[w.y * nx + w.x]["level"]) == 0:
				continue
			by_breach[w.y * nx + w.x] = true
			for f: Vector2i in dirs:
				if f == -d or f == d or not open_foot.call(w - f):
					continue   # the faces across the wall's run only (the breach cell and the next wall cell are no foot)
				var lo := origin + Vector2(w) * cell_in
				var along := 1.5 + 0.15 * (float(d.x) if f.x == 0 else float(d.y)) * -1.0   # a little towards the breach
				var pos := Vector2(lo.x + along, lo.y if -f.y < 0 else lo.y + cell_in) if f.x == 0 else Vector2(lo.x if -f.x < 0 else lo.x + cell_in, lo.y + along)
				_add(out, "wall_rubble_spill", _item(atan2(float(-f.x), float(-f.y)), Vector3(pos.x, 0.0, pos.y)))   # +z away from the wall, onto the foot
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["lot_kind"] != "Wall" or int(cd["level"]) < 1 or by_breach.has(i) or int(absf(float(cd["z"]) - 7.5)) % 4 != 1:
			continue
		var field := Vector2i(-1, 0) if int(cd["x"]) * 2 < nx else Vector2i(1, 0)
		var w := Vector2i(cd["x"], cd["z"])
		var run := 0
		for dz in [-1, 1]:
			var n := w + Vector2i(0, dz)
			run += 1 if n.y >= 0 and n.y < nz and cells[n.y * nx + n.x]["lot_kind"] == "Wall" and int(cells[n.y * nx + n.x]["level"]) >= 1 else 0
		if run < 2 or not open_foot.call(w + field):
			continue   # a long run only: wall above and below
		var lo := origin + Vector2(w) * cell_in
		var pos := Vector2(lo.x if field.x < 0 else lo.x + cell_in, lo.y + 1.5)
		_add(out, "wall_buttress_a" if int(cd["level"]) == 1 else "wall_buttress_b", _item(atan2(float(field.x), 0.0), Vector3(pos.x, 0.0, pos.y)))
	return out


## IVY CLUSTERS (kit batch A7, WALL, <= 0.17 in proud) on the SHADE faces - east and west, the faces both moons graze -: a large mass hanging from the top edge of a raised cell whose
## neighbours along the face are raised too (it is 3.6 in wide), a small one climbing from the foot where no strip piece or scene stands. Never on a ladder face, never on a strand of _ivy.
static func _ivy_clusters(layout: Dictionary, out: Dictionary, reserved: Dictionary = {}) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	var cells: Array = layout["cells"]
	var taken := {}
	for b: Dictionary in BoardgenTownDressing.props(layout):
		if typeof(b.get("face")) == TYPE_VECTOR2I:
			taken["%d/%d/%s" % [int(b["at"].x), int(b["at"].y), b["face"]]] = true
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] < 1 or cd["lot_kind"] == "Roofed" or clear.has(i):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in [1, 3]:
			var d: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
			var n := Vector2i(cd["x"], cd["z"]) + d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz:
				continue
			var j: int = n.y * nx + n.x
			var nb: Dictionary = cells[j]
			if nb["level"] != 0 or clear.has(j) or nb["lot_kind"] == "Hazard" or (not nb["street"] and BoardgenTownDressing._hash(i, half, 84 + side) <= 0.125):
				continue   # (the last: a strand of _ivy is there)
			var h := BoardgenTownDressing._hash(i, half, 220 + side)
			if h > 0.3:
				continue
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var yaw := atan2(float(d.x), float(d.y))
			var x := lo.x if d.x < 0 else lo.x + cell_in
			var top := float(layout["level_in"][int(cd["level"])])
			var wide := true
			for dz in [-1, 1]:
				var m := Vector2i(cd["x"], cd["z"] + dz)
				wide = wide and m.y >= 0 and m.y < nz and int(cells[m.y * nx + m.x]["level"]) >= int(cd["level"])
			if h < 0.18 and wide:
				_add(out, "ivy_cluster_large", _item(yaw, Vector3(x, top, lo.y + 1.5)))
			elif not reserved.has(j) and not taken.has("%d/%d/%s" % [n.x, n.y, -d]):
				_add(out, "ivy_cluster_small", _item(yaw, Vector3(x, 0.0, lo.y + 0.8 + 1.4 * BoardgenTownDressing._hash(i, half, 224 + side))))


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


## The landmarks of the town (R-L9 looks): the centre FOUNTAIN (basin, column with a broken bowl, leaves) on the market square, a STATUE (plinth and a broken stump, no figure) on a 1 x 1 post, a pool of
## 2 x 2 cells as a pond with a stone KERB round it (3 in runs, +z over the water), a smaller pool as a WELL (ring and winch frame). Each stays inside its footprint; the core's class and collider
## of the landmark are untouched (the solid fountain / statue boxes keep their colliders, the kit only draws them).
static func _landmarks(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for lm: Dictionary in layout["landmarks"]:
		var lo := origin + Vector2(lm["x"], lm["z"]) * cell_in
		var size := Vector2(lm["w"], lm["h"]) * cell_in
		var centre := lo + size * 0.5
		match lm["kind"]:
			"TankCluster":
				for m in FOUNTAIN_MODULES:   # the basin of separate ashlars and a broken side (kit batch A7; the kit draws the older basin while it is not cached)
					_add(out, "fountain_basin_b" if m == "fountain_basin" else m, _item(0.0, Vector3(centre.x, 0.0, centre.y)))
			"Crane":
				for m in STATUE_MODULES:
					_add(out, m, _item(float(lm["turn"]) * PI * 0.5, Vector3(centre.x, 0.0 if m == "statue_plinth" else 1.57, centre.y)))
			"Sump":   # a stone kerb round every pool, the well's too (lead 21.11.: the water ended in a hard rectangular edge)
				for ix in int(lm["w"]):   # north and south edges
					_add(out, "pool_kerb", _item(0.0, Vector3(lo.x + (ix + 0.5) * cell_in, 0.0, lo.y)))
					_add(out, "pool_kerb", _item(PI, Vector3(lo.x + (ix + 0.5) * cell_in, 0.0, lo.y + size.y)))
				for iz in int(lm["h"]):   # west and east edges
					_add(out, "pool_kerb", _item(PI * 0.5, Vector3(lo.x, 0.0, lo.y + (iz + 0.5) * cell_in)))
					_add(out, "pool_kerb", _item(-PI * 0.5, Vector3(lo.x + size.x, 0.0, lo.y + (iz + 0.5) * cell_in)))
				if lm["w"] < 2 or lm["h"] < 2:
					for m in ["well_ring", "well_frame"]:
						_add(out, m, _item(0.0 if lm["w"] >= lm["h"] else PI * 0.5, Vector3(centre.x, 0.0, centre.y)))


## The height (inches) of the highest cell under a landmark.
static func _top_of(layout: Dictionary, lm: Dictionary) -> float:
	var level := 0
	for dz in int(lm["h"]):
		for dx in int(lm["w"]):
			level = maxi(level, int(layout["cells"][(int(lm["z"]) + dz) * int(layout["nx"]) + int(lm["x"]) + dx]["level"]))
	return float(layout["level_in"][level])


## The HALL (PumpHouse on a raised block) and the tower tops: stub columns (1.78 / 0.98 in) in the edge strip of the hall's top, a fallen pediment lying on one edge, a step at a level-0 edge;
## on each 2 x 2 tower a corner turret stub inside the 0.75 in corner square (one tower in eight carries a heavy charred cap frame on the crown instead). Every piece inside the strip or see-through.
static func _hall_and_towers(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	for lm: Dictionary in layout["landmarks"]:
		if lm["kind"] != "PumpHouse":
			continue
		var top := _top_of(layout, lm)
		var lo := origin + Vector2(lm["x"], lm["z"]) * cell_in
		var size := Vector2(lm["w"], lm["h"]) * cell_in
		var i0: int = int(lm["z"]) * nx + int(lm["x"])
		var half := 1 if lm["z"] * 2 >= nz else 0
		# columns along the north and south edges of the top, a third in from each end, inside the strip (origin on the outer face, +z inward)
		for k in 2:
			var along := size.x * (0.3 + 0.4 * k)
			_add(out, "hall_column_a" if BoardgenTownDressing._hash(i0, half, 130 + k) < 0.5 else "hall_column_b", _item(0.0, Vector3(lo.x + along, top, lo.y)))
			_add(out, "hall_column_b" if BoardgenTownDressing._hash(i0, half, 134 + k) < 0.5 else "hall_column_a", _item(PI, Vector3(lo.x + size.x - along, top, lo.y + size.y)))
		_add(out, "hall_pediment", _item(PI * 0.5, Vector3(lo.x, top, lo.y + size.y * 0.5)))   # fallen along the west edge
		# a step at a level-0 edge cell of the block that looks at bare open ground
		for iz in int(lm["h"]):
			var c := Vector2i(int(lm["x"]) - 1, int(lm["z"]) + iz)
			if c.x >= 0 and int(cells[c.y * nx + c.x]["level"]) == 0 and not cells[c.y * nx + c.x]["street"] and cells[c.y * nx + c.x]["lot_kind"] == "Street":
				_add(out, "hall_step", _item(-PI * 0.5, Vector3(lo.x, 0.0, lo.y + (iz + 0.5) * cell_in)))   # +z out to the west
				break
	# tower tops: every level-3 non-wall 2 x 2 block
	var seen := {}
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 3 or cd["lot_kind"] == "Wall" or seen.has(i):
			continue
		var block := [i, i + 1, i + nx, i + nx + 1]
		var ok: bool = cd["x"] + 1 < nx and cd["z"] + 1 < nz
		for j: int in block:
			ok = ok and j < cells.size() and int(cells[j]["level"]) == 3 and cells[j]["lot_kind"] != "Wall"
		if not ok:
			continue
		for j: int in block:
			seen[j] = true
		var half := 1 if cd["z"] * 2 >= nz else 0
		var blo := origin + Vector2(cd["x"], cd["z"]) * cell_in
		var top9 := float(layout["level_in"][3])
		if BoardgenTownDressing._hash(i, half, 140) < BURNT_CAP_SHARE:
			_add(out, "tower_cap_burnt", _item(BoardgenTownDressing._hash(i, half, 141) * TAU, Vector3(blo.x + cell_in, top9, blo.y + cell_in)))
		elif BoardgenTownDressing._hash(i, half, 142) < 0.7:
			var corner := int(BoardgenTownDressing._hash(i, half, 143) * 4.0) % 4
			var corners: Array[Vector2] = [Vector2(blo.x, blo.y), Vector2(blo.x + 2.0 * cell_in, blo.y), Vector2(blo.x + 2.0 * cell_in, blo.y + 2.0 * cell_in), Vector2(blo.x, blo.y + 2.0 * cell_in)]
			var at: Vector2 = corners[corner]
			_add(out, "tower_turret", _item(TURRET_YAW[corner], Vector3(at.x, top9, at.y)))


## The market square and the walls round it: stalls (intact or ruined frame with its awning) and braziers in the 0.75 in strip of the square's wall faces, signs (a bracket and a board) on the
## faces of the houses round it, pool spouts on a wall face beside a pool, at most two laundry lines along tall house faces. The square is the street block about the board centre.
static func _square_and_walls(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	var clear := _kept_clear(layout)
	var laundry := 0
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
			var j: int = n.y * nx + n.x
			var nb: Dictionary = cells[j]
			if nb["level"] != 0 or clear.has(j):
				continue
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var along := 1.0 + 1.0 * BoardgenTownDressing._hash(i, half, 150 + side)
			var pos := Vector2(lo.x + along, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y + along)
			var yaw := atan2(float(d.x), float(d.y))   # +z out of the wall
			var on_square: bool = nb["street"] and absf(n.x - 7.5) <= 2.5 and absf(n.y - 7.5) <= 3.5
			if nb["lot_kind"] == "Hazard" and BoardgenTownDressing._hash(i, half, 160 + side) < 0.5:
				_add(out, "pool_spout", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
			elif on_square:
				var h := BoardgenTownDressing._hash(i, half, 170 + side)
				if h < 0.22:
					var intact := BoardgenTownDressing._hash(i, half, 171) < 0.55
					_add(out, "stall_frame" if intact else "stall_frame_ruined", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
					_add(out, "stall_awning" if intact else "stall_awning_ruined", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
				elif h < 0.30:
					_add(out, "brazier", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
					_add(out, "brazier_coals", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
				elif h < 0.42 and cd["lot_kind"] != "Wall":
					_add(out, "sign_bracket", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
					_add(out, "sign_board_loaf" if BoardgenTownDressing._hash(i, half, 172) < 0.5 else "sign_board_boot", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
			elif laundry < 2 and cd["level"] >= 2 and cd["lot_kind"] != "Wall" and not nb["street"] and BoardgenTownDressing._hash(i, half, 180 + side) < 0.15:
				laundry += 1
				_add(out, "laundry_line", _item(yaw, Vector3(pos.x, 0.0, pos.y)))


## Large hanging SIGNS (kit batch A8) on the street fronts off the square: an iron arm at 2.45 in with a framed board (a key, a fish, a mug or shears, no lettering) on the face of a raised
## house cell (not the wall, not an intact house) that looks at a street, everything above 1.85 in - over the heads of the models, a thin edge from above. One face in five, at most three a
## half; never on a ladder face, an ivy cluster's face or within 1 in of a lamp post.
const SIGN_BOARDS := ["sign_large_key", "sign_large_fish", "sign_large_mug", "sign_large_shears"]
const SIGNS_PER_HALF := 3


static func _signs(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	var clear := _kept_clear(layout)
	var lamps := BoardgenTownDressing.lanterns(layout).map(func(l: Dictionary) -> Vector2: return l["at"])
	var per_half := [0, 0]
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if int(cd["level"]) < 1 or ["Wall", "Roofed"].has(cd["lot_kind"]) or clear.has(i):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			if per_half[half] >= SIGNS_PER_HALF:
				break
			var d: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
			var n := Vector2i(cd["x"], cd["z"]) + d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz:
				continue
			var j: int = n.y * nx + n.x
			var nb: Dictionary = cells[j]
			if int(nb["level"]) != 0 or not nb["street"] or clear.has(j) or (absf(n.x - 7.5) <= 2.5 and absf(n.y - 7.5) <= 3.5):
				continue   # a street front off the square (the square has its own small signs)
			if side % 2 == 1 and BoardgenTownDressing._hash(i, half, 220 + side) <= 0.3:
				continue   # an ivy cluster's face
			if BoardgenTownDressing._hash(i, half, 230 + side) > 0.2:
				continue
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var along := 0.8 + 1.4 * BoardgenTownDressing._hash(i, half, 234 + side)
			var pos := Vector2(lo.x + along, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y + along)
			if lamps.any(func(l: Vector2) -> bool: return l.distance_to(pos) < 1.0):
				continue
			per_half[half] += 1
			var yaw := atan2(float(d.x), float(d.y))   # +z out of the wall, over the street
			_add(out, "sign_large_iron", _item(yaw, Vector3(pos.x, 0.0, pos.y)))
			_add(out, SIGN_BOARDS[int(BoardgenTownDressing._hash(i, half, 238 + side) * 4.0) % 4], _item(yaw, Vector3(pos.x, 0.0, pos.y)))


## Rubble heaps (<= 0.57 in high, 2 in across) on the level-0 rest of a ruined house (RUINS yard): one yard cell in four.
static func _yards(layout: Dictionary, out: Dictionary) -> void:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var clear := _kept_clear(layout)
	for cd: Dictionary in layout["cells"]:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 0 or cd["lot_kind"] != "Terrace" or cd["street"] or clear.has(i):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		if BoardgenTownDressing._hash(i, half, 190) > 0.25:
			continue
		var at := origin + (Vector2(cd["x"], cd["z"]) + Vector2(0.5, 0.5)) * cell_in
		_add(out, "rubble_heap_a" if BoardgenTownDressing._hash(i, half, 191) < 0.5 else "rubble_heap_b", _item(BoardgenTownDressing._hash(i, half, 192) * TAU, Vector3(at.x, 0.0, at.y)))
