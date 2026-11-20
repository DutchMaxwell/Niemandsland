class_name BoardgenProps
extends Node3D
## Dressing of a seeded boardgen board for the look pass: pipes along the tier walls, crates, barrels, floor grates and warm
## sodium lamps, all drawn from a small generated kit (boxes, cylinders; no model file). VISUAL ONLY: no collider, nothing the rules
## read. The open floor stays clear - every prop stands against a wall or lies flat - so a model base is never pushed off a spot.
## plan() is a pure function of the layout (its seed feeds one RandomNumberGenerator), so one seed always dresses the same board.

const INCHES_TO_METERS := 0.0254
const MAX_LIGHTS := 8
const LAMP_GAP_IN := 14.0
const LAMP_RANGE_IN := 13.0
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SODIUM := Color(1.0, 0.6, 0.24)
const CRATES: Array[Color] = [Color(0.38, 0.32, 0.22), Color(0.25, 0.31, 0.27), Color(0.42, 0.28, 0.18)]
const BARRELS: Array[Color] = [Color(0.17, 0.27, 0.36), Color(0.36, 0.17, 0.10), Color(0.24, 0.30, 0.18)]
const PIPE := Color(0.45, 0.40, 0.33)


## Every prop of the board, in metres off the board centre: {shape: box | cyl | bulb | light, xf: Transform3D, colour: Color}.
static func plan(layout: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) * 2654435761 + 97
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var origin := Vector2(nx, nz) * cell * -0.5
	var feet := {}   # the floor cell at the foot of a ladder stays bare
	for c: Dictionary in layout["connectors"]:
		feet[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	var out: Array[Dictionary] = []
	var lamps: Array[Dictionary] = []
	for z in nz:
		for x in nx:
			if cells[z * nx + x]["level"] > 0 or feet.has(Vector2i(x, z)):
				continue
			var centre := origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * cell
			if cells[z * nx + x]["street"] and rng.randf() < 0.08:   # a floor grate: dark frame, lighter slats, lies flat
				out.append(_prop("box", centre, 0.0, Vector3(1.5, 0.02, 1.5), 0.056, Color(0.09, 0.09, 0.10)))
				for i in 5:
					out.append(_prop("box", centre + Vector2(-0.6 + 0.3 * i, 0.0), 0.0, Vector3(0.1, 0.05, 1.3), 0.075, Color(0.30, 0.30, 0.33)))
			for d in DIRS:
				var o := Vector2i(x, z) + d
				if o.x < 0 or o.y < 0 or o.x >= nx or o.y >= nz or cells[o.y * nx + o.x]["level"] == 0:
					continue
				var wall_h := float(layout["level_in"][cells[o.y * nx + o.x]["level"]])
				var yaw := atan2(float(d.x), float(d.y))   # local +z of a prop points at the wall
				var at := centre + Vector2(d) * cell * 0.5   # the wall plane, mid-edge
				var side := Vector2(-d.y, d.x) * rng.randf_range(-0.8, 0.8)
				var roll := rng.randf()
				if roll < 0.2:   # a lagged pipe run the whole edge long
					out.append(_prop("cyl", at - Vector2(d) * 0.35, yaw, Vector3(0.5, cell, 0.5), 1.0, PIPE, true))
				elif roll < 0.36:   # a crate, sometimes with a second one on top
					var size := Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.8, 1.1), rng.randf_range(0.9, 1.3))
					var tint: Color = CRATES[rng.randi() % CRATES.size()]
					out.append(_prop("box", at - Vector2(d) * (size.z * 0.5 + 0.05) + side, yaw + rng.randf_range(-0.2, 0.2), size, size.y * 0.5, tint))
					if rng.randf() < 0.4:
						out.append(_prop("box", at - Vector2(d) * (size.z * 0.5 + 0.05) + side, yaw + 0.5, size * 0.7, size.y + size.y * 0.35, tint.lightened(0.1)))
				elif roll < 0.48:   # a barrel
					out.append(_prop("cyl", at - Vector2(d) * 0.45 + side, yaw, Vector3(0.65, 0.95, 0.65), 0.475, BARRELS[rng.randi() % BARRELS.size()]))
				elif roll < 0.62:   # a lamp site (the picks are made below)
					lamps.append({"at": at, "d": d, "yaw": yaw, "h": wall_h})
	var chosen: Array[Dictionary] = []
	while not lamps.is_empty() and chosen.size() < MAX_LIGHTS:   # a seeded pick, at least LAMP_GAP_IN apart
		var l: Dictionary = lamps.pop_at(rng.randi() % lamps.size())
		if chosen.all(func(o: Dictionary) -> bool: return o["at"].distance_to(l["at"]) >= LAMP_GAP_IN):
			chosen.append(l)
	for l in chosen:
		var d: Vector2i = l["d"]
		var y: float = l["h"] - 0.8
		out.append(_prop("box", l["at"] - Vector2(d) * 0.15, l["yaw"], Vector3(0.6, 0.4, 0.3), y, Color(0.10, 0.10, 0.11)))
		out.append(_prop("bulb", l["at"] - Vector2(d) * 0.4, l["yaw"], Vector3(0.45, 0.2, 0.2), y - 0.05, SODIUM))
		out.append({"shape": "light", "xf": Transform3D(Basis(), Vector3(l["at"].x - d.x * 0.9, y, l["at"].y - d.y * 0.9) * INCHES_TO_METERS), "colour": SODIUM})
	return out


## One prop: `size` inches (a cylinder: x = diameter, y = height, z = diameter) at `pos` inches, centre height `y`; `lying` turns a
## cylinder onto its side along the wall.
static func _prop(shape: String, pos: Vector2, yaw: float, size: Vector3, y: float, colour: Color, lying := false) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw)
	if lying:
		basis = basis * Basis(Vector3.BACK, PI * 0.5)   # the cylinder's axis runs along the wall
	return {"shape": shape, "xf": Transform3D(basis * Basis.from_scale(size * INCHES_TO_METERS), Vector3(pos.x, y, pos.y) * INCHES_TO_METERS), "colour": colour}


## One MultiMesh per shape (so the whole kit is three draw calls) and at most MAX_LIGHTS shadowless omni lights.
func build(layout: Dictionary) -> void:
	var props := plan(layout)
	for shape in ["box", "cyl", "bulb"]:
		var group := props.filter(func(p: Dictionary) -> bool: return p["shape"] == shape)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _unit_mesh(shape)
		mm.instance_count = group.size()
		for i in group.size():
			mm.set_instance_transform(i, group[i]["xf"])
			mm.set_instance_color(i, group[i]["colour"])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = shape
		mmi.multimesh = mm
		add_child(mmi)
	for l in props.filter(func(p: Dictionary) -> bool: return p["shape"] == "light"):
		var light := OmniLight3D.new()
		light.position = l["xf"].origin
		light.light_color = SODIUM
		light.light_energy = 0.6
		light.omni_range = LAMP_RANGE_IN * INCHES_TO_METERS
		light.distance_fade_enabled = true
		light.distance_fade_begin = 2.5
		light.distance_fade_length = 1.0
		add_child(light)


func _unit_mesh(shape: String) -> Mesh:
	var mesh: PrimitiveMesh = BoxMesh.new()
	if shape == "cyl":
		var cyl := CylinderMesh.new()
		cyl.height = 1.0   # radius 0.5 is the default: a unit cylinder
		cyl.radial_segments = 10
		mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.75
	mat.metallic = 0.35
	if shape == "bulb":
		mat.emission_enabled = true
		mat.emission = SODIUM
		mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	return mesh
