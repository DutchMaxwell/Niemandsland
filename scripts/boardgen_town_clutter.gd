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
const LAMP_MODULES := ["lantern_post", "lantern_glow"]
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
	_flat(layout, out)
	_plots(layout, out)
	_ivy(layout, out)
	_landmarks(layout, out)
	_hall_and_towers(layout, out)
	_square_and_walls(layout, out)
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
				for m in FOUNTAIN_MODULES:
					_add(out, m, _item(0.0, Vector3(centre.x, 0.0, centre.y)))
			"Crane":
				for m in STATUE_MODULES:
					_add(out, m, _item(float(lm["turn"]) * PI * 0.5, Vector3(centre.x, 0.0 if m == "statue_plinth" else 1.57, centre.y)))
			"Sump":
				if lm["w"] >= 2 and lm["h"] >= 2:
					for ix in int(lm["w"]):   # north and south edges
						_add(out, "pool_kerb", _item(0.0, Vector3(lo.x + (ix + 0.5) * cell_in, 0.0, lo.y)))
						_add(out, "pool_kerb", _item(PI, Vector3(lo.x + (ix + 0.5) * cell_in, 0.0, lo.y + size.y)))
					for iz in int(lm["h"]):   # west and east edges
						_add(out, "pool_kerb", _item(PI * 0.5, Vector3(lo.x, 0.0, lo.y + (iz + 0.5) * cell_in)))
						_add(out, "pool_kerb", _item(-PI * 0.5, Vector3(lo.x + size.x, 0.0, lo.y + (iz + 0.5) * cell_in)))
				else:
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
## on each 2 x 2 tower a corner turret stub inside the 0.75 in corner square (a third of the towers carry a skeletal burnt cap on the crown instead). Every piece inside the strip or see-through.
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
		if BoardgenTownDressing._hash(i, half, 140) < 0.3:
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
