class_name BoardgenTownGrit
extends RefCounted
## Why the ground of the ruin town is dirty where it is (plan PLAN_RUINTOWN_GRIT, the GRIT MAP): the board's layout rasterised ONCE on the CPU into a small RGBA8 texture that the board
## shader (shaders/ruintown_grit.gdshaderinc) only looks up, so every dirt term has a cause - a wall, an earth border, a well - instead of a noise seed. Pure data, the rules never read it.
## TEXELS_PER_CELL texels per 3 in cell (0.19 in; ~14 ms per board: per-neighbour distance tables, not a
## per-texel search), texel centres symmetric about the board centre, so a half-turned layout gives the half-turned map for the data channels:
##   R = EDGE: on a street texel the distance to the nearest non-street cell, 0..3 in -> 0..1 (the shader's WEAR: the middle of a street is walked, the 1 in beside a wall is not); 0 off the street.
##   G = WET / MUD: 0..0.7, the mud creeping 1.5 in onto the setts from an earth border, the damp 1 in of earth beside a street, the damp halo 1.5 in round a well, pool or fountain;
##       0.75..1 = a PUDDLE (its edge at 0.775: 6-10 per board, see puddles()).
##   B = THE SECTION of a straight street (not a junction or square): the signed offset across it from its centre line, which wanders +-0.3 in along the run (the kennel of a lane lies on
##       it, the cart ruts of an artery 0.7 in either side of it): a lane 64 + 16 x offset (0..127), an ARTERY (a straight run of 10+ street cells) 192 + 16 x offset (128..255);
##       255 off a run. Not half-turn true on purpose (the look need not mirror).
##   A = DAMAGE 0..1: 2-4 seeded patches per half of the board (1-2.5 in across the cells beside a wall or a border, never in the middle of a street: the wear lane stays nearly
##       intact) and the two rut lines of every artery (0.3); the shader raises the odds of a missing, sunken or cracked sett with it.

const TEXELS_PER_CELL := 16
const MUD_REACH_IN := 1.5   # mud creeps this far onto the setts from an earth border
const DAMP_EARTH_IN := 1.0   # the earth is damp this far from a street
const HALO_IN := 1.5   # the damp ring round water
const EDGE_CAP_IN := 3.0
const ARTERY_CELLS := 10   # a straight street run this long carries carts: ruts, and its kennels lie beside the frontage
const WANDER_IN := 0.3
const RUT_IN := 0.7
## The odds of a sett's fate (shader uniforms grit_odds_*, grit_lane_keep): missing, sunken, cracked, repair = BASE + DAMAGE x the map's damage (+ 0.08 x wet for sunken), the missing and
## sunken odds kept at LANE_KEEP in the walked middle. Tuned with expected_shares() to the style bible: 4-8 / 10-15 / 6-10 / 3-5 %, >= half the missing ones in the patches.
const ODDS_BASE := Vector4(0.032, 0.125, 0.08, 0.04)
const ODDS_DAMAGE := Vector4(0.65, 0.35, 0.12, 0.0)
const LANE_KEEP := Vector2(0.35, 0.5)   # the cart ruts lie this far either side of an artery's centre line (1.4 in apart)
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


## Sets the map and the odds on the board's material.
static func apply(mat: ShaderMaterial, layout: Dictionary) -> void:
	mat.set_shader_parameter("grit_map", ImageTexture.create_from_image(map(layout)))
	mat.set_shader_parameter("grit_on", 1.0)
	mat.set_shader_parameter("grit_odds_base", ODDS_BASE)
	mat.set_shader_parameter("grit_odds_damage", ODDS_DAMAGE)
	mat.set_shader_parameter("grit_lane_keep", LANE_KEEP)


## The walked middle of a street (the shader's `lane`) at `edge_in` inches from its edge.
static func lane(edge_in: float) -> float:
	return smoothstep(0.55, 1.1, edge_in)


## What the shader will draw, from the map alone (every street texel weighs the same): the shares of missing / sunken / cracked / repair setts, the share of the missing ones inside a
## damage patch (damage > 0.3), and the missing + sunken odds of the walked middle (lane > 0.5) over those of the rest.
static func expected_shares(layout: Dictionary) -> Dictionary:
	var img := map(layout)
	var cls := classes(layout)
	var nx: int = layout["nx"]
	var tpc := TEXELS_PER_CELL
	var sum := Vector4.ZERO
	var n := 0
	var miss_patch := 0.0
	var mid := Vector2.ZERO   # (odds, texels)
	var side := Vector2.ZERO
	for z in img.get_height():
		for x in img.get_width():
			if cls[(z / tpc) * nx + x / tpc] != 1:
				continue
			var c := img.get_pixel(x, z)
			var ln := lane(c.r * EDGE_CAP_IN)
			var pm := (ODDS_BASE.x + ODDS_DAMAGE.x * c.a) * lerpf(1.0, LANE_KEEP.x, ln)
			var ps := (ODDS_BASE.y + ODDS_DAMAGE.y * c.a + 0.08 * minf(c.g, 0.7)) * lerpf(1.0, LANE_KEEP.y, ln)
			var o := Vector4(pm, ps, ODDS_BASE.z + ODDS_DAMAGE.z * c.a, ODDS_BASE.w + ODDS_DAMAGE.w * c.a)
			sum += o
			n += 1
			if c.a > 0.3:
				miss_patch += pm
			if ln > 0.5:
				mid += Vector2(pm + ps, 1.0)
			else:
				side += Vector2(pm + ps, 1.0)
	var share := sum / maxf(n, 1)
	return {"missing": share.x, "sunken": share.y, "cracked": share.z, "repair": share.w, "missing_in_patches": miss_patch / maxf(sum.x, 0.0001),
		"lane_ratio": (mid.x / maxf(mid.y, 1.0)) / maxf(side.x / maxf(side.y, 1.0), 0.0001)}


## The damage patches of a board: 2-4 per half, {at (board inches), r (inches)}, each on a street texel 0.3-1.2 in from the street's edge, 6 in or more apart. Deterministic per seed;
## the two halves draw their own (the look need not mirror).
static func patches(layout: Dictionary, cls: PackedByteArray) -> Array[Dictionary]:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var tables := _tables(cell, TEXELS_PER_CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout.get("seed", 0)) * 7919 + 31
	var out: Array[Dictionary] = []
	for half in 2:
		var cells: Array[int] = []
		for i in nx * nz:
			if cls[i] == 1 and ((i / nx) * 2 < nz) == (half == 0):
				cells.append(i)
		if cells.is_empty():
			continue
		var want := 2 + rng.randi_range(0, 2)
		var placed := 0
		for _try in 60:
			if placed >= want:
				break
			var i: int = cells[rng.randi_range(0, cells.size() - 1)]
			var t := rng.randi_range(0, TEXELS_PER_CELL * TEXELS_PER_CELL - 1)
			var edge: float = _near(cls, nx, nz, i % nx, i / nx, (1 << 0) | (1 << 2) | (1 << 3), EDGE_CAP_IN, tables)[t]
			if edge < 0.3 or edge > 1.2:
				continue
			var at := (Vector2(i % nx, i / nx) - Vector2(nx, nz) * 0.5) * cell + (Vector2(t % TEXELS_PER_CELL, t / TEXELS_PER_CELL) + Vector2(0.5, 0.5)) * (cell / TEXELS_PER_CELL)
			if out.any(func(p: Dictionary) -> bool: return (p["at"] as Vector2).distance_to(at) < 6.0):
				continue
			out.append({"at": at, "r": rng.randf_range(1.0, 2.5)})
			placed += 1
	return out


## The puddles of a board (style bible 8, plan G5): 6-10 {at (board inches), r (inches, 0.2-0.6: 0.4-1.2 across; at most 0.3 in the middle of a street)} where water gathers - in a damage
## patch, on a lane's kennel, in an artery's rut - never within 1.5 in of a dangerous cell (or the fountain), never on a ladder's foot cell, 3 in or more apart, wholly on the setts.
static func puddles(layout: Dictionary, cls: PackedByteArray) -> Array[Dictionary]:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var tpc := TEXELS_PER_CELL
	var tables := _tables(cell, tpc)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout.get("seed", 0)) * 6271 + 17
	var feet := {}
	for c: Dictionary in layout.get("connectors", []):
		feet[int(c["low"])] = true
		feet[int(c["high"])] = true
	var water: Array[Rect2] = []
	for i in nx * nz:
		if cls[i] == 3:
			water.append(Rect2((Vector2(i % nx, i / nx) - Vector2(nx, nz) * 0.5) * cell, Vector2(cell, cell)))
	var cands: Array[Vector2] = []
	for pt: Dictionary in patches(layout, cls):
		cands.append(pt["at"])
	var section := runs(layout, cls)
	var keys := section.keys()
	keys.sort()
	for k in 40:
		if keys.is_empty():
			break
		var i: int = keys[rng.randi_range(0, keys.size() - 1)]
		var r: Dictionary = section[i]
		var along := ((i % nx if r["axis"] == 0 else i / nx) - (nx if r["axis"] == 0 else nz) * 0.5 + rng.randf_range(0.15, 0.85)) * cell
		var across: float = float(r["centre"]) + wander(along, r["phase"]) + ((RUT_IN if rng.randf() < 0.5 else -RUT_IN) if r["artery"] else 0.0)
		cands.append(Vector2(along, across) if r["axis"] == 0 else Vector2(across, along))
	var out: Array[Dictionary] = []
	var want := 6 + rng.randi_range(0, 4)
	var order := range(cands.size())
	for k in order.size():   # a seeded shuffle
		var j := rng.randi_range(k, order.size() - 1)
		var t: int = order[k]
		order[k] = order[j]
		order[j] = t
	for k: int in order:
		if out.size() >= want:
			break
		var at: Vector2 = cands[k]
		var cx := floori(at.x / cell + nx * 0.5)
		var cz := floori(at.y / cell + nz * 0.5)
		if cx < 0 or cz < 0 or cx >= nx or cz >= nz or cls[cz * nx + cx] != 1 or feet.has(cz * nx + cx):
			continue
		var f := at - (Vector2(cx, cz) - Vector2(nx, nz) * 0.5) * cell
		var t := clampi(int(f.y / cell * tpc), 0, tpc - 1) * tpc + clampi(int(f.x / cell * tpc), 0, tpc - 1)
		var edge: float = _near(cls, nx, nz, cx, cz, (1 << 0) | (1 << 2) | (1 << 3), EDGE_CAP_IN, tables)[t]
		var rad := rng.randf_range(0.2, 0.6)
		if edge > 0.55:
			rad = minf(rad, 0.3)   # the middle of a street keeps its puddles small (style bible 15)
		if edge < rad + 0.1 or out.any(func(p: Dictionary) -> bool: return (p["at"] as Vector2).distance_to(at) < 3.0):
			continue
		var dry := true
		for wr: Rect2 in water:
			var q := Vector2(clampf(at.x, wr.position.x, wr.end.x), clampf(at.y, wr.position.y, wr.end.y))
			dry = dry and q.distance_to(at) >= 1.5 + rad
		if dry:
			out.append({"at": at, "r": rad})
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
						if run["artery"] and absf(absf(off) - RUT_IN) < 0.3:
							bytes[o + 3] = 77   # 0.3 along the ruts
					bytes[o + 1] = int(round(maxf((1.0 - halo[i] / HALO_IN) * 0.6, (1.0 - other[i] / reach) * 0.7) * 255.0))
					o += 4
	for pd: Dictionary in puddles(layout, cls):
		var at: Vector2 = pd["at"]
		var big: float = float(pd["r"]) / 0.9   # 0.775 (the shader's edge) at r
		var lo := ((at - Vector2(big, big)) / step + Vector2(w, h) * 0.5).floor()
		var hi := ((at + Vector2(big, big)) / step + Vector2(w, h) * 0.5).ceil()
		for tz in range(maxi(int(lo.y), 0), mini(int(hi.y), h)):
			for tx in range(maxi(int(lo.x), 0), mini(int(hi.x), w)):
				var d := ((Vector2(tx + 0.5, tz + 0.5) - Vector2(w, h) * 0.5) * step - at).length()
				if d < big:
					var o := (tz * w + tx) * 4 + 1
					bytes[o] = maxi(bytes[o], roundi(255.0 * (0.75 + 0.25 * (1.0 - d / big))))
	for pt: Dictionary in patches(layout, cls):
		var at: Vector2 = pt["at"]
		var r: float = pt["r"]
		var lo := ((at - Vector2(r, r)) / step + Vector2(w, h) * 0.5).floor()
		var hi := ((at + Vector2(r, r)) / step + Vector2(w, h) * 0.5).ceil()
		for tz in range(maxi(int(lo.y), 0), mini(int(hi.y), h)):
			for tx in range(maxi(int(lo.x), 0), mini(int(hi.x), w)):
				if cls[(tz / tpc) * nx + tx / tpc] != 1:
					continue
				var d := (Vector2(tx + 0.5, tz + 0.5) - Vector2(w, h) * 0.5) * step - at
				var mid := smoothstep(0.8, 1.5, bytes[(tz * w + tx) * 4] / 255.0 * EDGE_CAP_IN)   # a patch fades towards the walked middle
				var v := roundi(255.0 * (1.0 - smoothstep(r * 0.45, r, d.length())) * (1.0 - 0.75 * mid))
				var o := (tz * w + tx) * 4 + 3
				bytes[o] = maxi(bytes[o], v)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
