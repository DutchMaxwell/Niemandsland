class_name DiceVisual
extends RefCounted
## Procedural visuals of the physics dice and their tray (uidice2, 23.09.2026). Everything is made in
## code — no external meshes or textures, so no licence questions: a rounded-cube mesh whose six faces
## map into a 3 x 2 pip atlas, that atlas plus its engraving normal map, one die material per
## DiceLook, and the tray (felt floor with a soft light pool, a dark rim with a gold lip, soft light
## and contact shadows). Visual only: the RigidBody, its BoxShape3D, the wall colliders, the roll
## impulses and DiceD6.top_face() never see any of this.

const ATLAS_COLS := 3
const ATLAS_ROWS := 2
const CELL_PX := 128
const PIP_RADIUS := 0.10          # cell units; < 0.11 so the six-face pips (0.22 apart) never touch
const PIP_SOFT := 0.012           # anti-aliased pip rim, in cell units
const PIP_DEPTH := 0.45           # dimple steepness of the engraving normal map
const EDGE_STEPS := 4             # segments across one rounded edge
const BODY_SHADER := preload("res://shaders/dice_body.gdshader")

# Tray (house style): dark teal felt, a dark rim with a gold lip, one soft key light with shadows.
const FELT := Color(0.085, 0.165, 0.175)   # mid-dark teal: dark dice still separate from it
const FELT_PX := 256
const RIM_WIDTH := 0.9
const RIM_HEIGHT := 0.7
const LIP_WIDTH := 0.14
const RIM_COLOR := Color(0.016, 0.022, 0.027)

static var _meshes: Dictionary = {}      # "edge|radius" -> ArrayMesh
static var _materials: Dictionary = {}   # look id -> ShaderMaterial
static var _atlas: Image = null
static var _atlas_tex: ImageTexture = null
static var _normal_tex: ImageTexture = null
static var _felt_tex: ImageTexture = null


# ===== Die =====

## A die's visible body for `look`: the shared rounded mesh + the look's shared material. The die's
## colours (its colour tag) go in per instance: set_instance_shader_parameter body_color / pip_color.
static func body_instance(edge: float, look: DiceLook) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "DieBody"
	mi.mesh = body_mesh(edge, look.edge_radius)
	mi.material_override = body_material(look)
	return mi


## The atlas cell (column, row) of a face value: 1 2 3 on the top row, 4 5 6 below.
static func cell_of(value: int) -> Vector2i:
	return Vector2i((value - 1) % ATLAS_COLS, int((value - 1) / float(ATLAS_COLS)))


## The two in-face axes of a face (image x to the right, image y down, seen from outside the die).
static func face_axes(value: int) -> Array[Vector3]:
	match value:
		1:
			return [Vector3.RIGHT, Vector3.BACK]
		6:
			return [Vector3.RIGHT, Vector3.FORWARD]
		2:
			return [Vector3.FORWARD, Vector3.DOWN]
		5:
			return [Vector3.BACK, Vector3.DOWN]
		3:
			return [Vector3.RIGHT, Vector3.DOWN]
		_:
			return [Vector3.LEFT, Vector3.DOWN]


## A cube of edge `edge` with rounded edges and corners (radius = radius_fraction * edge). Each face
## is its own grid, dense only across the rounded band, UV-mapped into its atlas cell.
static func body_mesh(edge: float, radius_fraction: float) -> ArrayMesh:
	var key := "%.4f|%.4f" % [edge, radius_fraction]
	if _meshes.has(key):
		return _meshes[key]
	var h := edge * 0.5
	var r := clampf(radius_fraction, 0.0, 0.45) * edge
	var inner := Vector3.ONE * (h - r)
	var steps := _grid_steps(clampf(radius_fraction, 0.0, 0.45))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for value: int in range(1, 7):
		var n: Vector3 = DiceD6.FACE_NORMALS[value]
		var axes := face_axes(value)
		var cell := Vector2(cell_of(value))
		var pos: Array[Vector3] = []
		var nrm: Array[Vector3] = []
		var uv: Array[Vector2] = []
		for j: int in steps.size():
			for i: int in steps.size():
				var p := n * h + axes[0] * (steps[i] * edge - h) + axes[1] * (steps[j] * edge - h)
				var c := p.clamp(-inner, inner)
				var d := (p - c).normalized() if r > 0.0 else n
				pos.append(c + d * r if r > 0.0 else p)
				nrm.append(d)
				uv.append((cell + Vector2(steps[i], steps[j])) / Vector2(ATLAS_COLS, ATLAS_ROWS))
		# Godot's front faces wind clockwise; the grid runs along axes[0] then axes[1].
		var flip := axes[0].cross(axes[1]).dot(n) > 0.0
		var w := steps.size()
		for j: int in w - 1:
			for i: int in w - 1:
				var a := j * w + i
				var quad: Array[int] = [a, a + 1, a + w + 1, a, a + w + 1, a + w]
				if flip:
					quad = [a, a + w + 1, a + 1, a, a + w, a + w + 1]
				for k: int in quad:
					st.set_normal(nrm[k])
					st.set_uv(uv[k])
					st.add_vertex(pos[k])
	st.generate_tangents()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## The material of one look (shared by every die of that look).
static func body_material(look: DiceLook) -> ShaderMaterial:
	if _materials.has(look.id):
		return _materials[look.id]
	_ensure_atlas()
	var m := ShaderMaterial.new()
	m.shader = BODY_SHADER
	m.set_shader_parameter(&"pip_atlas", _atlas_tex)
	m.set_shader_parameter(&"pip_normal", _normal_tex)
	m.set_shader_parameter(&"roughness", look.roughness)
	m.set_shader_parameter(&"metallic", look.metallic)
	m.set_shader_parameter(&"clearcoat", look.clearcoat)
	m.set_shader_parameter(&"rim", look.rim)
	m.set_shader_parameter(&"pip_depth", look.pip_depth)
	m.set_shader_parameter(&"pip_metallic", look.pip_metallic)
	m.set_shader_parameter(&"pip_roughness", look.pip_roughness)
	_materials[look.id] = m
	return m


## The pip mask atlas (R = pip, 0..1) every die face samples. Tests count its pips.
static func pip_atlas_image() -> Image:
	_ensure_atlas()
	return _atlas


static func _grid_steps(radius_fraction: float) -> Array[float]:
	var s: Array[float] = []
	if radius_fraction <= 0.0:
		s.assign([0.0, 1.0])
		return s
	for k: int in EDGE_STEPS + 1:
		s.append(radius_fraction * k / float(EDGE_STEPS))
	for k: int in EDGE_STEPS + 1:
		s.append(1.0 - radius_fraction + radius_fraction * k / float(EDGE_STEPS))
	return s


## Draws the six faces' pips (DieFaceIcon.PIP_LAYOUT, the tally icons' own layout) into the mask
## atlas and the matching engraving normals: each pip a shallow spherical dimple.
static func _ensure_atlas() -> void:
	if _atlas != null:
		return
	var w := CELL_PX * ATLAS_COLS
	var ht := CELL_PX * ATLAS_ROWS
	_atlas = Image.create(w, ht, false, Image.FORMAT_RGBA8)
	_atlas.fill(Color(0, 0, 0, 1))
	var normals := Image.create(w, ht, false, Image.FORMAT_RGBA8)
	normals.fill(Color(0.5, 0.5, 1.0, 1.0))
	var radius := PIP_RADIUS * CELL_PX
	var soft := PIP_SOFT * CELL_PX
	for value: int in range(1, 7):
		var origin := Vector2(cell_of(value)) * CELL_PX
		for centre_uv: Vector2 in DieFaceIcon.PIP_LAYOUT[value]:
			var centre := origin + centre_uv * CELL_PX
			var reach := int(ceil(radius + soft)) + 1
			for y: int in range(int(centre.y) - reach, int(centre.y) + reach + 1):
				for x: int in range(int(centre.x) - reach, int(centre.x) + reach + 1):
					var off := Vector2(x + 0.5, y + 0.5) - centre
					var d := off.length()
					var m := 1.0 - smoothstep(radius - soft, radius + soft, d)
					if m <= 0.0:
						continue
					_atlas.set_pixel(x, y, Color(maxf(m, _atlas.get_pixel(x, y).r), 0, 0, 1))
					# Concave cap: the wall rises away from the centre, so its normal leans back toward
					# the centre (x right, y up in the map); the soft edge blends back to flat.
					var q := clampf(d / radius, 0.0, 0.95)
					var slope := PIP_DEPTH * q / sqrt(1.0 - q * q)
					var dir := off.normalized() if d > 0.0 else Vector2.ZERO
					var nn := Vector3(-dir.x * slope, dir.y * slope, 1.0).normalized().lerp(Vector3(0, 0, 1), 1.0 - m).normalized()
					normals.set_pixel(x, y, Color(nn.x * 0.5 + 0.5, nn.y * 0.5 + 0.5, nn.z * 0.5 + 0.5, 1.0))
	_atlas.generate_mipmaps()
	normals.generate_mipmaps()
	_atlas_tex = ImageTexture.create_from_image(_atlas)
	_normal_tex = ImageTexture.create_from_image(normals)


# ===== Tray =====

## The visible tray around the (invisible, unchanged) wall colliders: felt floor, a rim whose inner
## face sits exactly on the colliders' inner face, and a thin gold lip on the rim's inner top edge.
## Returns the tray's outer half-extents (x, z) so the camera can frame it.
static func add_tray(parent: Node3D, roller_size: Vector3, wall_thickness: float) -> Vector2:
	var in_x := roller_size.x * 0.5 - wall_thickness * 0.5
	var in_z := roller_size.z * 0.5 - wall_thickness * 0.5
	var out_x := in_x + RIM_WIDTH
	var out_z := in_z + RIM_WIDTH

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "TrayFelt"
	var plane := PlaneMesh.new()
	plane.size = Vector2(in_x * 2.0, in_z * 2.0)
	var felt := StandardMaterial3D.new()
	felt.albedo_texture = _felt_texture()
	felt.roughness = 1.0
	plane.material = felt
	floor_mesh.mesh = plane
	parent.add_child(floor_mesh)

	var rim := StandardMaterial3D.new()
	rim.albedo_color = RIM_COLOR
	rim.roughness = 0.75
	rim.metallic_specular = 0.15   # no grey sheen from the sky on the dark rim
	var lip := StandardMaterial3D.new()
	lip.albedo_color = HouseStyle.GOLD
	lip.metallic = 0.7
	lip.roughness = 0.35
	# Two long sides along x, two short ones along z; each a rim bar plus its gold lip.
	for sgn: float in [-1.0, 1.0]:
		_add_bar(parent, Vector3(out_x * 2.0, RIM_HEIGHT, RIM_WIDTH), Vector3(0, RIM_HEIGHT * 0.5, sgn * (in_z + RIM_WIDTH * 0.5)), rim)
		_add_bar(parent, Vector3(RIM_WIDTH, RIM_HEIGHT, in_z * 2.0), Vector3(sgn * (in_x + RIM_WIDTH * 0.5), RIM_HEIGHT * 0.5, 0), rim)
		_add_bar(parent, Vector3(in_x * 2.0 + LIP_WIDTH * 2.0, 0.04, LIP_WIDTH), Vector3(0, RIM_HEIGHT + 0.02, sgn * (in_z + LIP_WIDTH * 0.5)), lip)
		_add_bar(parent, Vector3(LIP_WIDTH, 0.04, in_z * 2.0), Vector3(sgn * (in_x + LIP_WIDTH * 0.5), RIM_HEIGHT + 0.02, 0), lip)
	return Vector2(out_x, out_z)


## Soft light for the tray world: one key light with soft contact shadows, a weak cool fill, and a
## dim environment so metal and lacquer have something to reflect. Background stays transparent.
static func add_tray_lighting(parent: Node3D) -> DirectionalLight3D:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-62, -35, 0)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.shadow_opacity = 0.85
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 80.0
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-50, 145, 0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.75, 0.88, 0.9)
	parent.add_child(fill)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.62, 0.66)
	sky_mat.sky_horizon_color = Color(0.36, 0.40, 0.42)
	sky_mat.ground_horizon_color = Color(0.20, 0.22, 0.22)
	sky_mat.ground_bottom_color = Color(0.08, 0.09, 0.09)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.name = "TrayEnvironment"
	we.environment = env
	parent.add_child(we)
	return key


static func _add_bar(parent: Node3D, box_size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)


## Felt: fine fibre noise over the house teal, darker toward the rim (a soft light pool).
static func _felt_texture() -> ImageTexture:
	if _felt_tex != null:
		return _felt_tex
	var noise := FastNoiseLite.new()
	noise.seed = 23
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var grain := noise.get_image(FELT_PX, FELT_PX)
	var img := Image.create(FELT_PX, FELT_PX, false, Image.FORMAT_RGBA8)
	var half := FELT_PX * 0.5
	for y: int in FELT_PX:
		for x: int in FELT_PX:
			var g := grain.get_pixel(x, y).r
			var edge := maxf(absf(x - half), absf(y - half)) / half
			var pool := 1.0 - 0.38 * smoothstep(0.45, 1.0, edge)
			var c := FELT * (0.86 + 0.28 * g) * pool
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	_felt_tex = ImageTexture.create_from_image(img)
	return _felt_tex
