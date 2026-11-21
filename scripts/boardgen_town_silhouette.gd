class_name BoardgenTownSilhouette
extends RefCounted
## The town's silhouette from the overview and play cameras (maintainer 21.11.: "still too blocky from above"). LOOK ONLY: no piece here is a collider, no cell changes class,
## every walkable top stays flat and exact at its 3 / 6 / 9 in and keeps its middle free. Pure plans (board inches, origin at the board centre) and one builder.
##   - wall_parts: a raised city-wall or tower cell is drawn thinner - a full-width foot, a stepped batter, the face pulled in by at most REACH_IN on every open face, and a full-width
##     corbelled course under the walk (the walk itself is the cell, exact). The cell's own greybox box keeps the collider and draws nothing.
##   - ruin_gables: the end faces of a ruined, walkable house (Block / Deck) carry a broken crow-stepped gable end in the 0.3 in edge strip, so a tier reads as a roofless house.
##   - rafters: the long faces of those houses carry charred rafter stubs leaning in from a wall plate, inside the 0.75 in edge strip.
##   - turrets: some intact (solid, never walkable) houses get a round stair turret with a conical roof on one corner, inside the house's own cells.

const REACH_IN := 0.2   # the drawn face may sit at most this far inside the collider's face (plan O3: a model touching the collider still touches the wall)
const FOOT_IN := 0.45
const BATTER_IN := 0.9
const CORBEL_IN := 0.5
const GABLE_T_IN := 0.3
const GABLE_PEAK_IN := Vector2(1.4, 2.6)   # (train 3, lead: the skyline of a town that lost its roofs) was 1.0-1.9; non-walkable, in the strip, below the 9 in tower crown
const STRIP_IN := 0.75
const LADDER_GAP_IN := 0.9   # half the gap kept free round a ladder's top
const RAFTER_IN := Vector2(0.13, 0.78)   # section, length
const RAFTER_PITCH := deg_to_rad(38.0)
const TURRET_SHARE := 0.4
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W


static func _h(a: int, half: int, salt: int) -> float:
	return BoardgenTownDressing._hash(a, half, salt)


static func _level(layout: Dictionary, x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= int(layout["nx"]) or z >= int(layout["nz"]):
		return -1
	return int(layout["cells"][z * int(layout["nx"]) + x]["level"])


static func _is_tower(layout: Dictionary, x: int, z: int) -> bool:
	return _level(layout, x, z) >= 0 and layout["cells"][z * int(layout["nx"]) + x]["lot_kind"] == "Tower"


## {cell index: [side, ...]}: the sides (index into DIRS) of every cell where a ladder arrives at its top.
static func _ladder_tops(layout: Dictionary) -> Dictionary:
	var out := {}
	for c: Dictionary in layout["connectors"]:
		var d := Vector2i(c["low_xz"][0], c["low_xz"][1]) - Vector2i(c["high_xz"][0], c["high_xz"][1])
		(out.get_or_add(int(c["high"]), []) as Array).append(DIRS.find(d))
	return out


## {cell index: true} under a hall (a PumpHouse landmark): its top has its own columns and fallen pediment, no gable and no rafter.
static func _hall_cells(layout: Dictionary) -> Dictionary:
	var out := {}
	for lm: Dictionary in layout["landmarks"]:
		if lm["kind"] == "PumpHouse":
			for dz in int(lm["h"]):
				for dx in int(lm["w"]):
					out[(int(lm["z"]) + dz) * int(layout["nx"]) + int(lm["x"]) + dx] = true
	return out


## The cells wall_parts draws: every raised city-wall cell (the 3 in low wall of the bands and the buttress too), every 9 in tower cell and every tall scenery tower cell (lot kind "Tower", towers plan L1).
## The greybox draws none of these itself (it keeps their colliders).
static func drawn_cells(layout: Dictionary) -> Dictionary:
	var out := {}
	for cd: Dictionary in layout["cells"]:
		if int(cd["level"]) >= 3 or (int(cd["level"]) >= 1 and cd["lot_kind"] == "Wall") or cd["lot_kind"] == "Tower":
			out[int(cd["z"]) * int(layout["nx"]) + int(cd["x"])] = true
	return out


## The drawn pieces of the wall and tower cells: [{lo, hi (Vector3, inches), kind, cell}]. Foot and corbel course fill the cell; the batter is pulled in by half, the body by REACH_IN, on
## each OPEN face only (a lower neighbour or the board edge), never on a face a ladder leans on.
static func wall_parts(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, int(layout["nz"])) * cell_in * -0.5
	var ladders := _ladder_tops(layout)
	for i: int in drawn_cells(layout):
		var cd: Dictionary = layout["cells"][i]
		var level: int = cd["level"]
		var tall: bool = cd["lot_kind"] == "Tower"   # a tall scenery tower: level 0 in the layout, `tower_in` high to the core; a face is open where the neighbour is no tower cell
		var top: float = float(layout.get("tower_in", 12.0)) if tall else float(layout["level_in"][level])
		var kind := "wall" if cd["lot_kind"] == "Wall" else "tier3"
		var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
		var inset := [0.0, 0.0, 0.0, 0.0]
		for side in 4:
			var d := DIRS[side]
			var open := not _is_tower(layout, cd["x"] + d.x, cd["z"] + d.y) if tall else _level(layout, cd["x"] + d.x, cd["z"] + d.y) < level
			if open and not (ladders.get(i, []) as Array).has(side):
				inset[side] = REACH_IN
		var cut := func(f: float, y0: float, y1: float) -> Dictionary:
			return {"lo": Vector3(lo.x + inset[3] * f, y0, lo.y + inset[0] * f), "hi": Vector3(lo.x + cell_in - inset[1] * f, y1, lo.y + cell_in - inset[2] * f), "kind": kind, "cell": i}
		out.append_array([cut.call(0.0, 0.0, FOOT_IN), cut.call(0.5, FOOT_IN, BATTER_IN), cut.call(1.0, BATTER_IN, top - CORBEL_IN), cut.call(0.0, top - CORBEL_IN, top)])
	return out


## Broken crow-stepped gable ends on the END faces (across the lot's long axis) of every ruined, walkable house lot (Block / Deck) whose end column is one level and drops on its whole
## face: masonry 0.3 in thick, flush inside the face, 3-5 steps from each corner up to a 1.4-2.6 in peak (GABLE_PEAK_IN), one side broken off at a step the lot's hash picks; a gable that lost its
## middle keeps only its two corner stubs. Nothing within LADDER_GAP_IN of a ladder's top. [{lo, hi, kind, lot}]
## `timber` (train 3, H4): lots whose ladder-free gable faces carry the kit's timber gable instead (no masonry there); `faces` collects every gable face found
## ({lot, side, mid (Vector2, the face's outer middle), width, top, peak, free (no ladder top on it)}).
static func ruin_gables(layout: Dictionary, timber: Dictionary = {}, faces: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var tiers := BoardgenTownDressing.tier_parts(layout)
	var ladders := _ladder_tops(layout)
	var halls := _hall_cells(layout)
	for lot: Dictionary in layout["lots"]:
		if not tiers["axis_x"].has(lot["id"]) or tiers["cells"].keys().any(func(i: int) -> bool: return halls.has(i) and int(layout["cells"][i]["lot_id"]) == int(lot["id"])):
			continue
		var axis_x: bool = tiers["axis_x"][lot["id"]]
		var half := 1 if int(lot["z"]) * 2 >= nz else 0
		for end in 2:   # the low end, the high end along the axis
			var side := (3 if end == 0 else 1) if axis_x else (0 if end == 0 else 2)
			var d := DIRS[side]
			var span: int = lot["h"] if axis_x else lot["w"]
			var face: Array[int] = []
			for k in span:
				var x: int = int(lot["x"]) + (0 if end == 0 else int(lot["w"]) - 1) if axis_x else int(lot["x"]) + k
				var z: int = int(lot["z"]) + k if axis_x else int(lot["z"]) + (0 if end == 0 else int(lot["h"]) - 1)
				face.append(z * nx + x)
			var level: int = layout["cells"][face[0]]["level"]
			var ok := level >= 1 and level < 3   # (towers plan T2 sweep: a gable on a 9 in top would rise into the tower crown)
			for i in face:
				var cd: Dictionary = layout["cells"][i]
				ok = ok and int(cd["level"]) == level and _level(layout, int(cd["x"]) + d.x, int(cd["z"]) + d.y) < level
			if not ok:
				continue
			var top: float = layout["level_in"][level]
			var width := float(span) * cell_in
			var c0 := origin + Vector2(layout["cells"][face[0]]["x"], layout["cells"][face[0]]["z"]) * cell_in   # the low corner of the face's first cell
			var plane := c0 + (Vector2(cell_in - GABLE_T_IN, 0.0) if side == 1 else Vector2(0.0, cell_in - GABLE_T_IN) if side == 2 else Vector2.ZERO)
			var salt := int(lot["id"]) * 4 + end
			var steps := 3 + int(_h(salt, half, 200) * 3.0)
			var peak := GABLE_PEAK_IN.x + (GABLE_PEAK_IN.y - GABLE_PEAK_IN.x) * _h(salt, half, 201)
			var broken_at := int(_h(salt, half, 202) * float(2 * steps))   # the step from which on one side is gone
			var stubs_only := _h(salt, half, 203) < 0.3
			var gaps: Array[float] = []   # along the face: ladder tops
			for k in span:
				if (ladders.get(face[k], []) as Array).has(side):
					gaps.append((float(k) + 0.5) * cell_in)
			var outer := c0 + (Vector2(cell_in, 0.0) if side == 1 else Vector2(0.0, cell_in) if side == 2 else Vector2.ZERO)
			faces.append({"lot": lot["id"], "side": side, "mid": outer + (Vector2(0.0, width * 0.5) if axis_x else Vector2(width * 0.5, 0.0)), "width": width, "top": top, "peak": peak, "free": gaps.is_empty()})
			if timber.has(lot["id"]) and gaps.is_empty():
				continue
			var w := width * 0.5 / float(steps)
			for s in 2 * steps:   # left to right: rising, then falling
				var rank := s if s < steps else 2 * steps - 1 - s
				if s >= broken_at and broken_at >= steps / 2 and s > rank or (stubs_only and rank > 0):
					continue
				var a := float(s) * w
				if gaps.any(func(g: float) -> bool: return a < g + LADDER_GAP_IN and a + w > g - LADDER_GAP_IN):
					continue
				var hgt := peak * float(rank + 1) / float(steps) * (0.75 + 0.25 * _h(salt * 16 + s, half, 204))
				var lo := plane + (Vector2(0.0, a) if axis_x else Vector2(a, 0.0))
				var hi := lo + (Vector2(GABLE_T_IN, w) if axis_x else Vector2(w, GABLE_T_IN))
				out.append({"lo": Vector3(lo.x, top, lo.y), "hi": Vector3(hi.x, top + hgt, hi.y), "kind": "wall", "lot": lot["id"]})
	return out


## Charred rafter stubs on the LONG faces of the same houses (open drop, one level): a wall plate along the edge and rafters every 0.8 in leaning inward at 38 degrees, a third of them
## gone; a rafter's top stays inside the 0.75 in strip. None within LADDER_GAP_IN of a ladder's top. [{centre (Vector3), size (Vector3: section, section, length), yaw, pitch, kind}]
static func rafters(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var tiers := BoardgenTownDressing.tier_parts(layout)
	var ladders := _ladder_tops(layout)
	var halls := _hall_cells(layout)
	for i: int in tiers["cells"]:
		var cd: Dictionary = layout["cells"][i]
		var level: int = cd["level"]
		if level < 1 or halls.has(i):
			continue
		var axis_x: bool = tiers["axis_x"][int(cd["lot_id"])]
		var half := 1 if int(cd["z"]) * 2 >= nz else 0
		for side: int in ([0, 2] if axis_x else [1, 3]):
			var d := DIRS[side]
			if _level(layout, int(cd["x"]) + d.x, int(cd["z"]) + d.y) >= level or (ladders.get(i, []) as Array).has(side) or _h(i, half, 210 + side) < 0.35:
				continue
			var top: float = layout["level_in"][level]
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var edge := lo + Vector2(cell_in * 0.5, 0.0 if side == 0 else cell_in) if axis_x else lo + Vector2(0.0 if side == 3 else cell_in, cell_in * 0.5)
			var inward := -Vector2(d)
			var along := Vector2(1, 0) if axis_x else Vector2(0, 1)
			var yaw := atan2(inward.x, inward.y)   # the box's local +z points inward
			out.append({"centre": Vector3(edge.x + inward.x * 0.1, top + 0.08, edge.y + inward.y * 0.1), "size": Vector3(0.16, 0.16, cell_in - 0.1), "yaw": yaw + PI * 0.5, "pitch": 0.0, "kind": "wood"})
			for k in 3:
				if _h(i * 4 + k, half, 220 + side) < 0.33:
					continue
				var t := (float(k) - 1.0) * 0.8 + (_h(i * 4 + k, half, 230) - 0.5) * 0.2
				var length := RAFTER_IN.y * (0.6 + 0.4 * _h(i * 4 + k, half, 240))
				var foot := edge + along * t + inward * 0.12
				var mid := foot + inward * cos(RAFTER_PITCH) * length * 0.5
				out.append({"centre": Vector3(mid.x, top + 0.16 + sin(RAFTER_PITCH) * length * 0.5, mid.y), "size": Vector3(RAFTER_IN.x, RAFTER_IN.x, length), "yaw": yaw, "pitch": RAFTER_PITCH, "kind": "wood"})
	return out


## Round stair turrets on some intact houses (solid, nobody stands on them): on a corner of the drawn body, inside it by the radius, as high as the eaves plus 0.9-1.8 in, under a
## cone 1.6-2.3 in high. [{centre (Vector2), radius, top, cone}]
static func turrets(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in BoardgenTownDressing.house_bodies(layout):
		var size: Vector2 = b["size"]
		if maxf(size.x, size.y) < 5.0 or _h(b["lot"], b["half"], 250) >= TURRET_SHARE:
			continue
		var r := 0.55 + 0.15 * _h(b["lot"], b["half"], 251)
		var corner := int(_h(b["lot"], b["half"], 252) * 4.0) % 4
		var local := Vector2((size.x * 0.5 - r) * (1.0 if corner in [1, 2] else -1.0), (size.y * 0.5 - r) * (1.0 if corner >= 2 else -1.0))
		out.append({"centre": b["centre"] + local.rotated(-float(b["yaw"])), "radius": r, "top": float(b["top"]) + 0.9 + 0.9 * _h(b["lot"], b["half"], 253),
			"cone": 1.6 + 0.7 * _h(b["lot"], b["half"], 254), "lot": b["lot"]})
	return out


## All of it on the board's material: the boxes in one MultiMesh, the turret shafts and their cones in one each.
static func build(parent: Node3D, layout: Dictionary, material: Material, timber: Dictionary = {}) -> void:
	var m := BoardgenTownDressing.INCHES_TO_METERS
	var kinds: Array = BoardgenTheme.TOWN_KINDS
	var items: Array = []   # [basis, origin, custom]
	for b: Dictionary in wall_parts(layout) + ruin_gables(layout, timber):
		var size: Vector3 = b["hi"] - b["lo"]
		items.append([Basis.from_scale(size * m), (b["lo"] + b["hi"]) * 0.5 * m, Color(kinds.find(b["kind"]), size.x, size.y, size.z)])
	for r: Dictionary in rafters(layout):
		var size: Vector3 = r["size"]
		var basis := Basis(Vector3.UP, r["yaw"]) * Basis(Vector3.RIGHT, -float(r["pitch"])) * Basis.from_scale(size * m)
		items.append([basis, r["centre"] * m, Color(kinds.find(r["kind"]), size.x, size.y, size.z)])
	_multimesh(parent, "Silhouette", BoxMesh.new(), items, material)
	var shafts: Array = []
	var cones: Array = []
	for t: Dictionary in turrets(layout):
		var c: Vector2 = t["centre"]
		var d := 2.0 * float(t["radius"])
		shafts.append([Basis.from_scale(Vector3(d, t["top"], d) * m), Vector3(c.x, float(t["top"]) * 0.5, c.y) * m, Color(kinds.find("wall"), d, t["top"], d)])
		cones.append([Basis.from_scale(Vector3(d + 0.3, t["cone"], d + 0.3) * m), Vector3(c.x, float(t["top"]) + float(t["cone"]) * 0.5, c.y) * m, Color(kinds.find("roof"), d + 0.3, t["cone"], d + 0.3)])
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.5
	shaft.bottom_radius = 0.5
	shaft.height = 1.0
	shaft.radial_segments = 12
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 12
	cone.cap_bottom = true
	_multimesh(parent, "Turrets", shaft, shafts, material)
	_multimesh(parent, "TurretRoofs", cone, cones, material)


static func _multimesh(parent: Node3D, name: String, mesh: Mesh, items: Array, material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, Transform3D(items[i][0], items[i][1]))
		mm.set_instance_custom_data(i, items[i][2])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)
