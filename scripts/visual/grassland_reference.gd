extends Node3D
## Opt-in art-direction reference. Uses the real board and original miniatures.
## Existing rule geometry, terrain footprints and source models remain untouched.

const TREE_BUILDER = preload("res://scripts/visual/reference_tree.gd")
const GROUND = preload("res://shaders/visual/reference_ground.gdshader")
var _main: Node
var _ground: ShaderMaterial
var _base: ShaderMaterial
var _trees: Array[ArrayMesh] = []
var _regions := PackedVector4Array()
var _angles := PackedFloat32Array()


func apply(main: Node) -> void:
	_main = main
	for i in 3:
		_trees.append(TREE_BUILDER.build(i))
	_ground = ShaderMaterial.new()
	_ground.shader = GROUND
	for texture_name in ["meadow","earth","woodland"]:
		_ground.set_shader_parameter(texture_name + "_tex",load("res://assets/terrain/reference/" + texture_name + ".webp"))
	var table: Node3D = main.get_node("Table")
	_ground.set_shader_parameter("detail_normal", table._detail_normal_tex)
	table.get_node("TableMesh").material_override = _ground
	table.get_node("GrassField").visible = false
	_base = table.get_base_top_material()
	_base.shader = GROUND
	_base.set_shader_parameter("clip_base",true)
	_base.set_shader_parameter("detail_normal", table._detail_normal_tex)
	for texture_name in ["meadow","earth","woodland"]:
		_base.set_shader_parameter(texture_name + "_tex",_ground.get_shader_parameter(texture_name + "_tex"))
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.075,0.084,0.078)
	frame.roughness = 0.86
	for child in table.get_children():
		if child is MeshInstance3D and child != table.get_node("TableMesh"):
			child.material_override = frame
	var overlay: Node3D = main.terrain_overlay
	_dress_grid_forest(overlay)
	_dress_movable_forests()
	_sync_regions()
	_build_meadow(table.table_size * 0.3048)
	_style_trays()
	apply_lighting("Day")


func apply_lighting(mood: String) -> void:
	var light: Node = _main.lighting_controller
	var evening := mood == "Sunset"
	light.set_sun_energy(1.7 if evening else 1.55)
	light.set_sun_color(Color(1,0.85,0.69) if evening else Color(1,0.97,0.89))
	light.set_sun_angles(-40.0 if evening else 65.0,28.0 if evening else 48.0)
	light.set_ambient_energy(0.28)
	light.set_ambient_color(Color(0.77,0.84,0.94))
	light.set_fill_light_energy(0.40)
	light.set_fill_light_color(Color(0.80,0.89,1.0))
	light.set_exposure(1.0)
	light.set_contrast(1.05)
	light.set_saturation(0.96)
	light.set_shadow_opacity(0.85)
	light.set_shadow_blur(1.5)
	light.set_ssao_intensity(0.65)
	light.set_glow_intensity(0.1)
	var env: Environment = _main.get_node("WorldEnvironment").environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12,0.14,0.125)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR


func _dress_grid_forest(overlay: Node3D) -> void:
	var dims: Vector2i = overlay._calculate_grid_dims(overlay.table_size_feet)
	var cell_size: float = overlay.GRID_SIZE_INCHES * overlay.INCHES_TO_METERS
	var rotation_angle := deg_to_rad(float(overlay.grid_rotation_degrees))
	for zone: Dictionary in overlay._terrain_zones(overlay.grid_cells):
		if zone.type != overlay.TerrainType.FOREST:
			continue
		var minimum := Vector2(INF,INF)
		var maximum := Vector2(-INF,-INF)
		for cell: Vector2i in zone.cells:
			var pos: Vector3 = overlay._cell_to_world(float(cell.x),float(cell.y),dims,cell_size,rotation_angle)
			minimum = minimum.min(Vector2(pos.x,pos.z))
			maximum = maximum.max(Vector2(pos.x,pos.z))
		var center := (minimum+maximum)*0.5
		var radius := (maximum-minimum)*0.5+Vector2.ONE*cell_size*0.65
		_regions.append(Vector4(center.x,center.y,radius.x,radius.y))
		_angles.append(0.0)
	var index := 0
	for obj: Dictionary in overlay._last_objects:
		if obj.get("object_type","") != "tree":
			continue
		var cell: Vector2i = obj.cell
		var offset: Vector2 = obj.offset
		var x := (cell.x-dims.x/2.0+offset.x)*cell_size
		var z := (cell.y-dims.y/2.0+offset.y)*cell_size
		var expected := Vector2(x*cos(rotation_angle)-z*sin(rotation_angle),x*sin(rotation_angle)+z*cos(rotation_angle))
		for original: Node3D in overlay._object_instances:
			if Vector2(original.position.x,original.position.z).distance_squared_to(expected)>0.000001:
				continue
			var bounds: AABB = overlay._model_space_aabb(original)
			var height := clampf(bounds.size.y,0.08,0.20)
			for child in original.get_children():
				if child is Node3D:
					child.visible = false
			var tree := MeshInstance3D.new()
			tree.name = "ReferenceCanopy"
			tree.mesh = _trees[index%3]
			tree.scale = Vector3.ONE * height
			original.add_child(tree)
			index += 1
			break
	print("REFERENCE_TREES ",index," regions=",_regions.size())


func _dress_movable_forests() -> void:
	for group in get_tree().get_nodes_in_group("terrain_group_base"):
		if group.kind != TerrainGroupBase.KIND_FOREST or group.biome_prefix != "":
			continue
		var radius: Vector2 = group.footprint_inches * 0.0254 * 0.5
		_regions.append(Vector4(group.global_position.x,group.global_position.z,radius.x,radius.y))
		_angles.append(group.global_rotation.y)
		if is_instance_valid(group._floor_mesh):
			group._floor_mesh.material_override = _ground


func _sync_regions() -> void:
	var count := mini(_regions.size(),16)
	_regions.resize(16)
	_angles.resize(16)
	for mat in [_ground,_base]:
		mat.set_shader_parameter("forest_count",count)
		mat.set_shader_parameter("forest_regions",_regions)
		mat.set_shader_parameter("forest_angles",_angles)


func _build_meadow(size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91624
	var source := SurfaceTool.new()
	source.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var angle := float(i)*2.39996
		var a := Vector3(cos(angle)*0.0007,0,sin(angle)*0.0007)
		var sideways := Vector3(cos(angle+PI*0.5),0,sin(angle+PI*0.5))*0.00035
		var tip := a+Vector3(cos(angle)*0.0014,0.004+float(i%3)*0.001,sin(angle)*0.0014)
		for p in [a-sideways,a+sideways,tip]:
			source.set_normal(Vector3.UP)
			source.set_uv(Vector2(0.5,clampf(p.y/0.006,0,1)))
			source.add_vertex(p)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	source.set_material(material)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = source.commit()
	var count := int(size.x*size.y*4800)
	mm.instance_count = count
	var accepted := 0
	for i in count:
		var point := Vector3(rng.randf_range(-size.x*0.5,size.x*0.5),0.0003,rng.randf_range(-size.y*0.5,size.y*0.5))
		var xz := Vector2(point.x,point.z)
		var cover := _surface_noise(xz*6.5)*0.65+_surface_noise(xz*18.0)*0.35
		if cover < 0.46:
			continue
		var scale_value := rng.randf_range(0.45,1.0)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value)
		mm.set_instance_transform(accepted,Transform3D(basis,point))
		mm.set_instance_color(accepted,Color(0.24,0.31,0.10).lerp(Color(0.43,0.43,0.19),rng.randf()).srgb_to_linear())
		accepted += 1
	mm.visible_instance_count = accepted
	var grass := MultiMeshInstance3D.new()
	grass.name = "ShortMeadow"
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)


func _style_trays() -> void:
	for tray in _main.opr_army_manager.army_trays.values():
		for child in tray.get_children():
			if child is MeshInstance3D and child.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = child.material_override.duplicate()
				mat.albedo_color = mat.albedo_color.lerp(Color(0.08,0.10,0.11,mat.albedo_color.a),0.83)
				mat.roughness = 0.88
				child.material_override = mat


func _surface_hash(p: Vector2) -> float:
	var h := ((int(p.x) * 16777619) ^ (int(p.y) * 1103515245)) & 0xffffffff
	h = (((h >> 16) ^ h) * 16777619) & 0xffffffff
	h = (h >> 13) ^ h
	return float(h & 65535) / 65535.0


func _surface_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p-i
	var u := f*f*(Vector2(3,3)-2.0*f)
	return lerpf(lerpf(_surface_hash(i),_surface_hash(i+Vector2.RIGHT),u.x),lerpf(_surface_hash(i+Vector2.DOWN),_surface_hash(i+Vector2.ONE),u.x),u.y)
