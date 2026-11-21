class_name BoardgenSteam
extends Node3D
## A few steam plumes from wall vents on a seeded boardgen board: each vent is a small hood and a dark grille on a tier wall, and a plume
## of soft noise rises from it. Hoods are two boxes per vent in one MultiMesh, plumes are one quad per vent in another (billboarded round the
## vertical in the shader): two draw calls however many vents. VISUAL ONLY: no collider, no shadow, nothing the sight lines read. A vent sits
## on a wall face with nothing else on it, outside the deployment bands and off ladder feet, and its hood stays inside the wall strip.

const INCHES_TO_METERS := 0.0254
const MAX_VENTS := 5
const MIN_GAP_IN := 12.0
const VENT_Y_IN := 1.7   # the hood's mid-height over the floor
const HOOD_IN := Vector3(1.0, 0.6, 0.3)   # width, height, depth off the wall
const PROP_CLEAR_IN := 1.4
const PUFFS := 6   # sprites per vent, each on its own cycle
const SLATS := 3
const LAMP_SLOTS := 8
const SHADER := preload("res://shaders/tiefwerk_steam.gdshader")
const STEEL := Color(0.20, 0.21, 0.23)
const SLIT := Color(0.03, 0.03, 0.03)
const SLAT := Color(0.34, 0.35, 0.37)

var _plume_mat: ShaderMaterial


## The vents: {cell: Vector2i (the floor cell), d: Vector2i (floor -> wall), at: Vector2 (on the wall plane, inches off the board centre), phase}.
static func vents(layout: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) * 2654435761 + 331
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var origin := Vector2(nx, nz) * cell * -0.5
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	var sites: Array[Dictionary] = []
	var landmarks: Array = layout.get("landmarks", [])   # tanks and cranes stand in front of a wall: no vent behind them
	for z in nz:
		for x in nx:
			var me: Dictionary = cells[z * nx + x]
			if me["level"] > 0 or me["lot_kind"] == "Hazard" or feet.has(Vector2i(x, z)) or int(me.get("deploy", 0)) != 0 \
					or landmarks.any(func(l: Dictionary) -> bool: return x >= l["x"] - 1 and z >= l["z"] - 1 and x <= l["x"] + l["w"] and z <= l["z"] + l["h"]):
				continue
			for d in BoardgenProps.DIRS:
				var o := Vector2i(x, z) + d
				if o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz and cells[o.y * nx + o.x]["level"] > 0:
					var along := Vector2(-d.y, d.x) * rng.randf_range(-0.8, 0.8)
					sites.append({"cell": Vector2i(x, z), "d": d, "at": origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * cell + Vector2(d) * cell * 0.5 + along})
	var props := BoardgenProps.plan(layout)
	var out: Array[Dictionary] = []
	while not sites.is_empty() and out.size() < MAX_VENTS:
		var site: Dictionary = sites.pop_at(rng.randi() % sites.size())
		var clear: bool = out.all(func(v: Dictionary) -> bool: return v["at"].distance_to(site["at"]) >= MIN_GAP_IN) \
			and props.all(func(p: Dictionary) -> bool: return Vector2(p["xf"].origin.x, p["xf"].origin.z).distance_to(site["at"] * INCHES_TO_METERS) * 39.37 >= PROP_CLEAR_IN)
		if clear:
			site["phase"] = rng.randf()
			out.append(site)
	return out


func build(layout: Dictionary) -> void:
	var list := vents(layout)
	var parts := 2 + SLATS   # per vent: the hood, the dark grille and the slats across it
	var hoods := MultiMesh.new()
	hoods.transform_format = MultiMesh.TRANSFORM_3D
	hoods.use_colors = true
	hoods.mesh = BoxMesh.new()
	hoods.instance_count = list.size() * parts
	var plumes := MultiMesh.new()
	plumes.transform_format = MultiMesh.TRANSFORM_3D
	plumes.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # the shader sizes each puff and turns it to the camera
	plumes.mesh = quad
	plumes.instance_count = list.size() * PUFFS
	for i in list.size():
		var v: Dictionary = list[i]
		var d: Vector2i = v["d"]
		var basis := Basis(Vector3.UP, atan2(float(d.x), float(d.y)))   # local +z points at the wall
		for k in parts:   # the hood, the grille a hair proud of its face, the slats across the grille
			var size := HOOD_IN if k == 0 else Vector3(HOOD_IN.x * 0.8, HOOD_IN.y * 0.6, 0.04) if k == 1 else Vector3(HOOD_IN.x * 0.76, 0.04, 0.06)
			var p: Vector2 = v["at"] - Vector2(d) * (HOOD_IN.z * 0.5 if k == 0 else HOOD_IN.z + (0.01 if k == 1 else 0.03))
			var y := VENT_Y_IN + (0.0 if k < 2 else (k - 3) * HOOD_IN.y * 0.2)
			hoods.set_instance_transform(i * parts + k, Transform3D(basis * Basis.from_scale(size * INCHES_TO_METERS), Vector3(p.x, y, p.y) * INCHES_TO_METERS))
			hoods.set_instance_color(i * parts + k, STEEL if k == 0 else SLIT if k == 1 else SLAT)
		var foot: Vector2 = v["at"] - Vector2(d) * (HOOD_IN.z + 0.3)
		for k in PUFFS:
			plumes.set_instance_transform(i * PUFFS + k, Transform3D(Basis(), Vector3(foot.x, VENT_Y_IN + HOOD_IN.y * 0.5, foot.y) * INCHES_TO_METERS))
			plumes.set_instance_custom_data(i * PUFFS + k, Color(v["phase"], float(k) / PUFFS, -float(d.x), -float(d.y)))
	var hood_mat := StandardMaterial3D.new()
	hood_mat.vertex_color_use_as_albedo = true
	hood_mat.vertex_color_is_srgb = true
	hood_mat.roughness = 0.6
	hood_mat.metallic = 0.4
	_plume_mat = ShaderMaterial.new()
	_plume_mat.shader = SHADER
	var lamps := PackedVector3Array()   # the wall lamps of the board light the steam near them (a warm backlight)
	for p: Dictionary in BoardgenProps.plan(layout):
		if p["shape"] == "light" and lamps.size() < LAMP_SLOTS:
			lamps.append(p["xf"].origin)
	while lamps.size() < LAMP_SLOTS:
		lamps.append(Vector3(1000.0, 1000.0, 1000.0))
	_plume_mat.set_shader_parameter("lamps", lamps)
	for part in [["Hoods", hoods, hood_mat], ["Plumes", plumes, _plume_mat]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = part[0]
		mmi.multimesh = part[1]
		mmi.material_override = part[2]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 0.5   # the shader moves each puff well off its instance
		add_child(mmi)


## The shader reads the lamps and the puffs in world space: it is told where the board centre is.
func _enter_tree() -> void:
	if _plume_mat != null:
		_plume_mat.set_shader_parameter("board_origin", global_position)
