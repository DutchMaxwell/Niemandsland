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
const OCHRE := Color(0.74, 0.52, 0.14)
const DARK := Color(0.10, 0.10, 0.11)
const TANK := Color(0.52, 0.55, 0.52)
const VALVE := Color(0.85, 0.12, 0.06)
const SHADER := preload("res://shaders/tiefwerk_landmark.gdshader")
## `look` of a cylinder part, as the landmark shader knows it (INSTANCE_CUSTOM.x).
const LOOK_TANK := 1
const LOOK_CAP := 2
const LOOK_PIPE := 3
const LOOK_JACKET := 4
const LOOK_PAINT := 10
const LOOK_STRIPE := 11
const GAUGE := Color(0.88, 0.86, 0.78)


## Every part of every landmark: {shape "box"|"cyl", axis (0 x, 1 y, 2 z: a cylinder's length axis), lo, hi (inches, origin =
## board centre, y up), colour, glow, look}. A "torus" is a flat ring of
## diameter hi.x - lo.x whose tube is 8 % of that. Pure data, so the layout alone decides the look.
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


static func _box(out: Array[Dictionary], lo: Vector3, hi: Vector3, colour: Color, glow := false, look := 0) -> void:
	out.append({"shape": "box", "axis": 1, "lo": lo, "hi": hi, "colour": colour, "glow": glow, "look": look})


## A cylinder of `radius` and `length` along `axis`, centred on `at`.
static func _cyl(out: Array[Dictionary], at: Vector3, radius: float, length: float, axis: int, colour: Color, glow := false, look := 0) -> void:
	var reach := Vector3(radius, radius, radius)
	reach[axis] = length * 0.5
	out.append({"shape": "cyl", "axis": axis, "lo": at - reach, "hi": at + reach, "colour": colour, "glow": glow, "look": look})


## A flat ring (a hand rail, a valve wheel) of `diameter` round `at`.
static func _ring(out: Array[Dictionary], at: Vector3, diameter: float, colour: Color) -> void:
	var reach := Vector3(diameter * 0.5, diameter * 0.04, diameter * 0.5)
	out.append({"shape": "torus", "axis": 1, "lo": at - reach, "hi": at + reach, "colour": colour, "glow": false})


## A box along `dir` (a unit axis vector) from `a` to `b` inches off `c`, `half` wide each side, between heights y0 and y1.
static func _span(out: Array[Dictionary], c: Vector2, dir: Vector2, a: float, b: float, y0: float, y1: float, half: float, colour: Color, look := 0) -> void:
	var p := c + dir * a
	var q := c + dir * b
	_box(out, Vector3(minf(p.x, q.x) - half, y0, minf(p.y, q.y) - half), Vector3(maxf(p.x, q.x) + half, y1, maxf(p.y, q.y) + half), colour, false, look)


static func _tanks(out: Array[Dictionary], lo: Vector2, lm: Dictionary, cell: float) -> void:
	for dz in int(lm["h"]):
		for dx in int(lm["w"]):
			var c := lo + (Vector2(dx, dz) + Vector2(0.5, 0.5)) * cell
			var salt := (int(lm["x"]) + dx) * 7 + (int(lm["z"]) + dz) * 13
			var top := SKIN_IN + TANK_H
			_cyl(out, Vector3(c.x, SKIN_IN + TANK_H * 0.5, c.y), TANK_R, TANK_H, 1, TANK.lightened(0.04 * (salt % 5)), false, LOOK_TANK)
			_cyl(out, Vector3(c.x, top + 0.1, c.y), TANK_R * 0.8, 0.2, 1, TANK.darkened(0.15), false, LOOK_CAP)
			_cyl(out, Vector3(c.x, top, c.y), 1.45, 0.06, 1, STEEL.darkened(0.2))   # the catwalk ring round the top, with its rail
			_ring(out, Vector3(c.x, top + 0.5, c.y), 2.8, STEEL)
			for k in 6:
				var post := c + Vector2.from_angle(k * TAU / 6.0) * 1.4
				_box(out, Vector3(post.x - 0.03, top, post.y - 0.03), Vector3(post.x + 0.03, top + 0.5, post.y + 0.03), STEEL)
			for k in 4:   # the catwalk stands on four legs that reach the floor, braced to the shell
				var leg := c + Vector2.from_angle(PI * 0.25 + k * PI * 0.5) * 1.35
				_box(out, Vector3(leg.x - 0.05, SKIN_IN, leg.y - 0.05), Vector3(leg.x + 0.05, top, leg.y + 0.05), STEEL.darkened(0.1))
				_box(out, Vector3(minf(leg.x, c.x + (leg.x - c.x) * 0.9) - 0.03, top - 0.6, minf(leg.y, c.y + (leg.y - c.y) * 0.9) - 0.03), Vector3(maxf(leg.x, c.x + (leg.x - c.x) * 0.9) + 0.03, top - 0.5, maxf(leg.y, c.y + (leg.y - c.y) * 0.9) + 0.03), STEEL.darkened(0.1))
			var out_dir := Vector2([1, 0, -1, 0][salt % 4], [0, 1, 0, -1][salt % 4])   # a ladder up the side that faces out
			var foot := c + out_dir * (TANK_R + 0.08)
			for side in [-0.25, 0.25]:
				_span(out, foot + Vector2(out_dir.y, out_dir.x) * side, out_dir, 0.0, 0.0, SKIN_IN, top, 0.025, STEEL)
			for r in 5:
				_span(out, foot, Vector2(out_dir.y, out_dir.x), -0.25, 0.25, 0.4 + r * 0.5, 0.45 + r * 0.5, 0.025, STEEL)
			for y in [1.2, 1.9, 2.6]:   # the safety cage: a hoop of three bars round the ladder
				var hoop := foot + out_dir * 0.2
				_span(out, hoop, Vector2(out_dir.y, out_dir.x), -0.28, 0.28, y, y + 0.04, 0.02, STEEL)
				for side in [-0.28, 0.28]:
					_span(out, hoop + Vector2(out_dir.y, out_dir.x) * side, out_dir, -0.2, 0.0, y, y + 0.04, 0.02, STEEL)
			var side_dir := Vector2(out_dir.y, out_dir.x)   # a pressure gauge on the quarter turn from the ladder
			_cyl(out, Vector3(c.x + side_dir.x * (TANK_R + 0.03), 1.3, c.y + side_dir.y * (TANK_R + 0.03)), 0.17, 0.06, 0 if side_dir.x != 0.0 else 2, DARK)
			_cyl(out, Vector3(c.x + side_dir.x * (TANK_R + 0.06), 1.3, c.y + side_dir.y * (TANK_R + 0.06)), 0.13, 0.04, 0 if side_dir.x != 0.0 else 2, GAUGE)
			if dx + 1 < int(lm["w"]):   # the manifold: a lagged pipe with flanges and a valve joins each pair of neighbouring tanks
				_pipe(out, Vector3(c.x + cell * 0.5, 1.8, c.y), 0, cell)
			if dz + 1 < int(lm["h"]):
				_pipe(out, Vector3(c.x, 1.2, c.y + cell * 0.5), 2, cell)


static func _pipe(out: Array[Dictionary], at: Vector3, axis: int, length: float) -> void:
	_cyl(out, at, 0.17, length, axis, STEEL.lightened(0.1), false, LOOK_PIPE)
	for f in [-0.7, 0.7]:
		_cyl(out, at + Vector3(f if axis == 0 else 0.0, 0.0, f if axis == 2 else 0.0), 0.27, 0.1, axis, STEEL.darkened(0.2))   # flanges...
		_cyl(out, at + Vector3(f * 1.6 if axis == 0 else 0.0, 0.0, f * 1.6 if axis == 2 else 0.0), 0.24, 0.6, axis, STEEL.lightened(0.25), false, LOOK_JACKET)   # ...and the insulated stretch beyond
	_box(out, at + Vector3(-0.22, 0.1, -0.22), at + Vector3(0.22, 0.5, 0.22), VALVE.darkened(0.3))   # the valve: a bright wheel on a body and stem
	_cyl(out, at + Vector3(0.0, 0.7, 0.0), 0.05, 0.4, 1, STEEL)
	_ring(out, at + Vector3(0.0, 0.85, 0.0), 0.75, VALVE)
	_cyl(out, at + Vector3(0.0 if axis == 2 else -0.5, 0.2, 0.0 if axis == 0 else -0.5), 0.04, 0.3, 1, STEEL)   # a gauge on its stem, face up
	_cyl(out, at + Vector3(0.0 if axis == 2 else -0.5, 0.38, 0.0 if axis == 0 else -0.5), 0.2, 0.05, 1, GAUGE)


static func _crane(out: Array[Dictionary], c: Vector2, turn: int, half: Vector2) -> void:
	_box(out, Vector3(c.x - 1.4, SKIN_IN, c.y - 1.4), Vector3(c.x + 1.4, 3.0, c.y + 1.4), OCHRE.darkened(0.1), false, LOOK_STRIPE)   # the plinth, with warning stripes
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:   # four lattice posts
		_box(out, Vector3(c.x + s.x * 0.9 - 0.1, 3.0, c.y + s.y * 0.9 - 0.1), Vector3(c.x + s.x * 0.9 + 0.1, CRANE_TOP, c.y + s.y * 0.9 + 0.1), OCHRE, false, LOOK_PAINT)
	for y: float in [5.0, 8.0, 11.0, 14.0]:   # and the rings that tie them
		for k: Vector2 in [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9), Vector2(0, -0.9)]:
			_span(out, c + k, Vector2(absf(k.y), absf(k.x)).normalized(), -0.9, 0.9, y, y + 0.1, 0.1, OCHRE, LOOK_PAINT)
	_box(out, Vector3(c.x - 0.7, CRANE_TOP, c.y - 0.7), Vector3(c.x + 0.7, CRANE_TOP + 1.3, c.y + 0.7), OCHRE.darkened(0.2), false, LOOK_PAINT)   # the cab
	var dir := Vector2([1, 0, -1, 0][turn], [0, 1, 0, -1][turn])
	if half.dot(dir.abs()) - c.dot(dir) < 4.0:
		dir = -dir   # the arm never swings out over the table edge
	var arm := minf(half.dot(dir.abs()) - c.dot(dir) - 0.4, CRANE_ARM_IN)
	for y: float in [CRANE_TOP + 0.2, CRANE_TOP + 1.0]:   # two chords, a counterweight, a cable and a hook
		_span(out, c, dir, 0.0, arm, y, y + 0.15, 0.15, OCHRE, LOOK_PAINT)
	for t in range(1, int(arm / 1.2) + 1):   # struts between the chords
		_span(out, c, dir, t * 1.2, t * 1.2, CRANE_TOP + 0.35, CRANE_TOP + 1.0, 0.03, OCHRE, LOOK_PAINT)
	for k in 3:   # the counterweight: stacked blocks
		_span(out, c, dir, -1.0, -0.5, CRANE_TOP + k * 0.33, CRANE_TOP + (k + 1) * 0.33, 0.4, STEEL.darkened(0.3 + 0.05 * k), LOOK_PAINT)
	var tip := c + dir * arm
	for side in [-0.07, 0.07]:   # two cables to the hook block, which has its sheaves and a hook ring below
		_box(out, Vector3(tip.x + side - 0.015, 9.0, tip.y - 0.015), Vector3(tip.x + side + 0.015, CRANE_TOP + 0.2, tip.y + 0.015), DARK)
	_box(out, Vector3(tip.x - 0.22, 8.55, tip.y - 0.15), Vector3(tip.x + 0.22, 9.0, tip.y + 0.15), OCHRE, false, LOOK_STRIPE)
	_cyl(out, Vector3(tip.x, 8.95, tip.y), 0.1, 0.34, 2, STEEL.darkened(0.3))
	_ring(out, Vector3(tip.x, 8.45, tip.y), 0.3, STEEL)


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
		mm.use_custom_data = true
		mm.mesh = _unit_mesh(parts[0]["shape"])
		mm.instance_count = parts.size()
		for i in parts.size():
			var size: Vector3 = (parts[i]["hi"] - parts[i]["lo"]) * INCHES_TO_METERS
			var centre: Vector3 = (parts[i]["hi"] + parts[i]["lo"]) * 0.5 * INCHES_TO_METERS
			mm.set_instance_transform(i, Transform3D(_basis(parts[i]["shape"], parts[i]["axis"], size), centre))
			mm.set_instance_color(i, parts[i]["colour"])
			mm.set_instance_custom_data(i, Color(parts[i].get("look", 0), 0.0, 0.0, 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = _look_material()
		add_child(mmi)


## Unit box / cylinder scaled per instance: a cylinder's length axis is y, so one lying along x or z is turned first.
static func _basis(shape: String, axis: int, size: Vector3) -> Basis:
	if shape == "torus":
		return Basis.from_scale(Vector3.ONE * size.x)
	if shape == "box" or axis == 1:
		return Basis.from_scale(size)
	if axis == 0:
		return Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(size.y, size.x, size.z))
	return Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(size.x, size.z, size.y))


static func _unit_mesh(shape: String) -> Mesh:
	if shape == "box":
		return BoxMesh.new()
	if shape == "torus":
		var ring := TorusMesh.new()
		ring.inner_radius = 0.42
		ring.outer_radius = 0.5
		ring.rings = 16
		ring.ring_segments = 6
		return ring
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 1
	return mesh


## The procedural look of every plain part (tank shells and caps, pipes, jackets, crane paint): one shader, the instance says which.
static func _look_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	return mat
