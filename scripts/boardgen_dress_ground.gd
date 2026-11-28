class_name BoardgenDressGround
extends RefCounted
## The ground data of one ruin-town board (PLAN_RUINTOWN_DRESSING, step 25): `tops` is the one-texel-per-cell class and height map, `mask` the 8 px/in weight map the ground
## shader reads (cobble / flag / green / wet), and `puddles` the seeded street puddles. Pure data: no node, no mesh, no collider. Positions are board inches, origin at the centre.
## The generator's layout stays the gameplay truth; this file only names what the dressing draws over it. Class borders in `tops` are exact (R8) - it is never blurred.

const CLASS_NONE := 255
const PX_PER_IN := 8


## One texel per cell, 16 x 16 RGBA8: R top class (0 earth, 1 cobbles, 2 yard_flags, 3 deck_flags, 4 deck_boards, 5 walk_flags, 6 rubble, 7 plot, 8 water, 255 none),
## G top height in inches x 20, B the lot hash, A 255 at a ladder foot. Exact, never resized: the class edge is a rules edge.
static func tops(layout: Dictionary) -> Image:
	var nx: int = layout["nx"]; var nz: int = layout["nz"]
	var f := _flags(layout)
	var img := Image.create(nx, nz, false, Image.FORMAT_RGBA8)
	for z in nz:
		for x in nx:
			var i: int = z * nx + x
			var c: Dictionary = layout["cells"][i]
			var inches := 2.5 if String(c["lot_kind"]) == "Roofed" else (float(layout.get("tower_in", 12.0)) if String(c["lot_kind"]) == "Tower" else float(layout["level_in"][int(c["level"])]))
			img.set_pixel(x, z, Color8(_class(c, i, f), clampi(roundi(inches * 20.0), 0, 255), BoardgenDressStory.pick(int(c["lot_id"]), 0, 256), 255 if f["feet"].has(i) else 0))
	return img


## 384 x 384 RGBA8 (8 px / in): R cobble weight, G flag weight, B green zone (0.8 in round raised / solid cells and outside the town wall), A wet (puddles and cart ruts).
## Painted per cell and blurred by 0.5 in (a down/up resize), so the shader's noise can break the cobble / earth border; never pixel loops over the whole map.
static func mask(layout: Dictionary) -> Image:
	var nx: int = layout["nx"]; var nz: int = layout["nz"]; var cell := float(layout["cell_in"]); var size := roundi(float(layout["board_in"][0]) * PX_PER_IN)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var f := _flags(layout)
	for z in nz:
		for x in nx:
			var i: int = z * nx + x
			var c: Dictionary = layout["cells"][i]
			var cls := _class(c, i, f)
			var rect := _rect(x, z, cell, size)
			img.fill_rect(rect, Color(1, 0, 0, 0) if cls == 1 else (Color(0, 1, 0, 0) if cls == 2 or cls == 3 or cls == 5 else Color(0, 0, 0, 0)))
			if int(c["level"]) >= 1 or cls == CLASS_NONE or f["solid"].has(i):
				img.fill_rect(rect.grow(roundi(0.8 * PX_PER_IN)).intersection(Rect2i(0, 0, size, size)), Color(0, 0, 1, 0))
	for i in _outside_wall(layout):
		img.fill_rect(_rect(int(layout["cells"][i]["x"]), int(layout["cells"][i]["z"]), cell, size), Color(0, 0, 1, 0))
	_cart_ruts(layout, img, cell, size)
	for p: Dictionary in puddles(layout):
		_paint_disc(img, p["centre"], float(p["radius"]), size)
	var down := maxi(1, size / 4)
	img.resize(down, down, Image.INTERPOLATE_CUBIC); img.resize(size, size, Image.INTERPOLATE_CUBIC)
	return img


## 6 to 10 seeded puddles on street cells, each {centre: Vector2 (inches), radius: float (inches)}, every centre >= 1.5 in from a water cell and off a ladder foot.
## Every choice comes from the layout's own seed, so the same layout always gives the same list.
static func puddles(layout: Dictionary) -> Array:
	var nx: int = layout["nx"]; var nz: int = layout["nz"]; var cell := float(layout["cell_in"]); var half := Vector2(nx, nz) * cell * 0.5
	var f := _flags(layout)
	var cand: Array[int] = []
	for z in nz:
		for x in nx:
			var i: int = z * nx + x
			var c: Dictionary = layout["cells"][i]
			if c["street"] and int(c["level"]) == 0 and not f["feet"].has(i) and _water_dist(layout, (Vector2(x, z) + Vector2(0.5, 0.5) - half) * cell, f["water"]) >= 1.501:
				cand.append(i)
	var seed := int(layout["seed"]); var used := {}; var out: Array = []
	for k: int in mini(6 + BoardgenDressStory.pick(seed, 0x9E, 5), cand.size()):
		var at := BoardgenDressStory.pick(seed, 0x100 + k, cand.size())
		while used.has(at):
			at = (at + 1) % cand.size()
		used[at] = true
		out.append({"centre": (Vector2(int(layout["cells"][cand[at]]["x"]), int(layout["cells"][cand[at]]["z"])) + Vector2(0.5, 0.5) - half) * cell, "radius": 0.5 + 0.9 * float(BoardgenDressStory.pick(cand[at], 0x2B, 100)) / 99.0})
	return out


static func _class(c: Dictionary, i: int, f: Dictionary) -> int:
	var kind := String(c["lot_kind"])
	var lvl := int(c["level"])
	if kind == "Roofed" or kind == "Tower": return CLASS_NONE
	if f["water"].has(i) and lvl == 0: return 8
	if kind == "Wall": return 6 if lvl == 0 else 5
	if lvl >= 1: return 4 if kind == "Deck" else 3
	if kind == "Rough": return 7
	if kind == "Terrace" and not c["street"]: return 2
	if f["solid"].has(i): return 2
	return 1 if c["street"] else 0


## Water cells (Hazard at level 0; every Sump footprint is claimed as Hazard), solid landmark footprints and the ladder foot cells, as index sets.
static func _flags(layout: Dictionary) -> Dictionary:
	var out := {"water": {}, "solid": {}, "feet": {}}
	var nx: int = layout["nx"]
	for i in layout["cells"].size():
		var c: Dictionary = layout["cells"][i]
		if String(c["lot_kind"]) == "Hazard" and int(c["level"]) == 0: out["water"][i] = true
	for conn: Dictionary in layout["connectors"]:
		out["feet"][int(conn["low_xz"][1]) * nx + int(conn["low_xz"][0])] = true
	for lm: Dictionary in layout.get("landmarks", []):
		if lm.get("solid", false):
			for dz in int(lm["h"]):
				for dx in int(lm["w"]):
					out["solid"][(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	return out


## Cells beyond the town wall on either side: per row, west of the westmost Wall cell or east of the eastmost one. A row without a wall (a gate) is all inside.
static func _outside_wall(layout: Dictionary) -> Array[int]:
	var nx: int = layout["nx"]
	var out: Array[int] = []
	for z in layout["nz"]:
		var lo := nx; var hi := -1
		for x in nx:
			if String(layout["cells"][z * nx + x]["lot_kind"]) == "Wall":
				lo = mini(lo, x); hi = maxi(hi, x)
		if hi < 0: continue
		for x in nx:
			if x < lo or x > hi:
				out.append(z * nx + x)
	return out


static func _water_dist(layout: Dictionary, p: Vector2, water: Dictionary) -> float:
	var nx: int = layout["nx"]; var cell := float(layout["cell_in"]); var half := Vector2(nx, int(layout["nz"])) * cell * 0.5
	var best := INF
	for i: int in water:
		var r := Rect2((Vector2(i % nx, i / nx) - half) * cell, Vector2(cell, cell))
		best = minf(best, p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))))
	return best


static func _rect(x: int, z: int, cell: float, size: int) -> Rect2i:
	return Rect2i(Vector2i(roundi(x * cell * PX_PER_IN), roundi(z * cell * PX_PER_IN)), Vector2i(roundi(cell * PX_PER_IN), roundi(cell * PX_PER_IN))).intersection(Rect2i(0, 0, size, size))


## A thin wet strip through the middle of every street cell that has a street neighbour across it (a cart rut along the run).
static func _cart_ruts(layout: Dictionary, img: Image, cell: float, size: int) -> void:
	var nx: int = layout["nx"]; var nz: int = layout["nz"]
	for z in nz:
		for x in nx:
			var c: Dictionary = layout["cells"][z * nx + x]
			if not c["street"] or int(c["level"]) != 0: continue
			var across: bool = x > 0 and x + 1 < nx and layout["cells"][z * nx + x - 1]["street"] and layout["cells"][z * nx + x + 1]["street"]
			var down: bool = z > 0 and z + 1 < nz and layout["cells"][(z - 1) * nx + x]["street"] and layout["cells"][(z + 1) * nx + x]["street"]
			if across or down:
				var r := _rect(x, z, cell, size); var w := roundi(0.4 * PX_PER_IN); var mid := Vector2i(r.get_center())
				img.fill_rect(Rect2i(mid.x - r.size.x / 2, mid.y - w / 2, r.size.x, w) if across else Rect2i(mid.x - w / 2, mid.y - r.size.y / 2, w, r.size.y), Color(1, 0, 0, 1))


## A wet disc that keeps the cell's other weights (R / G / B) and only raises alpha.
static func _paint_disc(img: Image, centre: Vector2, radius: float, size: int) -> void:
	var c := Vector2(centre.x + float(size) * 0.5, centre.y + float(size) * 0.5) * PX_PER_IN; var r := radius * PX_PER_IN
	for yy in range(maxi(0, floori(c.y - r)), mini(size - 1, ceili(c.y + r)) + 1):
		for xx in range(maxi(0, floori(c.x - r)), mini(size - 1, ceili(c.x + r)) + 1):
			if Vector2(xx + 0.5, yy + 0.5).distance_to(c) <= r:
				var col := img.get_pixel(xx, yy)
				img.set_pixel(xx, yy, Color(col.r, col.g, col.b, 1.0))
