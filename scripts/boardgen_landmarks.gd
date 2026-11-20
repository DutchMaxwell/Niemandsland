class_name BoardgenLandmarks
extends Node3D
## Procedural meshes for the landmarks of a seeded boardgen layout (NmlCore.boardgen_layout()["landmarks"]): a storage-tank
## cluster (cylinders and a pipe manifold) and a crane (plinth, lattice tower, arm). Every part is an axis-aligned primitive in
## inches, drawn instanced: one MultiMesh per shape, so the whole set is two draw calls.
##
## VISUAL ONLY. What the rules make of a landmark is the core's terrain class the binding hands over (`terrain`, `solid`);
## nothing here is read by sight or movement. A tank cluster and a crane base are solid ground (impassable, nobody stands on
## them) and carry no collider; the crane's tower and arm stand far above any model.

const INCHES_TO_METERS := 0.0254
const SKIN_IN := 0.04              # the level-0 ground skin of the greybox
const TANK_R := 1.2
const TANK_H := 3.0                # one tier-1 block high; the core knows a solid only as a 2.5 in container
const CRANE_TOP := 15.0
const CRANE_ARM_IN := 10.0
const STEEL := Color(0.36, 0.38, 0.42)
const OCHRE := Color(0.78, 0.56, 0.16)
const DARK := Color(0.10, 0.10, 0.11)


## Every part of every landmark: {shape "box"|"cyl", axis (0 x, 1 y, 2 z: a cylinder's length axis), lo, hi (inches, origin =
## board centre, y up), colour}. Pure data, so the layout alone decides the look.
static func plan(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var half := Vector2(layout["nx"], layout["nz"]) * cell_in * 0.5
	for lm: Dictionary in layout.get("landmarks", []):   # a layout from before the landmarks has none
		var lo := Vector2(lm["x"], lm["z"]) * cell_in - half
		var size := Vector2(lm["w"], lm["h"]) * cell_in
		match lm["kind"]:
			"TankCluster":
				_tanks(out, lo, lm, cell_in)
			"Crane":
				_crane(out, lo + size * 0.5, int(lm["turn"]), half)
	return out


static func _box(out: Array[Dictionary], lo: Vector3, hi: Vector3, colour: Color) -> void:
	out.append({"shape": "box", "axis": 1, "lo": lo, "hi": hi, "colour": colour})


## A cylinder of `radius` and `length` along `axis`, centred on `at`.
static func _cyl(out: Array[Dictionary], at: Vector3, radius: float, length: float, axis: int, colour: Color) -> void:
	var reach := Vector3(radius, radius, radius)
	reach[axis] = length * 0.5
	out.append({"shape": "cyl", "axis": axis, "lo": at - reach, "hi": at + reach, "colour": colour})


## A box along `dir` (a unit axis vector) from `a` to `b` inches off `c`, `half` wide each side, between heights y0 and y1.
static func _span(out: Array[Dictionary], c: Vector2, dir: Vector2, a: float, b: float, y0: float, y1: float, half: float, colour: Color) -> void:
	var p := c + dir * a
	var q := c + dir * b
	_box(out, Vector3(minf(p.x, q.x) - half, y0, minf(p.y, q.y) - half), Vector3(maxf(p.x, q.x) + half, y1, maxf(p.y, q.y) + half), colour)


static func _tanks(out: Array[Dictionary], lo: Vector2, lm: Dictionary, cell: float) -> void:
	for dz in int(lm["h"]):
		for dx in int(lm["w"]):
			var c := lo + (Vector2(dx, dz) + Vector2(0.5, 0.5)) * cell
			var tint := 0.04 * float((int(lm["x"]) + dx) * 7 % 5 + (int(lm["z"]) + dz) * 3 % 4)   # no two tanks quite alike
			_cyl(out, Vector3(c.x, SKIN_IN + TANK_H * 0.5, c.y), TANK_R, TANK_H, 1, STEEL.lightened(tint))
			_cyl(out, Vector3(c.x, SKIN_IN + TANK_H + 0.1, c.y), TANK_R * 0.8, 0.2, 1, STEEL.darkened(0.2))
			if dx + 1 < int(lm["w"]):   # the manifold: a pipe joins each pair of neighbouring tanks
				_cyl(out, Vector3(c.x + cell * 0.5, 1.8, c.y), 0.13, cell, 0, OCHRE)
			if dz + 1 < int(lm["h"]):
				_cyl(out, Vector3(c.x, 1.2, c.y + cell * 0.5), 0.13, cell, 2, OCHRE)


static func _crane(out: Array[Dictionary], c: Vector2, turn: int, half: Vector2) -> void:
	_box(out, Vector3(c.x - 1.4, SKIN_IN, c.y - 1.4), Vector3(c.x + 1.4, 3.0, c.y + 1.4), OCHRE.darkened(0.25))   # the plinth
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:   # four lattice posts
		_box(out, Vector3(c.x + s.x * 0.9 - 0.1, 3.0, c.y + s.y * 0.9 - 0.1), Vector3(c.x + s.x * 0.9 + 0.1, CRANE_TOP, c.y + s.y * 0.9 + 0.1), OCHRE)
	for y: float in [5.0, 8.0, 11.0, 14.0]:   # and the rings that tie them
		for k: Vector2 in [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9), Vector2(0, -0.9)]:
			_span(out, c + k, Vector2(absf(k.y), absf(k.x)).normalized(), -0.9, 0.9, y, y + 0.1, 0.1, OCHRE)
	_box(out, Vector3(c.x - 0.7, CRANE_TOP, c.y - 0.7), Vector3(c.x + 0.7, CRANE_TOP + 1.3, c.y + 0.7), STEEL)   # the cab
	var dir := Vector2([1, 0, -1, 0][turn], [0, 1, 0, -1][turn])
	if half.dot(dir.abs()) - c.dot(dir) < 4.0:
		dir = -dir   # the arm never swings out over the table edge
	var arm := minf(half.dot(dir.abs()) - c.dot(dir) - 0.4, CRANE_ARM_IN)
	for y: float in [CRANE_TOP + 0.2, CRANE_TOP + 1.0]:   # two chords, a counterweight, a cable and a hook
		_span(out, c, dir, 0.0, arm, y, y + 0.15, 0.15, OCHRE)
	_span(out, c, dir, -1.0, -0.5, CRANE_TOP, CRANE_TOP + 1.0, 0.4, STEEL.darkened(0.3))
	var tip := c + dir * arm
	_box(out, Vector3(tip.x - 0.03, 9.0, tip.y - 0.03), Vector3(tip.x + 0.03, CRANE_TOP + 0.2, tip.y + 0.03), DARK)
	_box(out, Vector3(tip.x - 0.2, 8.6, tip.y - 0.2), Vector3(tip.x + 0.2, 9.0, tip.y + 0.2), STEEL)


## One MultiMeshInstance3D per shape (box or cylinder), a colour per instance, no colliders.
func build(layout: Dictionary) -> void:
	var groups := {}
	for p: Dictionary in plan(layout):
		groups[p["shape"]] = groups.get(p["shape"], []) + [p]
	for key: String in groups:
		var parts: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = BoxMesh.new() if parts[0]["shape"] == "box" else _unit_cylinder()
		mm.instance_count = parts.size()
		for i in parts.size():
			var size: Vector3 = (parts[i]["hi"] - parts[i]["lo"]) * INCHES_TO_METERS
			var centre: Vector3 = (parts[i]["hi"] + parts[i]["lo"]) * 0.5 * INCHES_TO_METERS
			mm.set_instance_transform(i, Transform3D(_basis(parts[i]["shape"], parts[i]["axis"], size), centre))
			mm.set_instance_color(i, parts[i]["colour"])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = _material()
		add_child(mmi)


## Unit box / cylinder scaled per instance: a cylinder's length axis is y, so one lying along x or z is turned first.
static func _basis(shape: String, axis: int, size: Vector3) -> Basis:
	if shape == "box" or axis == 1:
		return Basis.from_scale(size)
	if axis == 0:
		return Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(size.y, size.x, size.z))
	return Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(size.x, size.z, size.y))


static func _unit_cylinder() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 1
	return mesh


static func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true   # the colours above are display values
	mat.roughness = 0.8
	mat.metallic = 0.25
	return mat
