extends Node3D
## Ultra's world follows the table presentation lifecycle and the atmosphere buttons.
const Biomes := preload("res://scripts/visual/reference_biomes.gd")
const Materials = preload("res://scripts/visual/reference_materials.gd")
const TreePass = preload("res://scripts/visual/table_tree_pass.gd")
const Props = preload("res://scripts/visual/reference_props.gd")

var _world_scale := 1.0
var _world_trees_ready := false

var _main: Node
var _profile: Dictionary
var _material: ShaderMaterial
var _state: RenderState
var _clouds: SpotLight3D
static var _cloud_mask: ImageTexture

## Light islands: the cloud spot sits this far from the table along the sun, and the sun keeps this share of its energy.
const CLOUD_DISTANCE_M := 4.5
const CLOUD_SUN_SCALE := 0.4
const CLOUD_ENERGY := 10.0
## Sunset tune (maintainer verdict S4_mild_nofog): a milder spot, no spot volumetric fog, so the low sun does not wash
## the ruins white or turn the haze milky.
const CLOUD_SUN_SCALE_SUNSET := 0.45
const CLOUD_ENERGY_SUNSET := 6.0

func setup(main: Node, profile: Dictionary) -> void:
	_main = main
	_profile = profile
	_state = main.render_state
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/visual/table_world_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _material
	_state.set_layer("world", {"sky":sky, "sdfgi_read_sky_light":true, "sdfgi_energy":0.75})
	_clouds = make_cloud_light()
	add_child(_clouds)
	main.atmosphere_controller.atmosphere_changed.connect(_on_mood)
	_on_mood(main.atmosphere_controller.get_current_atmosphere())
	_build_landscape()

static func sky_values(profile: Dictionary, mood: String) -> Dictionary:
	return {"world_mood":["Sunset","Day","Overcast","Night","Rain"].find(mood),
		"biome_tint":profile.fog_color / Biomes.GRASSLAND.fog_color}

func _on_mood(mood: String) -> void:
	var values := sky_values(_profile, mood)
	for key in values:
		_material.set_shader_parameter(key,values[key])
	_update_clouds(mood)

## Broken-cloud sunlight on a sunny day (GraphicsSettings.cloud_light_enabled): a spot along the sun projects a soft
## cloud mask and the sun dims, so the gaps read as light islands and the rest as cloud shadow.
## Per-mood island parameters: Day is the approved look; Sunset is the S4 tune (milder spot, no spot volumetric fog).
static func cloud_params(mood: String) -> Dictionary:
	var sunset := mood == "Sunset"
	return {"energy": CLOUD_ENERGY_SUNSET if sunset else CLOUD_ENERGY,
		"sun_scale": CLOUD_SUN_SCALE_SUNSET if sunset else CLOUD_SUN_SCALE,
		"fog": 0.0 if sunset else 1.0}

func _update_clouds(mood: String) -> void:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	var on: bool = graphics != null and graphics.cloud_light_enabled(int(graphics.current_preset), mood)
	_clouds.visible = on
	set_process(on)
	if on:
		var params := cloud_params(mood)
		_clouds.light_energy = params["energy"]
		_clouds.light_volumetric_fog_energy = params["fog"]
		_set_sun_scale(params["sun_scale"])
	else:
		_set_sun_scale(1.0)

func _set_sun_scale(scale: float) -> void:
	var lighting: Object = _main.get("lighting_controller") if _main != null else null
	if lighting != null and lighting.has_method("set_sun_scale"):
		lighting.set_sun_scale(scale)

## The spot follows the sun (a mood blend turns it), so its shadows line up with the sun's.
func _process(_delta: float) -> void:
	var sun := _main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		return
	var to_sun := sun.global_basis.z.normalized()
	var at := to_sun * CLOUD_DISTANCE_M * _world_scale
	if not _clouds.global_position.is_equal_approx(at):
		_clouds.global_position = at
		_clouds.look_at(Vector3.ZERO, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)

## The cloud spot. The projector only shows through the light's own shadow pass, so the shadow stays on - but with no
## caster in it: the projector alone carries the islands, and a full shadow pass costs about twice as much (measured
## +1.2 ms instead of +2.3 ms at High Day). The mask is built once (FastNoiseLite image, not a NoiseTexture2D: its
## async bake raced the table materials before).
static func make_cloud_light() -> SpotLight3D:
	if _cloud_mask == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.seed = 7
		noise.frequency = 0.012
		noise.fractal_octaves = 3
		var img := noise.get_image(256, 256, false, false, true)
		img.convert(Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var v := smoothstep(0.42, 0.58, img.get_pixel(x, y).r)
				img.set_pixel(x, y, Color(v, v, v))
		_cloud_mask = ImageTexture.create_from_image(img)
	var spot := SpotLight3D.new()
	spot.name = "CloudLight"
	spot.light_projector = _cloud_mask
	spot.light_color = Color(1.0, 0.95, 0.84)
	spot.light_energy = 10.0
	spot.shadow_enabled = true
	spot.shadow_caster_mask = 0   # no caster shadows: the projector alone carries the islands, at half the cost
	spot.spot_range = 12.0
	spot.spot_angle = 24.0
	spot.spot_attenuation = 0.0
	spot.visible = false
	return spot

func _exit_tree() -> void:
	if _state != null:
		_state.set_layer("world", {})
	_set_sun_scale(1.0)

func _build_landscape() -> void:
	var size_m: Vector2 = _main.get_node("Table").table_size * 0.3048
	_world_scale = maxf(1.0, maxf(size_m.x,size_m.y) / 1.8288)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const GRID := 100
	const CELL := 0.36
	for z in GRID:
		for x in GRID:
			var p := Vector2(x - GRID * 0.5, z - GRID * 0.5) * CELL
			for offset: Vector2 in [Vector2.ZERO, Vector2(CELL,0), Vector2(0,CELL), Vector2(CELL,0), Vector2(CELL,CELL), Vector2(0,CELL)]:
				var q := (p + offset) * _world_scale
				surface.add_vertex(Vector3(q.x, _height(q), q.y))
	surface.generate_normals()
	var ground := MeshInstance3D.new()
	ground.name = "WorldGround"
	ground.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/table_world_ground.gdshader")
	material.set_shader_parameter("grass_tex", Materials.texture(_profile.textures.meadow))
	material.set_shader_parameter("earth_tex", Materials.texture("res://assets/terrain/reference/earth.webp" if _profile.name == "grassland" else _profile.textures.earth))
	if _profile.name != "grassland":
		material.set_shader_parameter("grass_tint", _profile.fog_color * 0.85)
		material.set_shader_parameter("soil_tint", _profile.fog_color * 0.65)
	ground.material_override = material
	ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(ground)
	# Seat the unchanged board on a dark stone display plinth, down to the clearing floor.
	var plinth := MeshInstance3D.new()
	plinth.name = "WorldPlinth"
	var box := BoxMesh.new()
	box.size = Vector3(size_m.x + 0.0612,0.29,size_m.y + 0.0608)
	plinth.mesh = box
	plinth.position.y = -0.195
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.055,0.06,0.052)
	stone.roughness = 0.78
	plinth.material_override = stone
	add_child(plinth)
	var presenter: Node = _main.get("_table_biome_presenter")
	if presenter != null:
		presenter.trees_dressed.connect(_dress_world_trees)
	_dress_world_trees(_profile.name)

func _dress_world_trees(biome: String) -> void:
	if _world_trees_ready or biome != _profile.name or not TreePass._sources.has(biome):
		return
	_world_trees_ready = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5102026
	var sources: Dictionary = TreePass._sources[biome]
	if biome == "grassland" and sources.get("oak_scenes", []).is_empty():
		return
	var props := Props.new()
	var forest := preload("res://scripts/visual/reference_biome_forest.gd").new()
	forest._main = _main
	forest.use_sources(biome, sources.get("hero"), sources.get("natives", {}))
	props._tree_variants.assign(sources.get("oak_scenes", []))
	props._tree_bounds.assign(sources.get("oak_bounds", []))
	# Groves along ridges, with a clear valley behind the battle; use the production biome tree LODs.
	for i in 84:
		var grove := i / 7
		var angle := float(grove) * TAU / 12.0 + 0.23
		var radius := 5.0 + float(grove % 3)*2.4
		var p := Vector2(cos(angle),sin(angle))*radius + Vector2(rng.randfn(0,0.7),rng.randfn(0,0.7))
		p *= _world_scale
		var height := rng.randf_range(0.85,1.75)
		var tree: Node3D = props.tree_instance(height,i,_height(p)-0.01) if biome == "grassland" else forest._instance(2,i,height,_height(p)-0.01)
		if tree == null:
			continue
		tree.position.x = p.x
		tree.position.z = p.y
		add_child(tree)
		_no_world_gi(tree)
	props.free()
	forest.free()

func _no_world_gi(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children():
		_no_world_gi(child)

func _height(p: Vector2) -> float:
	p /= _world_scale
	var distance := p.length()
	var ridge := sin(p.x*0.38 + sin(p.y*0.19)*1.8) * 0.5 + 0.5
	var detail := sin(p.x*1.2+p.y*0.46)*sin(p.y*0.72)*0.10
	return -0.34 + smoothstep(2.2,8.5,distance) * (0.65 + ridge*2.3 + detail)
