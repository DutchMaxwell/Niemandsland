class_name BoardgenTownGrit
extends RefCounted
## Why the ground of the ruin town is dirty where it is (plan PLAN_RUINTOWN_GRIT, the GRIT MAP): the board's layout rasterised ONCE on the CPU into a small RGBA8 texture that the board
## shader (shaders/ruintown_grit.gdshaderinc) only looks up, so every dirt term has a cause - a wall, an earth border, a well - instead of a noise seed. Pure data, the rules never read it.
## TEXELS_PER_CELL texels per 3 in cell (0.19 in; ~14 ms per board: per-neighbour distance tables, not a
## per-texel search), texel centres symmetric about the board centre, so a half-turned layout gives the half-turned map for the data channels:
##   R = EDGE: on a street texel the distance to the nearest non-street cell, 0..3 in -> 0..1 (the shader's WEAR: the middle of a street is walked, the 1 in beside a wall is not); 0 off the street.
##   G = WET / MUD: 0..0.7, the mud creeping 1.5 in onto the setts from an earth border, the damp 1 in of earth beside a street, the damp halo 1.5 in round a well, pool or fountain.
##   B = THE SECTION of a straight street (not a junction or square): the signed offset across it from its centre line, which wanders +-0.3 in along the run (the kennel of a lane lies on
##       it, the cart ruts of an artery 0.7 in either side of it): a lane 64 + 16 x offset (0..127), an ARTERY (a straight run of 10+ street cells) 192 + 16 x offset (128..255);
##       255 off a run. Not half-turn true on purpose (the look need not mirror).
##   A = reserved for the damage patches (G4), 0 = none.

const TEXELS_PER_CELL := 16
const MUD_REACH_IN := 1.5   # mud creeps this far onto the setts from an earth border
const DAMP_EARTH_IN := 1.0   # the earth is damp this far from a street
const HALO_IN := 1.5   # the damp ring round water
const EDGE_CAP_IN := 3.0
const ARTERY_CELLS := 10   # a straight street run this long carries carts: ruts, and its kennels lie beside the frontage
const WANDER_IN := 0.3
const NEIGHBOURS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


## The cell classes the map is built from: 0 other, 1 open street, 2 earth, 3 water (a dangerous pool / well, or the fountain's footprint).
static func classes(layout: Dictionary) -> PackedByteArray:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var out := PackedByteArray()
	out.resize(nx * nz)
	for i in nx * nz:
		var cd: Dictionary = layout["cells"][i]
		var kind := BoardgenGreybox._cell_kind(cd, true)
		out[i] = 1 if kind == "street" else (2 if kind == "ground" else (3 if kind == "hazard" else 0))
	for lm: Dictionary in layout.get("landmarks", []):
		if lm["kind"] == "TankCluster":
			for dz in int(lm["h"]):
				for dx in int(lm["w"]):
					out[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = 3
	return out


## The straight streets: per run cell (index) {axis (0 along x, 1 along z), centre (board inches across), artery, phase}. A cell is on a run when its street reaches 3+ cells one way and
## at most 2 the other (BoardgenGreybox.ground_map's rule); its centre line is the middle of the street band across it.
static func runs(layout: Dictionary, cls: PackedByteArray) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var street := func(x: int, z: int) -> bool: return x >= 0 and z >= 0 and x < nx and z < nz and cls[z * nx + x] == 1
	var reach := func(x: int, z: int, dx: int, dz: int) -> int:
		var n := 0
		while street.call(x + (n + 1) * dx, z + (n + 1) * dz):
			n += 1
		return n
	var out := {}
	for i in nx * nz:
		var x := i % nx
		var z := i / nx
		if not street.call(x, z):
			continue
		var h: int = 1 + reach.call(x, z, 1, 0) + reach.call(x, z, -1, 0)
		var v: int = 1 + reach.call(x, z, 0, 1) + reach.call(x, z, 0, -1)
		if not ((h >= 3 and v <= 2) or (v >= 3 and h <= 2)):
			continue
		var axis := 0 if h >= 3 else 1
		var lo: int = (z - reach.call(x, z, 0, -1)) if axis == 0 else (x - reach.call(x, z, -1, 0))
		var hi: int = (z + reach.call(x, z, 0, 1)) if axis == 0 else (x + reach.call(x, z, 1, 0))
		var centre := (float(lo + hi + 1) * 0.5 - float(nz if axis == 0 else nx) * 0.5) * cell
		out[i] = {"axis": axis, "centre": centre, "artery": (h if axis == 0 else v) >= ARTERY_CELLS, "phase": BoardgenTownDressing._hash(int(round(centre * 8.0)) + 4096 * axis, int(layout.get("seed", 0)) & 1023, 300) * TAU}
	return out


## The wander of a run's centre line at `along` inches (+-WANDER_IN, two slow waves).
static func wander(along: float, phase: float) -> float:
	return WANDER_IN * (0.8 * sin(along * 0.31 + phase) + 0.2 * sin(along * 0.77 + phase * 2.3))


## The distance (inches) from every texel of the cell (cx, cz) to the nearest of its 8 neighbour cells whose class bit is in `want` (bit 1 << class), capped at `cap`; `tables` are the
## per-neighbour distance tables of a cell's texels (_tables). A neighbour off the board never counts (a street that runs off the edge has no kerb there).
static func _near(cls: PackedByteArray, nx: int, nz: int, cx: int, cz: int, want: int, cap: float, tables: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n: int = (tables[0] as PackedFloat32Array).size()
	out.resize(n)
	out.fill(cap)
	for k in 8:
		var d: Vector2i = NEIGHBOURS[k]
		var x := cx + d.x
		var z := cz + d.y
		if x < 0 or z < 0 or x >= nx or z >= nz or (want >> cls[z * nx + x]) & 1 == 0:
			continue
		var t: PackedFloat32Array = tables[k]
		for i in n:
			if t[i] < out[i]:
				out[i] = t[i]
	return out


## Per neighbour direction, the distance of every texel centre of a cell (row by row) to that neighbour cell.
static func _tables(cell: float, tpc: int) -> Array:
	var out: Array = []
	var step := cell / tpc
	for d: Vector2i in NEIGHBOURS:
		var t := PackedFloat32Array()
		t.resize(tpc * tpc)
		for tz in tpc:
			for tx in tpc:
				var fx := (tx + 0.5) * step
				var fz := (tz + 0.5) * step
				var ex := fx if d.x < 0 else (cell - fx if d.x > 0 else 0.0)
				var ez := fz if d.y < 0 else (cell - fz if d.y > 0 else 0.0)
				t[tz * tpc + tx] = sqrt(ex * ex + ez * ez)
		out.append(t)
	return out


## The grit map of a town layout (see the header): Image RGBA8, (nx x nz) * TEXELS_PER_CELL.
static func map(layout: Dictionary) -> Image:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var tpc := TEXELS_PER_CELL
	var w := nx * tpc
	var h := nz * tpc
	var cls := classes(layout)
	var tables := _tables(cell, tpc)
	var section := runs(layout, cls)
	var step := cell / tpc
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for i in w * h:
		bytes[i * 4 + 2] = 255
	for cz in nz:
		for cx in nx:
			var c := cls[cz * nx + cx]
			if c != 1 and c != 2:
				continue
			var halo := _near(cls, nx, nz, cx, cz, 1 << 3, HALO_IN, tables)
			var edge := _near(cls, nx, nz, cx, cz, (1 << 0) | (1 << 2) | (1 << 3), EDGE_CAP_IN, tables) if c == 1 else PackedFloat32Array()
			var other := _near(cls, nx, nz, cx, cz, 1 << (2 if c == 1 else 1), MUD_REACH_IN if c == 1 else DAMP_EARTH_IN, tables)
			var reach := MUD_REACH_IN if c == 1 else DAMP_EARTH_IN
			var run: Dictionary = section.get(cz * nx + cx, {})
			for tz in tpc:
				var o := ((cz * tpc + tz) * w + cx * tpc) * 4
				for tx in tpc:
					var i := tz * tpc + tx
					if c == 1:
						bytes[o] = int(round(edge[i] / EDGE_CAP_IN * 255.0))
					if not run.is_empty():
						var px := (cx * tpc + tx + 0.5) * step - nx * cell * 0.5
						var pz := (cz * tpc + tz + 0.5) * step - nz * cell * 0.5
						var off: float = (pz if run["axis"] == 0 else px) - float(run["centre"]) - wander(px if run["axis"] == 0 else pz, run["phase"])
						bytes[o + 2] = clampi(roundi((192.0 if run["artery"] else 64.0) + 16.0 * off), 128 if run["artery"] else 0, 255 if run["artery"] else 127)
					bytes[o + 1] = int(round(maxf((1.0 - halo[i] / HALO_IN) * 0.6, (1.0 - other[i] / reach) * 0.7) * 255.0))
					o += 4
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
