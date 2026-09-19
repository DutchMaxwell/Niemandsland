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
var _tree_points := PackedVector2Array()
var _angles := PackedFloat32Array()
var _props: Node3D
var _previous_viewport: Dictionary = {}
var _studio_sky: Sky
var _fog: FogVolume
var _wall_top := 0.0635
var _camera: Camera3D
var _dof: CameraAttributesPractical
var _tilt_shift_enabled := true
const DOF_MAX_AMOUNT := 0.09
const DOF_NEAR_DISTANCE := 0.22
const DOF_FAR_DISTANCE := 1.10


func prepare() -> void:
	_props = preload("res://scripts/visual/reference_props.gd").new()
	add_child(_props)
	await _props.prepare()


func apply(main: Node) -> void:
	_main = main
	for i in 3:
		_trees.append(TREE_BUILDER.build(i))
	_ground = ShaderMaterial.new()
	_ground.shader = GROUND
	for texture_name in ["meadow","earth","woodland"]:
		_ground.set_shader_parameter(texture_name + "_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/" + texture_name + ".webp"))
	_ground.set_shader_parameter("earth_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/rough-earth.webp"))
	_ground.set_shader_parameter("woodland_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/forest-duff.webp"))
	var table: Node3D = main.get_node("Table")
	var surface: MeshInstance3D = table.get_node("TableMesh")
	var plane: PlaneMesh = surface.mesh.duplicate()
	plane.subdivide_width = 450
	plane.subdivide_depth = 300
	surface.mesh = plane
	_ground.set_shader_parameter("surface_relief",true)
	surface.material_override = _ground
	table.get_node("GrassField").visible = false
	_base = table.get_base_top_material()
	_base.shader = GROUND
	_base.set_shader_parameter("clip_base",true)
	for texture_name in ["meadow","earth","woodland"]:
		_base.set_shader_parameter(texture_name + "_tex",_ground.get_shader_parameter(texture_name + "_tex"))
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.022,0.026,0.023)
	frame.roughness = 0.86
	for child in table.get_children():
		if child is MeshInstance3D and child != table.get_node("TableMesh"):
			child.material_override = frame
	var overlay: Node3D = main.terrain_overlay
	_dress_grid_forest(overlay)
	_dress_movable_forests()
	_wall_top = overlay.WALL_HEIGHT_INCHES * overlay.INCHES_TO_METERS
	_dress_decals()
	for wall in overlay._wall_instances:
		_weather_ruin(wall)
	_sync_regions()
	var wall_regions := PackedVector4Array()
	for edge: Array in overlay.get_wall_segments_world():
		wall_regions.append(Vector4(edge[0].x,edge[0].y,edge[1].x,edge[1].y))
	var wall_count := mini(wall_regions.size(),64)
	wall_regions.resize(64)
	for mat in [_ground,_base]:
		mat.set_shader_parameter("wall_count",wall_count)
		mat.set_shader_parameter("wall_regions",wall_regions)
	var understory := preload("res://scripts/visual/reference_understory.gd").new()
	add_child(understory)
	understory.build(self,main,table.table_size * 0.3048)
	if _props != null:
		_props.dress(self,table.table_size*0.3048)
	_style_trays()
	_build_fog(main)
	apply_lighting("Day")


## Local fog volume over the board only: no global exponential fog, so the dark
## studio background behind the table stays black. Height falloff keeps the haze
## near the ground and lets light shafts form around the ruins.
func _build_fog(main: Node) -> void:
	var table: Node3D = main.get_node("Table")
	var surface: MeshInstance3D = main.get_node("Table/TableMesh")
	var size: Vector2 = table.table_size * 0.3048
	var span: float = maxf(size.x,size.y)
	var fog := FogMaterial.new()
	fog.density = 0.30
	fog.albedo = Color(0.72,0.73,0.70)
	fog.emission = Color(0.0,0.0,0.0)
	fog.height_falloff = 1.1
	fog.edge_fade = 0.60
	var volume := FogVolume.new()
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	volume.size = Vector3(span,span * 0.6,span)
	volume.material = fog
	surface.add_child(volume)
	volume.position = Vector3(0.0,span * 0.30,0.0)
	_fog = volume


func apply_lighting(mood: String) -> void:
	if _previous_viewport.is_empty():
		_previous_viewport = {"taa":get_viewport().use_taa,"scale":get_viewport().scaling_3d_scale}
	var light: Node = _main.lighting_controller
	var evening := mood == "Sunset"
	light.set_sun_energy(2.55)
	light.set_sun_color(Color(1,0.85,0.69) if evening else Color(1,0.90,0.76))
	light.set_sun_angles(-40.0 if evening else -58.0,28.0 if evening else 38.0)
	light.set_ambient_energy(0.32)
	light.set_ambient_color(Color(0.77,0.84,0.94))
	light.set_fill_light_energy(0.40)
	light.set_fill_light_color(Color(0.95,0.94,0.90))
	light.set_exposure(1.0)
	light.set_contrast(1.06)
	light.set_saturation(0.82)
	light.set_shadow_opacity(0.60)
	light.set_shadow_blur(1.5)
	light.set_shadow_bias(0.015)
	light.set_shadow_normal_bias(0.25)
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D")
	sun.directional_shadow_max_distance = 3.0
	sun.directional_shadow_pancake_size = 1.0
	sun.light_volumetric_fog_energy = 0.9
	RenderingServer.directional_shadow_atlas_set_size(8192,true)
	get_viewport().use_taa = false
	get_viewport().scaling_3d_scale = 1.25
	light.set_ssao_intensity(1.2)
	light.set_glow_intensity(0.16)
	var env: Environment = _main.get_node("WorldEnvironment").environment
	if _studio_sky == null:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.34,0.42,0.52)
		sky_material.sky_horizon_color = Color(0.65,0.61,0.51)
		sky_material.ground_bottom_color = Color(0.055,0.040,0.025)
		sky_material.ground_horizon_color = Color(0.46,0.42,0.34)
		_studio_sky = Sky.new()
		_studio_sky.sky_material = sky_material
		_studio_sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.sky = _studio_sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20,0.205,0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ssao_radius = 0.035
	env.ssao_intensity = 2.0
	env.ssao_power = 1.4
	env.ssil_enabled = false
	env.tonemap_agx_contrast = 1.15
	# Damp-surface screen-space reflections; no bloom (rejected by the maintainer).
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.08
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.20
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.72,0.73,0.70)
	env.volumetric_fog_emission = Color(0.0,0.0,0.0)
	env.volumetric_fog_length = 18.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.10
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	var camera: Camera3D = _main.get_node("CameraPivot/Camera3D")
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 0.40
	attributes.dof_blur_far_transition = 0.28
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = 0.075
	attributes.dof_blur_near_transition = 0.05
	attributes.dof_blur_amount = 0.0
	camera.attributes = attributes
	_camera = camera
	_dof = attributes


## Tilt-shift fades in as the camera zooms towards the table, so the wide review
## view stays sharp and only the close inspection gets the photo-like falloff.
## Player-toggleable: off removes the attribute cost entirely.
func set_tilt_shift_enabled(enabled: bool) -> void:
	_tilt_shift_enabled = enabled
	if _dof != null and not enabled:
		_dof.dof_blur_amount = 0.0


func tilt_shift_enabled() -> bool:
	return _tilt_shift_enabled


## Toggles the effect for a player. Production should wire this to a settings
## entry instead of the key; the key is only the reference-scene shortcut.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		set_tilt_shift_enabled(not _tilt_shift_enabled)


func _process(_delta: float) -> void:
	if _camera == null or _dof == null:
		return
	if not _tilt_shift_enabled:
		return
	var origin := _camera.global_position
	var forward := -_camera.global_transform.basis.z
	var focus_distance := origin.length()
	if absf(forward.y) > 0.001:
		focus_distance = origin.distance_to(origin + forward * (-origin.y / forward.y))
	var fade := 1.0 - smoothstep(DOF_NEAR_DISTANCE, DOF_FAR_DISTANCE, focus_distance)
	_dof.dof_blur_amount = DOF_MAX_AMOUNT * fade


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
			if _props != null and _props.has_tree():
				var tree: Node3D = _props.tree_instance(height,index)
				tree.name = "ReferenceCanopy"
				original.add_child(tree)
			else:
				var tree := MeshInstance3D.new()
				tree.name = "ReferenceCanopy"
				tree.mesh = _trees[index%3]
				tree.scale = Vector3.ONE*height
				original.add_child(tree)
			_tree_points.append(expected)
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


func _style_trays() -> void:
	for tray in _main.opr_army_manager.army_trays.values():
		for child in tray.get_children():
			if child is MeshInstance3D and child.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = child.material_override.duplicate()
				mat.albedo_color = mat.albedo_color.lerp(Color(0.025,0.030,0.032,mat.albedo_color.a),0.83)
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


## Organic moss blobs with soft alpha, used as a decal so the ruin feet and wall
## faces get patches the flat weathering shader cannot place per-position.
func _moss_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.022
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0,Color(0.0,0.0,0.0,0.0))
	ramp.set_color(1,Color(0.22,0.32,0.10,1.0))
	ramp.add_point(0.52,Color(0.10,0.17,0.05,0.45))
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.color_ramp = ramp
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	return texture


func _dress_decals() -> void:
	var moss := _moss_texture()
	var units: Array[Vector2] = []
	for model in _main.object_manager.get_children():
		if model is Node3D and model.is_in_group("selectable"):
			units.append(Vector2(model.global_position.x,model.global_position.z))
	var segments: Array = _main.terrain_overlay.get_wall_segments_world()
	var placed := 0
	for segment: Array in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var edge := b-a
		var length := edge.length()
		if length<0.01:
			continue
		var dir := edge/length
		var side := Vector2(-dir.y,dir.x)
		var count := clampi(int(length/0.15),1,2)
		for i in count:
			var t := (float(i)+0.5)/float(count)
			var p := a+edge*t
			var foot_center := p+side*0.020
			if _near_unit(foot_center,units):
				continue
			var foot := Decal.new()
			foot.texture_albedo = moss
			foot.albedo_mix = 0.55
			foot.size = Vector3(0.11,0.018,0.11)
			foot.position = Vector3(foot_center.x,0.010,foot_center.y)
			add_child(foot)
			var face_center := p+side*0.003
			var face := Decal.new()
			face.texture_albedo = moss
			face.albedo_mix = 0.5
			face.size = Vector3(0.08,0.05,0.016)
			face.position = Vector3(face_center.x,_wall_top*0.45,face_center.y)
			face.rotation = Vector3(-PI/2.0,atan2(side.x,side.y),0.0)
			add_child(face)
			placed += 2
	print("REFERENCE_DECALS ",placed)


func _near_unit(p: Vector2,units: Array[Vector2]) -> bool:
	for u in units:
		if p.distance_squared_to(u)<0.055*0.055:
			return true
	return false


func _weather_ruin(node: Node) -> void:
	if node is MeshInstance3D:
		var panel_texture: Texture2D = null
		var panel_scale := Vector2.ONE
		var panel_offset := Vector2.ZERO
		if node.material_override is BaseMaterial3D:
			var stone: BaseMaterial3D = node.material_override.duplicate()
			if stone.normal_enabled:
				stone.normal_scale *= 3.0
			# Damp masonry: darker and glossier than the shipped dry panels.
			stone.roughness = 0.45
			stone.metallic_specular = 0.6
			stone.albedo_color = Color(stone.albedo_color.r*0.62,
					stone.albedo_color.g*0.62,stone.albedo_color.b*0.60,stone.albedo_color.a)
			node.material_override = stone
			if not stone.uv1_triplanar and stone.albedo_texture != null:
				panel_texture = stone.albedo_texture
				panel_scale = Vector2(stone.uv1_scale.x,stone.uv1_scale.y)
				panel_offset = Vector2(stone.uv1_offset.x,stone.uv1_offset.y)
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/visual/reference_weathering.gdshader")
		material.set_shader_parameter("wall_top",_wall_top)
		if panel_texture != null:
			material.set_shader_parameter("stone_tex",panel_texture)
			material.set_shader_parameter("joint_darken",true)
			material.set_shader_parameter("panel_uv_scale",panel_scale)
			material.set_shader_parameter("panel_uv_offset",panel_offset)
		node.material_overlay = material
	for child in node.get_children():
		_weather_ruin(child)


func _exit_tree() -> void:
	if _previous_viewport.is_empty():
		return
	var viewport := get_viewport()
	viewport.use_taa = _previous_viewport.taa
	viewport.scaling_3d_scale = _previous_viewport.scale
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:
		RenderingServer.directional_shadow_atlas_set_size(graphics.PRESETS[graphics.current_preset]["shadow_size"],true)
