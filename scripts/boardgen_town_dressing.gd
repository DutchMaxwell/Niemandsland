class_name BoardgenTownDressing
extends Node3D
## The look pieces of a ruin-town board that are not a flat box of the greybox plan: the tiled GABLE roofs of the intact (Roofed) houses
## (a prism mesh each, one MultiMesh), their brick chimneys (boxes in the greybox plan) and, later, the battlements of the wall. VISUAL ONLY: an
## intact house is the core's 2.5 in solid (CONTAINER) whatever the roof above it is, and nobody stands on a roof (no collider). The two
## halves of the board vary the pitch and the chimney end by a hash of the lot and its half, so a half turn does not look like its twin.

const INCHES_TO_METERS := 0.0254
const BODY_IN := 2.5   # the intact house's body: the core's solid height
const OVERHANG_IN := 0.3
const CHIMNEY_IN := 0.62
const MAX_LIGHTS := 8
const LANTERN_COLOUR := Color(1.0, 0.62, 0.30)


## A 0..1 hash of a lot id and the half of the board it stands in (0 = north, 1 = south), stable per layout.
static func _hash(lot_id: int, half: int, salt: int) -> float:
	return float(posmod((lot_id * 73856093) ^ (half * 19349663) ^ (salt * 83492791), 1000)) / 1000.0


## How an intact house is DRAWN differently from its collider (plan O3), per lot and half of the board: the drawn body is inset 0.06-0.14 in on every side (inward only), yawed so
## that no corner swings out of the lot's cells (the yaw is at most 3 degrees, and at most what the inset allows, so the drawn wall is never more than 0.2 in off the collider's face),
## its top (= its eaves) is 2.5 in +- 0.3, its stone plinth 0.3-0.6 in high. The collider and the class stay the core's 2.5 in solid; nothing here is a rule.
static func house_look(lot_id: int, half: int, size: Vector2) -> Dictionary:
	var inset := 0.06 + 0.08 * _hash(lot_id, half, 4)
	var room := minf(inset, 0.2 - inset)   # how far a corner may swing out of the inset body and still stay in its cells with a gap <= 0.2 in
	var yaw_max := minf(deg_to_rad(3.0), asin(room / (maxf(size.x, size.y) * 0.5)))
	return {"inset": inset, "yaw": (2.0 * _hash(lot_id, half, 5) - 1.0) * yaw_max, "top": BODY_IN + (_hash(lot_id, half, 6) - 0.5) * 0.6, "plinth": 0.3 + 0.3 * _hash(lot_id, half, 7)}


## The drawn bodies of the intact houses (ruined, walkable tiers are never touched): {lot, centre (Vector2, board inches), size (inset), yaw, top, plinth, half}. Pure data.
static func house_bodies(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var board := Vector2(layout["nx"], layout["nz"]) * cell_in
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var size := Vector2(lot["w"], lot["h"]) * cell_in
		var centre := Vector2(lot["x"], lot["z"]) * cell_in + size * 0.5 - board * 0.5
		var half := 1 if centre.y > 0.0 else 0
		var look := house_look(lot["id"], half, size)
		out.append({"lot": lot["id"], "centre": centre, "size": size - Vector2.ONE * 2.0 * float(look["inset"]), "yaw": look["yaw"], "top": look["top"], "plinth": look["plinth"], "half": half})
	return out


## One roof per intact lot: {lot, centre (Vector2, board inches), length, width (along / across the ridge), height, along_x, half, yaw, eaves}. Pure data.
static func roofs(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var board := Vector2(layout["nx"], layout["nz"]) * cell_in
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var size := Vector2(lot["w"], lot["h"]) * cell_in
		var centre := Vector2(lot["x"], lot["z"]) * cell_in + size * 0.5 - board * 0.5
		var half := 1 if centre.y > 0.0 else 0
		var along_x := size.x > size.y or (size.x == size.y and _hash(lot["id"], half, 1) < 0.5)
		var run := size.x if along_x else size.y
		var across := size.y if along_x else size.x
		var look := house_look(lot["id"], half, size)
		out.append({"lot": lot["id"], "centre": centre, "length": run + 2.0 * OVERHANG_IN, "width": across + 2.0 * OVERHANG_IN,
			"height": 1.5 + 1.2 * _hash(lot["id"], half, 2), "along_x": along_x, "half": half, "yaw": look["yaw"], "eaves": look["top"]})
	return out


## A brick chimney on the ridge of every roof, at the end the lot's hash picks: boxes for the greybox plan ({lo, hi, kind, solid}).
static func chimneys(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in roofs(layout):
		var end_sign := 1.0 if _hash(r["lot"], r["half"], 3) < 0.5 else -1.0
		var offset: float = end_sign * (float(r["length"]) * 0.5 - 0.9)
		var centre: Vector2 = r["centre"] + (Vector2(offset, 0.0) if r["along_x"] else Vector2(0.0, offset))
		out.append({"lo": Vector3(centre.x - CHIMNEY_IN * 0.5, BODY_IN, centre.y - CHIMNEY_IN * 0.5),
			"hi": Vector3(centre.x + CHIMNEY_IN * 0.5, BODY_IN + float(r["height"]) + 0.9, centre.y + CHIMNEY_IN * 0.5), "kind": "brick", "solid": false})
	return out


## The battlements: merlons (0.7 x 0.7 x 0.4 in, three to a 3 in edge) round the open edges of every wall ridge and tower crown (a cell of the wall at
## 6 in or more, or any 9 in cell), inside the 0.4 in edge strip so the walkway keeps its width. Some are missing, more in the south half than in the north
## one (a broken battlement is a look; no merlon is cover the core knows). Boxes for the greybox plan ({lo, hi, kind, solid}).
static func merlons(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:
		var level: int = cd["level"]
		if level < 2 or (level == 2 and cd["lot_kind"] != "Wall"):
			continue
		var top: float = layout["level_in"][level]
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			var d := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side] as Vector2i
			var at := Vector2i(cd["x"], cd["z"]) + d
			if at.x >= 0 and at.y >= 0 and at.x < nx and at.y < nz and int(layout["cells"][at.y * nx + at.x]["level"]) >= level:
				continue   # a neighbour as high: this edge is no open edge
			for i in 3:
				if _hash(cd["x"] * 16 + cd["z"], half, 10 + side * 3 + i) < (0.28 if half == 1 else 0.10):
					continue
				var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
				var t := 0.5 + float(i)
				var box_lo := Vector2(lo.x + t - 0.35, lo.y) if d.x == 0 else Vector2(lo.x, lo.y + t - 0.35)
				var box_hi := box_lo + (Vector2(0.7, 0.4) if d.x == 0 else Vector2(0.4, 0.7))
				if d.y == 1:
					box_lo.y += cell_in - 0.4
					box_hi.y += cell_in - 0.4
				if d.x == 1:
					box_lo.x += cell_in - 0.4
					box_hi.x += cell_in - 0.4
				out.append({"lo": Vector3(box_lo.x, top, box_lo.y), "hi": Vector3(box_hi.x, top + 0.7, box_hi.y), "kind": "wall", "solid": false, "merlon": true})
	return out


## Where the lanterns stand (board inches, {at, half}): a post at each corner of the market square and one at every gate of the wall, against the wall
## face (north side of the gate in the north half, south side in the south half), so nothing stands in the middle of a passage and nothing takes more than the 0.75 in strip.
static func lanterns(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for corner in [Vector2(-5.5, -5.5), Vector2(5.5, -5.5), Vector2(-5.5, 5.5), Vector2(5.5, 5.5)]:
		out.append({"at": corner, "half": 1 if corner.y > 0.0 else 0})
	var per_column := {}   # a wall column is a column with a run of wall cells (a stray buttress beside it does not count)
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] == "Wall" and cd["level"] >= 1:
			per_column[cd["x"]] = int(per_column.get(cd["x"], 0)) + 1
	var wall_cols := {}
	for x in per_column:
		if per_column[x] >= 5:
			wall_cols[x] = true
	for cd: Dictionary in layout["cells"]:
		if cd["street"] and wall_cols.has(cd["x"]) and cd["level"] == 0:
			var half := 1 if cd["z"] >= nz / 2 else 0
			var at := origin + Vector2(cd["x"] + 0.5, cd["z"] + (0.12 if half == 0 else 0.88)) * cell_in
			out.append({"at": at, "half": half})
	return out


## Post and lantern boxes for the greybox plan ({lo, hi, kind, solid}): a 0.14 in timber post 2.3 in high, a 0.4 in lantern on top (the kind "lantern" glows).
static func lantern_boxes(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in lanterns(layout):
		var at: Vector2 = l["at"]
		out.append({"lo": Vector3(at.x - 0.07, 0.0, at.y - 0.07), "hi": Vector3(at.x + 0.07, 2.3, at.y + 0.07), "kind": "ladder", "solid": false, "lantern": true})
		out.append({"lo": Vector3(at.x - 0.2, 2.3, at.y - 0.2), "hi": Vector3(at.x + 0.2, 2.85, at.y + 0.2), "kind": "lantern", "solid": false, "lantern": true})
	return out


## The warm lights of the first MAX_LIGHTS lanterns (the square's four first, then the gates nearest the centre); the four nearest the centre cast shadows.
func _add_lights(layout: Dictionary) -> void:
	var list := lanterns(layout)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as Vector2).length() < (b["at"] as Vector2).length())
	for i in mini(list.size(), MAX_LIGHTS):
		var at: Vector2 = list[i]["at"]
		var light := OmniLight3D.new()
		light.name = "Lantern%d" % i
		light.position = Vector3(at.x, 2.55, at.y) * INCHES_TO_METERS
		light.light_color = LANTERN_COLOUR
		light.light_energy = 0.5
		light.omni_range = 0.24
		light.omni_attenuation = 1.3
		light.shadow_enabled = i < 4
		add_child(light)


## The dusk of the town: a low warm sun, a cool violet sky fill, a touch less exposure; applied to the scene's lighting controller (a dev view, so it is not restored).
static func dusk(lighting: Object) -> void:
	if lighting == null:
		return
	lighting.set_sun_color(Color(1.0, 0.66, 0.42))
	lighting.set_sun_energy(1.0)
	lighting.set_sun_angles(-50.0, 14.0)
	lighting.set_ambient_color(Color(0.36, 0.40, 0.66))
	lighting.set_ambient_energy(0.8)
	lighting.set_exposure(0.95)


## Props against the house walls: crates, barrels, wood piles and sacks on bare ground, only in the 0.75 in strip beside a wall face of a raised house, an intact
## house or the wall, never on a street, a plot, a pool, a ladder foot or a landmark (a prop never takes standing room). The north half stacks more barrels and
## fewer crates than the south half. Boxes ({lo, hi, kind, solid}).
static func props(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[int(c["low"])] = true
		feet[int(c["high"])] = true
	var taken := {}
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				taken[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 0 or cd["street"] or feet.has(i) or taken.has(i) or ["Hazard", "Rough", "Wall", "Roofed"].has(cd["lot_kind"]):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			var d := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side] as Vector2i
			var at := Vector2i(cd["x"], cd["z"]) + d
			if at.x < 0 or at.y < 0 or at.x >= nx or at.y >= nz:
				continue
			var n: Dictionary = cells[at.y * nx + at.x]
			if n["level"] == 0 and n["lot_kind"] != "Roofed":
				continue   # no wall face on that side
			if _hash(i, half, 40 + side) > (0.42 if half == 0 else 0.3):
				continue
			var kind := int(_hash(i, half, 50 + side) * (4.0 if half == 0 else 3.99))   # 0 barrel .. 3 crate; the north half draws from a longer list
			var size := [Vector3(0.5, 0.75, 0.5), Vector3(0.9, 0.4, 0.4), Vector3(0.7, 0.3, 0.45), Vector3(0.6, 0.55, 0.6)][kind % 4] as Vector3
			var along := 0.8 + 1.4 * _hash(i, half, 60 + side)   # position along the 3 in edge
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var depth := minf(size.z, 0.7)
			var box_lo := Vector2.ZERO
			var box_size := Vector2(size.x, depth) if d.x == 0 else Vector2(depth, size.x)
			if d.x == 0:
				box_lo = Vector2(lo.x + along, lo.y + 0.05 if d.y < 0 else lo.y + cell_in - depth - 0.05)
			else:
				box_lo = Vector2(lo.x + 0.05 if d.x < 0 else lo.x + cell_in - depth - 0.05, lo.y + along)
			out.append({"lo": Vector3(box_lo.x, 0.0, box_lo.y), "hi": Vector3(box_lo.x + box_size.x, size.y, box_lo.y + box_size.y), "kind": "wood", "solid": false, "prop": true})
	return out


## The rubble of a wall breach: eight low stones (0.08-0.25 in) scattered over the gap, flat enough to stand on (the breach is Difficult ground).
static func breach_rubble(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, layout["nz"]) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] != "Wall" or cd["level"] != 0:
			continue
		var id: int = cd["z"] * nx + cd["x"]
		for k in 8:
			var w := 0.3 + 0.4 * _hash(id, 0, 70 + k)
			var at := origin + Vector2(cd["x"], cd["z"]) * cell_in + Vector2(0.2 + (cell_in - 0.4 - w) * _hash(id, 1, 80 + k), 0.2 + (cell_in - 0.4 - w) * _hash(id, 0, 90 + k))
			out.append({"lo": Vector3(at.x, 0.0, at.y), "hi": Vector3(at.x + w, 0.08 + 0.17 * _hash(id, 1, 100 + k), at.y + w * 0.8), "kind": "rubble", "solid": false, "prop": true})
	return out


## Battlements round the hall: merlons along the outer edges of every hall footprint (a pumphouse landmark) on its block, like the wall's, inside the rim.
static func hall_merlons(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, layout["nz"]) * cell_in * -0.5
	var n := 0
	for lm: Dictionary in layout["landmarks"]:
		n += 1
		if lm["kind"] != "PumpHouse":
			continue
		var top := 0.0
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				top = maxf(top, float(layout["level_in"][layout["cells"][(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx]["level"]]))
		var lo := origin + Vector2(lm["x"], lm["z"]) * cell_in
		var size := Vector2(lm["w"], lm["h"]) * cell_in
		var half := 1 if lo.y + size.y * 0.5 > 0.0 else 0
		for edge in 4:   # north, east, south, west: 3 merlons per 3 in of edge
			var length := size.x if edge % 2 == 0 else size.y
			for i in int(length / cell_in) * 3:
				if _hash(n * 31 + edge, half, 110 + i) < (0.28 if half == 1 else 0.10):
					continue
				var t := 0.5 + float(i)
				var box_lo := Vector2(lo.x + t - 0.35, lo.y if edge == 0 else lo.y + size.y - 0.4) if edge % 2 == 0 else Vector2(lo.x if edge == 3 else lo.x + size.x - 0.4, lo.y + t - 0.35)
				var box_size := Vector2(0.7, 0.4) if edge % 2 == 0 else Vector2(0.4, 0.7)
				out.append({"lo": Vector3(box_lo.x, top, box_lo.y), "hi": Vector3(box_lo.x + box_size.x, top + 0.7, box_lo.y + box_size.y), "kind": "wall", "solid": false, "merlon": true})
	return out


## The frontage table of the building lots (plan O1, no visual change yet): for every house lot (Block, Terrace, Deck, Roofed) its FRONT face - the face with the most
## street cells beside it, ties toward the square - its back (opposite), its sides, the faces that are party walls (a building lot of its own right beside them) and
## whether it is a corner lot (street beside two adjacent faces). A lot with no street beside any face has front "" (a backyard house). Faces are "N" (z - 1), "E", "S", "W".
## Pure data: [{lot, front, back, sides, party {face: bool}, corner, streets {face: count}}].
static func frontage(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cells: Array = layout["cells"]
	var dirs := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
	var opposite := {"N": "S", "E": "W", "S": "N", "W": "E"}
	var houses := ["Block", "Terrace", "Deck", "Roofed"]
	for lot: Dictionary in layout["lots"]:
		if not houses.has(lot["kind"]):
			continue
		var streets := {"N": 0, "E": 0, "S": 0, "W": 0}
		var party := {"N": false, "E": false, "S": false, "W": false}
		for dz in int(lot["h"]):
			for dx in int(lot["w"]):
				var x: int = int(lot["x"]) + dx
				var z: int = int(lot["z"]) + dz
				for face: String in dirs:
					var at: Vector2i = Vector2i(x, z) + (dirs[face] as Vector2i)
					if at.x < 0 or at.y < 0 or at.x >= nx or at.y >= nz or (at.x >= int(lot["x"]) and at.x < int(lot["x"]) + int(lot["w"]) and at.y >= int(lot["z"]) and at.y < int(lot["z"]) + int(lot["h"])):
						continue
					var nb: Dictionary = cells[at.y * nx + at.x]
					if nb["street"]:
						streets[face] += 1
					elif nb["lot_id"] != 0 and nb["lot_id"] != lot["id"] and houses.has(String(nb["lot_kind"])):
						party[face] = true
		var centre := Vector2(float(lot["x"]) + float(lot["w"]) * 0.5 - float(nx) * 0.5, float(lot["z"]) + float(lot["h"]) * 0.5 - float(nz) * 0.5)
		var front := ""
		var best_key := Vector2(0.0, -INF)   # (street cells, how much the face points at the board centre)
		for face: String in dirs:
			if streets[face] == 0:
				continue
			var key := Vector2(float(streets[face]), -(Vector2(dirs[face] as Vector2i)).dot(centre))
			if key.x > best_key.x or (key.x == best_key.x and key.y > best_key.y):
				best_key = key
				front = face
		var sides: Array = []
		for face: String in dirs:
			if front != "" and face != front and face != opposite[front]:
				sides.append(face)
		out.append({"lot": lot["id"], "front": front, "back": opposite[front] if front != "" else "", "sides": sides, "party": party, "streets": streets,
			"corner": (streets["N"] > 0 or streets["S"] > 0) and (streets["E"] > 0 or streets["W"] > 0)})
	return out


## The unit gable prism: ridge along x at height 1 over z = 0, eaves at y = 0 on z = -0.5 / +0.5, x from -0.5 to 0.5.
static func prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), Vector3(0, 0.5, 1).normalized()],
		[Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, -0.5), Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(0, 0.5, -1).normalized()]]
	for q: Array in quads:
		for i in [0, 2, 1, 0, 3, 2]:   # clockwise seen from outside
			st.set_normal(q[4])
			st.add_vertex(q[i])
	for end in [-1.0, 1.0]:   # the gable triangles, wound to face outward
		var a := Vector3(end * 0.5, 0, 0.5)
		var b := Vector3(end * 0.5, 0, -0.5)
		var c := Vector3(end * 0.5, 1, 0)
		for v: Vector3 in ([a, c, b] if end > 0.0 else [b, c, a]):
			st.set_normal(Vector3(end, 0, 0))
			st.add_vertex(v)
	return st.commit()


## The roofs in ONE MultiMesh with the board's material (the kind "roof" in its instance data).
func build(layout: Dictionary, material: Material) -> void:
	var list := roofs(layout)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = prism_mesh()
	mm.instance_count = list.size()
	var kind := float(BoardgenTheme.TOWN_KINDS.find("roof"))
	for i in list.size():
		var r: Dictionary = list[i]
		var basis := Basis.from_scale(Vector3(r["length"], r["height"], r["width"]) * INCHES_TO_METERS)
		if not r["along_x"]:
			basis = Basis(Vector3.UP, PI * 0.5) * basis
		basis = Basis(Vector3.UP, r["yaw"]) * basis   # the roof follows its body's yaw
		var at: Vector2 = r["centre"]
		mm.set_instance_transform(i, Transform3D(basis, Vector3(at.x, r["eaves"], at.y) * INCHES_TO_METERS))
		mm.set_instance_custom_data(i, Color(kind, r["length"], r["height"], r["width"]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Roofs"
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	_add_bodies(layout, material)
	_add_lights(layout)


## The drawn bodies of the intact houses in ONE MultiMesh with the board's material (kind "roofed"; the fraction of the kind carries the plinth height for the shader).
## The greybox's own boxes for these cells draw nothing (zero scale) and only keep the collider.
func _add_bodies(layout: Dictionary, material: Material) -> void:
	var list := house_bodies(layout)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = list.size()
	var kind := float(BoardgenTheme.TOWN_KINDS.find("roofed"))
	for i in list.size():
		var b: Dictionary = list[i]
		var size := Vector3(b["size"].x, b["top"], b["size"].y)
		var at: Vector2 = b["centre"]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, b["yaw"]) * Basis.from_scale(size * INCHES_TO_METERS), Vector3(at.x, size.y * 0.5, at.y) * INCHES_TO_METERS))
		mm.set_instance_custom_data(i, Color(kind + (float(b["plinth"]) - 0.3) / 0.75, size.x, size.y, size.z))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Houses"
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
