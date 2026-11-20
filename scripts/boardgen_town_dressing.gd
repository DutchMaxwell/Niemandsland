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


## One roof per intact lot: {lot, centre (Vector2, board inches), length, width (along / across the ridge), height, along_x, half}. Pure data.
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
		out.append({"lot": lot["id"], "centre": centre, "length": run + 2.0 * OVERHANG_IN, "width": across + 2.0 * OVERHANG_IN,
			"height": 1.5 + 1.2 * _hash(lot["id"], half, 2), "along_x": along_x, "half": half})
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
	var wall_cols := {}
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] == "Wall" and cd["level"] >= 1:
			wall_cols[cd["x"]] = true
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
		light.light_energy = 1.4
		light.omni_range = 0.3
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
	lighting.set_ambient_energy(0.62)
	lighting.set_exposure(0.95)


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
		var at: Vector2 = r["centre"]
		mm.set_instance_transform(i, Transform3D(basis, Vector3(at.x, BODY_IN, at.y) * INCHES_TO_METERS))
		mm.set_instance_custom_data(i, Color(kind, r["length"], r["height"], r["width"]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Roofs"
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	_add_lights(layout)
