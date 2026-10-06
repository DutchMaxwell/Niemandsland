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

func setup(main: Node, profile: Dictionary) -> void:
	_main = main
	_profile = profile
	_state = main.render_state
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/visual/table_world_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _material
	_state.set_layer("world", {"sky":sky, "sdfgi_read_sky_light":true, "sdfgi_energy":0.75})
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

func _exit_tree() -> void:
	if _state != null:
		_state.set_layer("world", {})

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
