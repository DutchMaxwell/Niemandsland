extends Node3D
## Opt-in art-direction reference. Uses the real board and original miniatures.
## Existing rule geometry, terrain footprints and source models remain untouched.

const TREE_BUILDER = preload("res://scripts/visual/reference_tree.gd")
const GROUND = preload("res://shaders/visual/reference_ground.gdshader")
## Game-table tier variant: same surface, derivative bump instead of three extra surface samples.
const GROUND_TABLE = preload("res://shaders/visual/reference_ground_table.gdshader")
const ReferenceMaterials = preload("res://scripts/visual/reference_materials.gd")
var _main: Node
var _ground: ShaderMaterial
var _base: ShaderMaterial
var _trees: Array[ArrayMesh] = []
var _regions := PackedVector4Array()
var _tree_points := PackedVector2Array()
var _angles := PackedFloat32Array()
var _props: Node3D
var _biome_forest: Node3D
var _volcanic: Node3D
var _jungle_motion: Node3D
var _previous_viewport: Dictionary = {}
var _current_mood := "Day"
var _fog: FogVolume
var _dust: Array = []
var _wind_time := 0.0
var _wall_top := 0.0635
var _camera: Camera3D
var _dof: CameraAttributesPractical
var _tilt_shift_enabled := true
var biome := "grassland"
## Game-table tier (TableBiomePresenter): no TRELLIS prop replacement, the render scale / TAA / shadow
## atlas / camera stay with the player's quality preset, and scatter casts no shadow. Off = the accepted
## reference look (menu diorama, reference scene).
var table_tier := false
## Scatter density multiplier (table tier: quality preset x area cap). 1.0 = the reference density.
var density_scale := 1.0
## Table tier: edge length of the relief cells of the table plane.
const TABLE_RELIEF_CELL_M := 0.012
## Table tier: game moods that take the biome light profile (D1); the others keep the game's lighting.
const TABLE_PROFILE_MOODS: Array[String] = ["Day", "Sunset", "Night"]
var _profile: Dictionary = {}
const Biomes = preload("res://scripts/visual/reference_biomes.gd")
const DOF_MAX_AMOUNT := 0.045
const DOF_NEAR_DISTANCE := 0.30
const DOF_FAR_DISTANCE := 0.85


func prepare() -> void:
	# Urban uses native props and its dedicated textures; no oak/rock source is needed. The table tier
	# replaces no props, so it needs no TRELLIS source either.
	if biome == "urban_ruins" or table_tier:
		return
	_props = preload("res://scripts/visual/reference_props.gd").new()
	add_child(_props)
	await _props.prepare()
	if biome in ["frozen_tundra","arid_desert","volcanic_ash","alien_jungle"]:
		_biome_forest = preload("res://scripts/visual/reference_biome_forest.gd").new()
		add_child(_biome_forest)
		await _biome_forest.prepare(biome)


func apply(main: Node) -> void:
	_main = main
	_profile = Biomes.get_profile(biome)
	var table: Node3D = main.get_node("Table")
	# Re-theme the ruin walls and trees to the biome before dressing. The overlay is themed
	# directly: table.set_biome also rebuilds the production battlemap material, which would
	# replace the reference ground and reset the shared base-top material under us.
	if not _profile["biome"].is_empty() and main.terrain_overlay.has_method("set_biome"):
		main.terrain_overlay.set_biome(_profile["biome"])
	for i in 3:
		_trees.append(TREE_BUILDER.build(i))
	_ground = ShaderMaterial.new()
	_ground.shader = GROUND_TABLE if table_tier else GROUND
	for texture_name in ["meadow","earth","woodland"]:
		_ground.set_shader_parameter(texture_name + "_tex",ReferenceMaterials.texture(_profile["textures"][texture_name]))
	_ground.set_shader_parameter("desert_mode",_profile["desert_mode"])
	_ground.set_shader_parameter("tundra_mode",_profile.get("tundra_mode",false))
	_ground.set_shader_parameter("volcanic_mode",_profile.get("volcanic_mode",false))
	_ground.set_shader_parameter("jungle_mode",_profile.get("jungle_mode",false))
	_ground.set_shader_parameter("urban_mode",_profile.get("urban_mode",false))
	var surface: MeshInstance3D = table.get_node("TableMesh")
	var plane: PlaneMesh = surface.mesh.duplicate()
	plane.subdivide_width = 450
	plane.subdivide_depth = 300
	if table_tier:
		# Relief cells follow the table size (the reference's 450x300 is ~4 mm on 6x4 ft only). The relief's
		# shortest wavelength is ~13 cm, so TABLE_RELIEF_CELL_M still samples it finely; 4 mm cells were
		# 3-6 px triangles at play zoom, shaded several times per pixel under MSAA. Capped for 240 in tables.
		var size_m: Vector2 = table.table_size * 0.3048
		plane.subdivide_width = clampi(int(size_m.x / TABLE_RELIEF_CELL_M), 16, 400)
		plane.subdivide_depth = clampi(int(size_m.y / TABLE_RELIEF_CELL_M), 16, 400)
	surface.mesh = plane
	_ground.set_shader_parameter("surface_relief",true)
	# Props and miniatures stand at y = 0 on the game table, so its tier drops the small-scale noise relief (mines
	# floated over its dips) and keeps the mounds and ridges; the dressing below follows the same surface.
	_ground.set_shader_parameter("relief_noise",not table_tier)
	ReferenceMaterials.set_tier(table_tier)
	surface.material_override = _ground
	table.get_node("GrassField").visible = false
	_base = table.get_base_top_material()
	_base.shader = _ground.shader
	_base.set_shader_parameter("clip_base",true)
	for texture_name in ["meadow","earth","woodland"]:
		_base.set_shader_parameter(texture_name + "_tex",_ground.get_shader_parameter(texture_name + "_tex"))
	_base.set_shader_parameter("desert_mode",_profile["desert_mode"])
	_base.set_shader_parameter("tundra_mode",_profile.get("tundra_mode",false))
	_base.set_shader_parameter("volcanic_mode",_profile.get("volcanic_mode",false))
	_base.set_shader_parameter("jungle_mode",_profile.get("jungle_mode",false))
	_base.set_shader_parameter("urban_mode",_profile.get("urban_mode",false))
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.022,0.026,0.023)
	frame.roughness = 0.86
	for child in table.get_children():
		if child is MeshInstance3D and child != table.get_node("TableMesh"):
			child.material_override = frame
	var overlay: Node3D = main.terrain_overlay
	if _profile["forests"]:
		_dress_grid_forest(overlay)
		_dress_movable_forests()
	if _biome_forest != null:
		_biome_forest.apply(main,self)
	_wall_top = overlay.WALL_HEIGHT_INCHES * overlay.INCHES_TO_METERS
	# Retain the tundra's snow-covered masonry instead of applying damp green moss.
	if not _profile.get("tundra_mode",false) and not _profile.get("volcanic_mode",false) and not _profile.get("urban_mode",false):
		_dress_decals()
		for wall in overlay._wall_instances:
			_weather_ruin(wall)
	_sync_regions()
	var wall_regions := PackedVector4Array()
	for edge: Array in overlay.get_wall_segments_world():
		wall_regions.append(Vector4(edge[0].x,edge[0].y,edge[1].x,edge[1].y))
	var wall_count := mini(wall_regions.size(),64)
	wall_regions.resize(64)
	var drift_points := PackedVector4Array()
	if _profile["desert_mode"]:
		# Sand piles only where a windbreak stands: ruin walls (handled in the shader),
		# trees/cacti and containers. Mines and signs are flat markers, so they get none.
		var dims: Vector2i = overlay._calculate_grid_dims(overlay.table_size_feet)
		var cell_size: float = overlay.GRID_SIZE_INCHES * overlay.INCHES_TO_METERS
		var rot := deg_to_rad(float(overlay.grid_rotation_degrees))
		for obj: Dictionary in overlay._last_objects:
			var kind: String = obj.get("object_type","tree")
			if kind != "tree" and kind != "container":
				continue
			var cell: Vector2i = obj.cell
			var offset: Vector2 = obj.offset
			var x := (cell.x-dims.x/2.0+offset.x)*cell_size
			var z := (cell.y-dims.y/2.0+offset.y)*cell_size
			var point := Vector2(x*cos(rot)-z*sin(rot),x*sin(rot)+z*cos(rot))
			drift_points.append(Vector4(point.x,point.y,0.028 if kind=="tree" else 0.058,0.0))
	var drift_count := mini(drift_points.size(),32)
	drift_points.resize(32)
	for mat in [_ground,_base]:
		mat.set_shader_parameter("wall_count",wall_count)
		mat.set_shader_parameter("wall_regions",wall_regions)
		mat.set_shader_parameter("drift_count",drift_count)
		mat.set_shader_parameter("drift_points",drift_points)
	if table_tier:
		if not _profile.get("urban_mode",false):   # the urban ground draws no mounds
			ReferenceMaterials.set_mounds(wall_regions.slice(0,wall_count),drift_points.slice(0,drift_count))
		_seat_props(overlay)
	var understory: Node3D = preload("res://scripts/visual/reference_jungle.gd").new() if _profile.get("jungle_mode",false) else preload("res://scripts/visual/reference_understory.gd").new()
	if _profile.get("urban_mode",false):
		understory.free()
		understory = preload("res://scripts/visual/reference_urban.gd").new()
	add_child(understory)
	if _profile["understory"] == "desert":
		understory.build_desert(self,main,table.table_size * 0.3048)
	elif _profile["understory"] == "volcanic":
		understory.build_volcanic(self,main,table.table_size * 0.3048)
	elif _profile["understory"] == "tundra":
		understory.build_tundra(self,main,table.table_size * 0.3048)
	else:
		understory.build(self,main,table.table_size * 0.3048)
	if _props != null and not _profile.get("volcanic_mode",false) and not _profile.get("urban_mode",false):
		_props.dress(self,table.table_size*0.3048)
	if _profile.get("volcanic_mode",false):
		_volcanic = preload("res://scripts/visual/reference_volcanic.gd").new()
		add_child(_volcanic)
		_volcanic.build(main,self)
	if _profile.get("jungle_mode",false):
		_jungle_motion = preload("res://scripts/visual/reference_jungle_motion.gd").new()
		add_child(_jungle_motion)
		_jungle_motion.build(main,self,understory)
	_build_fog(main)
	if _profile["dust"]:
		_build_dust(main)
	if table_tier:
		apply_table_mood(_game_mood())
	else:
		apply_lighting("Day")
	# A quality-preset change rewrites the shared environment (SDFGI, SSIL, metre-scale
	# SSAO, stronger glow). Re-assert the tuned reference look so Ultra cannot undo it.
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null and not graphics.settings_applied.is_connected(_on_graphics_settings_applied):
		graphics.settings_applied.connect(_on_graphics_settings_applied)


## Local fog volume over the board only: no global exponential fog, so the dark
## studio background behind the table stays black. A 3D noise texture breaks the
## haze into sparse wisps that hug the ground and drift slowly across it.
func _build_fog(main: Node) -> void:
	var table: Node3D = main.get_node("Table")
	var surface: MeshInstance3D = main.get_node("Table/TableMesh")
	var size: Vector2 = table.table_size * 0.3048
	var span: float = maxf(size.x,size.y)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.28
	noise.fractal_octaves = 3
	var wisps := NoiseTexture3D.new()
	wisps.noise = noise
	wisps.width = 64
	wisps.height = 16
	wisps.depth = 64
	wisps.seamless = true
	wisps.seamless_blend_skirt = 0.2
	var fog := FogMaterial.new()
	fog.density = _profile["fog_density"]
	fog.density_texture = wisps
	fog.albedo = _profile["fog_color"]
	fog.emission = Color(0.0,0.0,0.0)
	fog.height_falloff = 1.5
	fog.edge_fade = 0.90
	var volume := FogVolume.new()
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	# A thin band (~1.5 cm) laid just above the ground.
	volume.size = Vector3(span,0.015,span)
	volume.material = fog
	surface.add_child(volume)
	volume.position = Vector3(0.0,0.010,0.0)
	_fog = volume


## Local, terrain-following sand streams with separate gust phases.
func _build_dust(main: Node) -> void:
	var table: Node3D = main.get_node("Table")
	var surface: MeshInstance3D = main.get_node("Table/TableMesh")
	var size: Vector2 = table.table_size * 0.3048
	var streams := preload("res://scripts/visual/reference_sand_streams.gd").build(main,_ground,size)
	surface.add_child(streams)
	_dust.append(streams)


func apply_lighting(mood: String) -> void:
	_current_mood = mood
	if _previous_viewport.is_empty():
		_previous_viewport = {"taa":get_viewport().use_taa,"scale":get_viewport().scaling_3d_scale}
	var light: Node = _main.lighting_controller
	# D1 (table tier): Night uses the profile's sunset values too.
	var evening := mood == "Sunset" or (table_tier and mood == "Night")
	var angles: Vector2 = _profile["sun_angles_sunset"] if evening else _profile["sun_angles_day"]
	light.set_sun_energy(_profile["sun_energy"])
	light.set_sun_color(_profile["sun_color_sunset"] if evening else _profile["sun_color_day"])
	light.set_sun_angles(angles.x,angles.y)
	light.set_ambient_energy(_profile["ambient_energy"])
	light.set_ambient_color(_profile["ambient_color"])
	light.set_fill_light_energy(_profile["fill_energy"])
	light.set_fill_light_color(_profile["fill_color"])
	light.set_exposure(1.0)
	light.set_contrast(1.06)
	light.set_saturation(_profile["saturation"])
	light.set_shadow_opacity(0.60)
	light.set_shadow_blur(1.5)
	light.set_shadow_bias(0.015)
	light.set_shadow_normal_bias(0.25)
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D")
	sun.directional_shadow_max_distance = 3.0
	sun.directional_shadow_pancake_size = 1.0
	sun.light_volumetric_fog_energy = 0.9
	if not table_tier:
		RenderingServer.directional_shadow_atlas_set_size(8192,true)
		get_viewport().use_taa = false
		get_viewport().scaling_3d_scale = 1.25
	light.set_ssao_intensity(1.2)
	light.set_glow_intensity(0.16)
	_apply_reference_environment()
	if table_tier:
		return   # the game camera keeps its own tilt-shift (camera_controller.gd)
	var camera: Camera3D = _main.get_node("CameraPivot/Camera3D")
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 0.55
	attributes.dof_blur_far_transition = 0.55
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = 0.10
	attributes.dof_blur_near_transition = 0.12
	attributes.dof_blur_amount = 0.0
	camera.attributes = attributes
	_camera = camera
	_dof = attributes


## Reference environment, isolated so a quality-preset change can be countered. Keeps the
## game's space skybox as the visible background and reflection source (the starfield is
## part of the identity, maintainer decision) and pins the tuned miniature-scale values.
func _apply_reference_environment() -> void:
	var env: Environment = _main.get_node("WorldEnvironment").environment
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ssao_radius = 0.035
	env.ssao_intensity = 2.0
	env.ssao_power = 1.4
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.tonemap_agx_contrast = 1.15
	# Damp-surface screen-space reflections; no bloom (rejected by the maintainer). The table tier follows
	# the player's quality preset for SSR and volumetric fog (Medium: both off, High/Ultra: on).
	var preset := _preset_values()
	env.ssr_enabled = bool(preset.get("ssr", true)) if table_tier else true
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.08
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.20
	env.volumetric_fog_enabled = bool(preset.get("volumetric_fog", true)) if table_tier else true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.72,0.73,0.70)
	env.volumetric_fog_emission = Color(0.0,0.0,0.0)
	env.volumetric_fog_length = 18.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.10
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	# Pin the glow to the accepted reference look so ULTRA's stronger glow/bloom cannot
	# wash the scene out; the light controller's set_glow_intensity(0.16) still wins on intensity.
	env.glow_enabled = true
	env.glow_bloom = 0.1
	env.glow_intensity = 0.16
	env.fog_enabled = false


## The player's current quality preset values (GraphicsSettings.PRESETS); empty outside the game.
func _preset_values() -> Dictionary:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics == null:
		return {}
	return graphics.PRESETS.get(graphics.current_preset, {})


func _on_graphics_settings_applied(_preset_name: String) -> void:
	if _main != null:
		if table_tier:
			apply_table_mood(_game_mood())
		else:
			apply_lighting(_current_mood)


## Table tier, maintainer decision D1: the biome light profile is the Day base; Sunset and Night use the
## profile's own sunset values; the other game moods (Overcast, Rain) keep the game's own lighting.
func apply_table_mood(mood: String) -> void:
	if mood in TABLE_PROFILE_MOODS:
		apply_lighting(mood)


## The game's current atmosphere mood (atmosphere_controller), "Day" outside the game.
func _game_mood() -> String:
	var atmosphere = _main.get("atmosphere_controller") if _main != null else null
	return str(atmosphere.get_current_atmosphere()) if atmosphere != null else "Day"


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
	if table_tier:
		return   # T is the game's move-trails key; the table tier has no camera of its own
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		set_tilt_shift_enabled(not _tilt_shift_enabled)


func _process(delta: float) -> void:
	if not _dust.is_empty() or _volcanic != null or _jungle_motion != null:
		_wind_time += delta
		for streams in _dust:
			streams.material_override.set_shader_parameter("time",_wind_time)
	if _volcanic != null:
		_volcanic.set_time(_wind_time)
	if _jungle_motion != null:
		_jungle_motion.set_time(_wind_time)
	if _ground != null:
		_ground.set_shader_parameter("wind_time",_wind_time)
	if _base != null:
		_base.set_shader_parameter("wind_time",_wind_time)
	if _fog != null:
		var t := Time.get_ticks_msec() / 1000.0
		var span: float = _fog.size.x
		_fog.position.x = sin(t * 0.05) * span * 0.02
		_fog.position.z = cos(t * 0.037) * span * 0.02
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
			if table_tier:
				# Keep the game's own tree; only its position feeds the litter around it.
				_tree_points.append(expected)
				index += 1
				break
			var bounds: AABB = overlay._model_space_aabb(original)
			var height := clampf(bounds.size.y,0.08,0.20)
			for child in original.get_children():
				if child is Node3D:
					child.visible = false
			if _props != null and _props.has_tree():
				var tree: Node3D = _props.tree_instance(height,index,ReferenceMaterials.ground_height(expected))
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


## Table tier: the flat markers (mines, warning signs, hazard models) stand on the dressed ground instead of hovering
## at a mound's foot: each drops onto the LOWEST ground under its footprint, so nothing floats. Trees and containers
## raise the mounds themselves (a container's edges are wall segments, the desert piles sand around both), so they
## stay at y = 0, sunk in their own mound as in the reference. Display only: cells, footprints and LOS are untouched,
## and the overlay's rebuild on teardown puts the markers back at y = 0.
func _seat_props(overlay: Node3D) -> void:
	var dims: Vector2i = overlay._calculate_grid_dims(overlay.table_size_feet)
	var cell_size: float = overlay.GRID_SIZE_INCHES * overlay.INCHES_TO_METERS
	var rot := deg_to_rad(float(overlay.grid_rotation_degrees))
	var windbreaks: Array[Vector2] = []
	for obj: Dictionary in overlay._last_objects:
		if obj.get("object_type","tree") in ["tree","container"]:
			var x: float = (obj.cell.x-dims.x/2.0+obj.offset.x)*cell_size
			var z: float = (obj.cell.y-dims.y/2.0+obj.offset.y)*cell_size
			windbreaks.append(Vector2(x*cos(rot)-z*sin(rot),x*sin(rot)+z*cos(rot)))
	for prop in overlay._object_instances:
		if not is_instance_valid(prop) or windbreaks.any(func(w: Vector2) -> bool: return w.distance_to(Vector2(prop.position.x,prop.position.z)) < 0.001):
			continue
		var box: AABB = overlay._model_space_aabb(prop)
		if not box.has_volume():   # no mesh yet (a model still loading): its own spot
			box = AABB(prop.position,Vector3.ZERO)
		var lowest := INF
		for i in 3:
			for j in 3:
				lowest = minf(lowest,ReferenceMaterials.ground_height(Vector2(lerpf(box.position.x,box.end.x,i*0.5),lerpf(box.position.z,box.end.z,j*0.5))))
		prop.position.y += lowest


func _dress_movable_forests() -> void:
	for group in get_tree().get_nodes_in_group("terrain_group_base"):
		if group.prop_kind != TerrainGroupBase.KIND_FOREST or group.biome_prefix != "":
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
