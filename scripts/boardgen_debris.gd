class_name BoardgenDebris
extends Node3D
## Urban debris for the look pass of a seeded boardgen board: paper scraps that lie flat anywhere, and rubble piles, cans, leaning scrap
## plates and cables that lie ONLY in the wall strip (STRIP_IN off a tier wall), so the open floor stays clear for bases. The foot of a
## connector and the sump cells stay bare. Boxes and cylinders in two MultiMeshes; VISUAL ONLY (no collider). plan() is a pure
## function of the layout (its seed feeds one RandomNumberGenerator).

const INCHES_TO_METERS := 0.0254
const STRIP_IN := 0.75   # loose debris stays this close to a tier wall
const FLAT_IN := 0.12   # an item no higher than this above its floor (paper) does not block a base and may lie anywhere
const SKIN_IN := 0.04
const CHUNKS: Array[Color] = [Color(0.40, 0.19, 0.14), Color(0.33, 0.17, 0.13), Color(0.42, 0.42, 0.40), Color(0.30, 0.30, 0.29)]
const CANS: Array[Color] = [Color(0.55, 0.16, 0.12), Color(0.14, 0.27, 0.45), Color(0.18, 0.38, 0.22)]


## Every item of the board, in metres off the board centre: {shape: box | cyl, xf: Transform3D, colour: Color}.
static func plan(layout: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) * 40503 + 211
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var origin := Vector2(nx, nz) * cell * -0.5
	var feet := {}   # the floor cell at the foot of a ladder or stair stays bare
	for c: Dictionary in layout["connectors"]:
		feet[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	for lm: Dictionary in layout.get("landmarks", []):   # a landmark's footprint stays bare too
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				feet[Vector2i(int(lm["x"]) + dx, int(lm["z"]) + dz)] = true
	var busy := {}   # the cells that carry a prop of the BoardgenProps kit: the loose debris keeps off them
	for prop: Dictionary in BoardgenProps.plan(layout):
		if prop["shape"] != "light" and prop["xf"].origin.y > FLAT_IN * INCHES_TO_METERS:
			busy[Vector2i(floori(prop["xf"].origin.x / INCHES_TO_METERS / cell + nx * 0.5), floori(prop["xf"].origin.z / INCHES_TO_METERS / cell + nz * 0.5))] = true
	var out: Array[Dictionary] = []
	for z in nz:
		for x in nx:
			var me: Dictionary = cells[z * nx + x]
			if me["lot_kind"] == "Hazard" or feet.has(Vector2i(x, z)):
				continue
			var centre := origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * cell
			if rng.randf() < 0.18:   # paper scraps, flat, anywhere in the cell
				for i in rng.randi_range(1, 3):
					var at := centre + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
					out.append(_item("box", at, (float(layout["level_in"][me["level"]]) if me["level"] > 0 else SKIN_IN) + 0.008, Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(0.5, 0.9), 0.012, rng.randf_range(0.4, 0.7)), Color(0.66, 0.63, 0.55).darkened(rng.randf() * 0.3)))
			for d in BoardgenProps.DIRS:
				var o := Vector2i(x, z) + d
				if me["level"] > 0 or busy.has(Vector2i(x, z)) or o.x < 0 or o.y < 0 or o.x >= nx or o.y >= nz or cells[o.y * nx + o.x]["level"] == 0:
					continue
				var yaw := Basis(Vector3.UP, atan2(float(d.x), float(d.y)))   # local +z of an item points at the wall
				var wall := centre + Vector2(d) * cell * 0.5   # the wall plane, mid-edge
				var along := Vector2(-d.y, d.x)
				var roll := rng.randf()
				if roll < 0.25:   # a rubble pile of broken brick and concrete, two layers, with a can or two beside it
					var pile := wall + along * rng.randf_range(-0.5, 0.5)
					for i in rng.randi_range(4, 7):
						var s := rng.randf_range(0.18, 0.4)
						out.append(_item("box", pile - Vector2(d) * rng.randf_range(0.15, 0.4) + along * rng.randf_range(-0.6, 0.6), SKIN_IN + s * 0.4 + (0.2 if i > 3 else 0.0), Basis.from_euler(Vector3(rng.randf() * 0.8, rng.randf() * TAU, rng.randf() * 0.8)), Vector3(s, s * 0.8, s * 1.2), CHUNKS[rng.randi() % CHUNKS.size()]))
					for i in rng.randi_range(0, 2):
						var lying := rng.randf() < 0.4
						var rot := Basis(Vector3.UP, rng.randf() * TAU) * (Basis(Vector3.BACK, PI * 0.5) if lying else Basis())
						out.append(_item("cyl", pile - Vector2(d) * rng.randf_range(0.2, 0.36) + along * rng.randf_range(-0.65, 0.65), SKIN_IN + (0.15 if lying else 0.225), rot, Vector3(0.3, 0.45, 0.3), CANS[rng.randi() % CANS.size()]))
				elif roll < 0.4:   # a scrap plate leaning on the wall
					out.append(_item("box", wall - Vector2(d) * rng.randf_range(0.15, 0.35) + along * rng.randf_range(-0.9, 0.9), SKIN_IN + 0.16, yaw * Basis(Vector3.RIGHT, -1.1), Vector3(0.5, 0.03, 0.35), Color(0.30, 0.31, 0.33).lerp(Color(0.38, 0.20, 0.10), rng.randf())))
				elif roll < 0.58:   # a cable along the wall foot
					var length := rng.randf_range(1.0, 2.2)
					var lim := 1.4 - length * 0.5
					out.append(_item("cyl", wall - Vector2(d) * rng.randf_range(0.1, 0.5) + along * rng.randf_range(-lim, lim), SKIN_IN + 0.035, yaw * Basis(Vector3.BACK, PI * 0.5), Vector3(0.07, length, 0.07), Color(0.07, 0.07, 0.08).lerp(Color(0.30, 0.10, 0.07), rng.randf() * 0.5)))
	return out


## One item: `size` inches (a cylinder: x = diameter, y = height) turned by `rot` at `pos` inches, centre height `y`.
static func _item(shape: String, pos: Vector2, y: float, rot: Basis, size: Vector3, colour: Color) -> Dictionary:
	return {"shape": shape, "xf": Transform3D(rot * Basis.from_scale(size * INCHES_TO_METERS), Vector3(pos.x, y, pos.y) * INCHES_TO_METERS), "colour": colour}


## One MultiMesh per shape, so the whole kit is two draw calls.
func build(layout: Dictionary) -> void:
	var items := plan(layout)
	var meshes := {"box": BoxMesh.new(), "cyl": CylinderMesh.new()}
	meshes["cyl"].height = 1.0   # radius 0.5 is the default: a unit cylinder
	meshes["cyl"].radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	for shape: String in meshes:
		var group := items.filter(func(p: Dictionary) -> bool: return p["shape"] == shape)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[shape]
		mm.mesh.material = mat
		mm.instance_count = group.size()
		for i in group.size():
			mm.set_instance_transform(i, group[i]["xf"])
			mm.set_instance_color(i, group[i]["colour"])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = shape
		mmi.multimesh = mm
		add_child(mmi)
