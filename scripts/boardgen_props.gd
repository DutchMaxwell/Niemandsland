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
## The finer look's lamp: a paler sodium (the walls keep their own colours under it), a downward cone with inverse-square falloff,
## shadows on the lamps nearest the board centre (rails and pipes throw one, nothing is lit behind a wall).
const LAMP_COLOUR := Color(1.0, 0.72, 0.45)
const SHADOW_LAMPS := 4
const CRATES: Array[Color] = [Color(0.38, 0.32, 0.22), Color(0.25, 0.31, 0.27), Color(0.42, 0.28, 0.18)]
const BARRELS: Array[Color] = [Color(0.17, 0.27, 0.36), Color(0.36, 0.17, 0.10), Color(0.24, 0.30, 0.18)]
const PIPE := Color(0.45, 0.40, 0.33)
const RUST := Color(0.42, 0.20, 0.09)
const STEEL := Color(0.12, 0.12, 0.13)
const PIPE_BORES: Array[float] = [0.22, 0.34, 0.5]
## Nothing that is not flat reaches further than this from the wall it stands against: the rest of the cell stays standing room.
const STRIP_IN := 0.75
## A prop whose top is no higher than this lies flat (a grate): a base stands on it.
const FLAT_IN := 0.12
## The authored K2 pipe modules (BoardgenKit) are cut for this bore (outer diameter, inches); a run draws them at bore / KIT_BORE_IN, uniformly.
## The pipe axis stands KIT_WALL_RATIO x its bore off the wall (the clamps and the elbow's collar are cut for it: 0.255 in at the reference bore).
const KIT_MODULES: Array[String] = ["pipe", "elbow", "flange", "bracket", "valve", "lamp_caged", "junction_box"]
const KIT_BORE_IN := 0.34
const KIT_WALL_RATIO := 0.75
const KIT_WALL_IN := 0.255
const COLLAR_IN := 0.3   # the elbow's wall collar is 0.28 in in radius at the reference bore; an elbow stands that far (scaled) from the cell boundary
## Module extents at the reference bore, inches (min corner, size): the standing-room test reads them.
const KIT_BOUNDS := {"pipe": AABB(Vector3(-1.5, -0.184, -0.184), Vector3(3.0, 0.368, 0.368)), "elbow": AABB(Vector3(-0.375, -0.28, -0.17), Vector3(0.655, 0.56, 0.447)),
	"flange": AABB(Vector3(-0.074, -0.246, -0.246), Vector3(0.148, 0.492, 0.492)), "bracket": AABB(Vector3(-0.08, -0.215, -0.211), Vector3(0.16, 0.427, 0.471)),
	"valve": AABB(Vector3(-0.23, -0.238, -0.238), Vector3(0.459, 0.878, 0.476)), "lamp_caged": AABB(Vector3(-0.24, -0.25, -0.71), Vector3(0.48, 0.51, 0.71)),
	"junction_box": AABB(Vector3(-0.25, -0.18, -0.255), Vector3(0.5, 0.52, 0.255))}

var _omnis: Array[OmniLight3D] = []   # the plain lamps (Low) and, one for one, the cones (Medium up)
var _spots: Array[SpotLight3D] = []
var _shadowed: Array[int] = []


## Every prop of the board, in metres off the board centre: {shape: box | cyl | bulb | ball | ring | light, xf: Transform3D, colour: Color}. With
## `kit` the pipe runs are instances of the K2 modules instead (shape = the module's name) and obey the rule that no pipe ends in the air:
## a run ends in a joint flange where the next cell's run carries on, else in an elbow that turns into the wall and ends in a collar on it.
static func plan(layout: Dictionary, kit := false) -> Array[Dictionary]:
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
	for lm: Dictionary in layout.get("landmarks", []):   # a landmark's footprint stays bare too
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				feet[Vector2i(int(lm["x"]) + dx, int(lm["z"]) + dz)] = true
	var out: Array[Dictionary] = []
	var lamps: Array[Dictionary] = []
	var runs := {}   # (cell x, z, wall direction) -> the pipe run along that cell edge
	for z in nz:
		for x in nx:
			if cells[z * nx + x]["level"] > 0 or cells[z * nx + x]["lot_kind"] == "Hazard" or feet.has(Vector2i(x, z)):
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
				if roll < 0.2:   # a pipe run the whole edge long
					runs[Vector4i(x, z, d.x, d.y)] = _run(rng, at, d, yaw, wall_h, cell)
				elif roll < 0.36:   # a small crate, sometimes with a second one on top
					var size := Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.5, 0.8), rng.randf_range(0.35, 0.55))
					var tint: Color = CRATES[rng.randi() % CRATES.size()]
					out.append(_prop("box", at - Vector2(d) * (size.z * 0.5 + 0.05) + side, yaw + rng.randf_range(-0.15, 0.15), size, size.y * 0.5, tint))
					if rng.randf() < 0.4:
						out.append(_prop("box", at - Vector2(d) * (size.z * 0.5 + 0.05) + side, yaw + 0.5, size * 0.7, size.y + size.y * 0.35, tint.lightened(0.1)))
				elif roll < 0.48:   # a barrel
					out.append(_prop("cyl", at - Vector2(d) * 0.4 + side, yaw, Vector3(0.55, 0.8, 0.55), 0.4, BARRELS[rng.randi() % BARRELS.size()]))
				elif roll < 0.62:   # a lamp site (the picks are made below)
					lamps.append({"at": at, "d": d, "yaw": yaw, "h": wall_h})
	for key: Vector4i in runs:
		if kit:
			_run_kit(out, runs[key], key, runs)
		else:
			_run_prims(out, runs[key])
		_run_streaks(out, runs[key])
	var chosen: Array[Dictionary] = []
	while not lamps.is_empty() and chosen.size() < MAX_LIGHTS:   # a seeded pick, at least LAMP_GAP_IN apart
		var l: Dictionary = lamps.pop_at(rng.randi() % lamps.size())
		if chosen.all(func(o: Dictionary) -> bool: return o["at"].distance_to(l["at"]) >= LAMP_GAP_IN):
			chosen.append(l)
	for l in chosen:
		var d: Vector2i = l["d"]
		var y: float = l["h"] - 0.8
		_lamp(out, l["at"], d, l["yaw"], y, l["h"], kit)
		out.append({"shape": "light", "xf": Transform3D(Basis(), Vector3(l["at"].x - d.x * 0.9, y, l["at"].y - d.y * 0.9) * INCHES_TO_METERS), "colour": SODIUM, "out": Vector2(-d.x, -d.y)})
	return out


## A pipe run along a wall edge as plain numbers (all the seeded draws; the looks below only read them): one bore and height per wall line (so
## the runs of neighbouring cells meet), a tint, a rust streak under each clamp, sometimes a valve and a climbing or dropping elbow.
static func _run(rng: RandomNumberGenerator, at: Vector2, d: Vector2i, yaw: float, wall_h: float, cell: float) -> Dictionary:
	var line := RandomNumberGenerator.new()
	line.seed = hash([absi(d.x), at.x if d.x != 0 else at.y, wall_h])
	var run := {"at": at, "d": d, "yaw": yaw, "wall_h": wall_h, "len": cell - 0.12, "bore": PIPE_BORES[line.randi() % PIPE_BORES.size()],
		"y": line.randf_range(0.7, wall_h - 0.9), "tint": PIPE.lerp(RUST, rng.randf() * 0.35) * rng.randf_range(0.8, 1.1)}
	run["streak"] = [rng.randf_range(0.5, 1.4), rng.randf_range(0.5, 1.4)]
	run["valve"] = rng.randf() < 0.4
	run["elbow"] = rng.randf() < 0.35
	if run["elbow"]:
		run["up"] = rng.randf() < 0.5
		run["side"] = 1.15 if rng.randf() < 0.5 else -1.15
	return run


## The procedural look of a run: the pipe, flanges at the joints, two clamps with stand-offs to the wall, sometimes a valve and an elbow.
static func _run_prims(out: Array[Dictionary], r: Dictionary) -> void:
	var d: Vector2i = r["d"]
	var yaw: float = r["yaw"]
	var bore: float = r["bore"]
	var y: float = r["y"]
	var tint: Color = r["tint"]
	var depth := 0.05 + bore * 0.65   # the flanges (1.3 x bore) clear the wall by 0.05 in
	var s := Vector2(-d.y, d.x)
	var mid: Vector2 = r["at"] - Vector2(d) * depth
	out.append(_prop("cyl", mid, yaw, Vector3(bore, r["len"], bore), y, tint, true))
	for e: float in [-1.43, 1.43]:
		out.append(_prop("cyl", mid + s * e, yaw, Vector3(bore * 1.3, 0.1, bore * 1.3), y, RUST * 0.8, true))
	for e: float in [-0.9, 0.9]:
		out.append(_prop("cyl", mid + s * e, yaw, Vector3(bore * 1.15, 0.1, bore * 1.15), y, STEEL, true))
		out.append(_prop("box", r["at"] - Vector2(d) * depth * 0.5 + s * e, yaw, Vector3(0.1, bore * 0.5, depth), y, STEEL))
	if r["valve"]:   # a valve: body, stem, red handwheel
		out.append(_prop("cyl", mid, yaw, Vector3(bore * 1.4, 0.3, bore * 1.4), y, STEEL, true))
		out.append(_prop("cyl", mid, yaw, Vector3(0.07, 0.4, 0.07), y + bore * 0.85 + 0.2, STEEL))
		out.append(_prop("ring", mid, yaw, Vector3.ONE * 0.42, y + bore * 0.85 + 0.42, Color(0.55, 0.12, 0.08)))
	if r["elbow"]:
		var top: float = r["wall_h"] - 0.1 if r["up"] else 0.04
		var end := mid + s * float(r["side"])
		out.append(_prop("ball", end, yaw, Vector3.ONE * bore * 1.3, y, tint))
		out.append(_prop("cyl", end, yaw, Vector3(bore, absf(top - y), bore), (top + y) * 0.5, tint))


## A rust streak under each clamp (both looks).
static func _run_streaks(out: Array[Dictionary], r: Dictionary) -> void:
	var d: Vector2i = r["d"]
	for i in 2:
		var e := -0.9 + 1.8 * i
		var streak: float = r["streak"][i]
		out.append(_prop("box", r["at"] - Vector2(d) * 0.006 + Vector2(-d.y, d.x) * e, r["yaw"], Vector3(0.12, streak, 0.012), r["y"] - r["bore"] * 0.6 - streak * 0.5, RUST * 0.7))


## The kit look of a run: the modules stand KIT_WALL_RATIO x bore off the wall, +x along the run. A neighbour run on the same line (same bore and
## height) is joined by ONE flange on the cell boundary; an end with none gets an elbow whose outlet and collar sit on the wall (the other end of
## the elbow is the pipe's, so the pipe stops short of it). The elbow stays a collar's radius inside the cell edge, so the collar never hangs over the end of a wall.
static func _run_kit(out: Array[Dictionary], r: Dictionary, key: Vector4i, runs: Dictionary) -> void:
	var d: Vector2i = r["d"]
	var sc: float = float(r["bore"]) / KIT_BORE_IN
	var ax := Vector2(d.y, -d.x)   # the modules' +x on the board
	var mid: Vector2 = r["at"] - Vector2(d) * KIT_WALL_RATIO * float(r["bore"])
	var basis := Basis(Vector3.UP, r["yaw"])
	var tint: Color = r["tint"] * 1.2
	var span := Vector2(-1.5, 1.5)   # the pipe's ends along the run
	for e in [-1, 1]:
		var nb := Vector4i(key.x + int(ax.x) * e, key.y + int(ax.y) * e, d.x, d.y)
		if runs.has(nb) and is_equal_approx(runs[nb]["bore"], r["bore"]) and is_equal_approx(runs[nb]["y"], r["y"]):
			if e == 1:
				out.append(_kit("flange", mid + ax * 1.5, basis, Vector3.ONE * sc, r["y"], Color.WHITE))
			continue
		var corner: float = (1.5 - COLLAR_IN * sc) * e   # where the pipe's axis and the outlet's axis meet
		out.append(_kit("elbow", mid + ax * corner, basis if e == 1 else basis * Basis(Vector3.BACK, PI), Vector3.ONE * sc, r["y"], tint))
		span[(e + 1) / 2] = corner - KIT_WALL_IN * sc * e
	out.append(_kit("pipe", mid + ax * (span.x + span.y) * 0.5, basis, Vector3((span.y - span.x) / 3.0, sc, sc), r["y"], tint))
	for e: float in [-0.9, 0.9]:
		out.append(_kit("bracket", mid + ax * e, basis, Vector3.ONE * sc, r["y"], Color.WHITE))
	if r["valve"]:
		out.append(_kit("valve", mid, basis, Vector3.ONE * sc, r["y"], Color.WHITE))


static func _kit(module: String, pos: Vector2, basis: Basis, scale: Vector3, y: float, colour: Color) -> Dictionary:
	return {"shape": module, "xf": Transform3D(basis * Basis.from_scale(scale), Vector3(pos.x, y, pos.y) * INCHES_TO_METERS), "colour": colour}


## A wall lamp: back plate, bracket arm, hood, a cage of four bars round the emissive glass, and a cable up the wall. Reaches 0.7 in off the wall.
## The kit look: the caged lamp module, the bulb (still the emissive primitive), a junction box 0.9 in below it and a conduit that joins the two.
static func _lamp(out: Array[Dictionary], at: Vector2, d: Vector2i, yaw: float, y: float, wall_h: float, kit := false) -> void:
	if kit:
		var basis := Basis(Vector3.UP, yaw)
		var box_y := y - 0.9
		var from := box_y + 0.34   # the box's conduit stub ends here, the lamp's back plate starts 0.25 below its centre
		var on_wall := at - Vector2(d) * 0.001   # (a hair inside the lamp's own cell, not on the boundary)
		out.append(_kit("lamp_caged", on_wall, basis, Vector3.ONE, y, Color.WHITE))
		out.append(_kit("junction_box", on_wall, basis, Vector3.ONE, box_y, Color.WHITE))
		out.append(_kit("pipe", at - Vector2(d) * 0.03, basis * Basis(Vector3.BACK, PI * 0.5), Vector3((y - 0.25 - from) / 3.0, 0.147, 0.147), (from + y - 0.25) * 0.5, Color(0.5, 0.5, 0.52)))
		out.append(_prop("bulb", at - Vector2(d) * 0.47, yaw, Vector3(0.24, 0.34, 0.24), y, SODIUM))
		return
	var s := Vector2(-d.y, d.x)
	var hub := at - Vector2(d) * 0.47
	out.append(_prop("box", at - Vector2(d) * 0.03, yaw, Vector3(0.5, 0.55, 0.06), y, STEEL))
	out.append(_prop("box", at - Vector2(d) * 0.25, yaw, Vector3(0.1, 0.1, 0.42), y + 0.15, STEEL))
	out.append(_prop("box", hub, yaw, Vector3(0.46, 0.04, 0.46), y + 0.24, STEEL))
	out.append(_prop("box", hub, yaw, Vector3(0.4, 0.03, 0.4), y - 0.2, STEEL))
	for e: float in [-0.17, 0.17]:
		for f: float in [-0.17, 0.17]:
			out.append(_prop("box", hub - Vector2(d) * f + s * e, yaw, Vector3(0.035, 0.44, 0.035), y + 0.02, STEEL))
	out.append(_prop("bulb", hub, yaw, Vector3(0.24, 0.34, 0.24), y, SODIUM))
	out.append(_prop("cyl", at - Vector2(d) * 0.05, yaw, Vector3(0.04, wall_h - y - 0.3, 0.04), (wall_h + y + 0.3) * 0.5, STEEL))


## One prop: `size` inches (a cylinder: x = diameter, y = height, z = diameter) at `pos` inches, centre height `y`; `lying` turns a
## cylinder onto its side along the wall.
static func _prop(shape: String, pos: Vector2, yaw: float, size: Vector3, y: float, colour: Color, lying := false) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw)
	if lying:
		basis = basis * Basis(Vector3.BACK, PI * 0.5)   # the cylinder's axis runs along the wall
	return {"shape": shape, "xf": Transform3D(basis * Basis.from_scale(size * INCHES_TO_METERS), Vector3(pos.x, y, pos.y) * INCHES_TO_METERS), "colour": colour}


## One MultiMesh per shape (so the whole kit is three draw calls) and at most MAX_LIGHTS lamps, each as a plain omni light and a spot cone (only one of them shows).
func build(layout: Dictionary, kit: BoardgenKit = null) -> void:
	var use_kit := kit != null and kit.usable(KIT_MODULES)
	var props := plan(layout, use_kit)
	if use_kit:   # one MultiMesh per module
		for module in KIT_MODULES:
			BoardgenKit.add_multimesh(self, module, kit.mesh_or(module), props.filter(func(p: Dictionary) -> bool: return p["shape"] == module), module == "pipe")   # only the pipes throw a shadow (every shadow cascade draws a mesh again)
	for shape in ["box", "cyl", "bulb", "ball", "ring"]:
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
	var lamps := props.filter(func(p: Dictionary) -> bool: return p["shape"] == "light")
	_shadowed = shadow_lamps(lamps, SHADOW_LAMPS)
	for l in lamps:
		var light := OmniLight3D.new()
		light.position = l["xf"].origin
		light.light_color = SODIUM
		light.light_energy = 0.6
		light.omni_range = LAMP_RANGE_IN * INCHES_TO_METERS
		light.distance_fade_enabled = true
		light.distance_fade_begin = 2.5
		light.distance_fade_length = 1.0
		add_child(light)
		_omnis.append(light)
		var spot := SpotLight3D.new()
		spot.transform = Transform3D(spot_basis(l["out"]), l["xf"].origin)
		spot.light_color = LAMP_COLOUR
		spot.light_energy = 0.3
		spot.spot_range = LAMP_RANGE_IN * INCHES_TO_METERS
		spot.spot_angle = 80.0
		spot.spot_attenuation = 2.0
		spot.spot_angle_attenuation = 2.0   # the cone fades out towards its edge instead of cutting
		spot.shadow_blur = 1.5
		spot.shadow_bias = 0.01
		spot.shadow_normal_bias = 1.5
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 2.5
		spot.distance_fade_length = 1.0
		add_child(spot)
		_spots.append(spot)
	if is_inside_tree():
		_on_settings_applied("")
	else:
		apply_detail(false)   # _ready follows the preset once the board is in the tree


func _ready() -> void:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:
		graphics.settings_applied.connect(_on_settings_applied)
	_on_settings_applied("")


func _exit_tree() -> void:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null and graphics.settings_applied.is_connected(_on_settings_applied):
		graphics.settings_applied.disconnect(_on_settings_applied)


func _on_settings_applied(_preset_name: String) -> void:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:
		apply_detail(BoardgenGreybox.detail_for(int(graphics.current_preset), RenderingServer.get_current_rendering_method() == "gl_compatibility"))


## The finer look (Medium up): spot cones with shadows on the lamps nearest the board centre. Off (Performance / Low, Compatibility):
## the plain omni lamps, unchanged.
func apply_detail(on: bool) -> void:
	for i in _spots.size():
		_omnis[i].visible = not on
		_spots[i].visible = on
		_spots[i].shadow_enabled = on and _shadowed.has(i)


## A lamp's cone: down, leaning a little away from the wall it hangs on (`out` = the wall's outward direction, board plane).
static func spot_basis(out: Vector2) -> Basis:
	return Basis.looking_at(Vector3(out.x * 0.35, -1.0, out.y * 0.35).normalized(), Vector3.UP)


## Indices (into `lamps`) of the `n` lamps nearest the board centre: the ones that get a shadow.
static func shadow_lamps(lamps: Array, n: int) -> Array[int]:
	var order: Array[int] = []
	for i in lamps.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return Vector2(lamps[a]["xf"].origin.x, lamps[a]["xf"].origin.z).length() < Vector2(lamps[b]["xf"].origin.x, lamps[b]["xf"].origin.z).length())
	return order.slice(0, mini(n, order.size()))


func _unit_mesh(shape: String) -> Mesh:
	var mesh: PrimitiveMesh = BoxMesh.new()
	if shape == "cyl":
		var cyl := CylinderMesh.new()
		cyl.height = 1.0   # radius 0.5 is the default: a unit cylinder
		cyl.radial_segments = 10
		mesh = cyl
	elif shape == "ball" or shape == "bulb":   # an ellipsoid once the instance scales it
		var ball := SphereMesh.new()
		ball.radial_segments = 12
		ball.rings = 6
		mesh = ball
	elif shape == "ring":   # a handwheel: a torus lying flat
		var ring := TorusMesh.new()
		ring.inner_radius = 0.36
		ring.outer_radius = 0.5
		ring.rings = 14
		ring.ring_segments = 5
		mesh = ring
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
