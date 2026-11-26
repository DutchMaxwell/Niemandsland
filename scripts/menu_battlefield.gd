extends Node3D
## Dedicated visual scene. No game, save, army-state or atmosphere controller is loaded.
## Supplies the small scene contract used by the accepted biome presentation.

signal progress(label: String, ratio: float)
signal finished

const BIOMES := ["urban_ruins", "alien_jungle", "grassland", "arid_desert", "frozen_tundra", "volcanic_ash"]
const FORMATION := [Vector2(-0.043,0), Vector2(0,0.01), Vector2(0.043,0), Vector2(-0.0215,-0.043), Vector2(0.0215,-0.043)]
## Offline or a failed download: reveal the placeholders after this long rather than never.
const TERRAIN_MODELS_WAIT_MS := 30000
## The hero shot's light, matched to MenuDiorama.CAMERA_REST: a cool moon and key light from the front left
## light every face, a warm fire spill at the Warriors' side gives the picture its second colour.
const MOON_COLOR := Color(0.50,0.80,0.92)
const KEY_POSITION := Vector3(-0.20,0.25,0.35)
const KEY_ENERGY := 0.9
const KEY_RANGE := 1.0
const FIRE_POSITION := Vector3(0.24,0.05,0.02)
const FIRE_COLOR := Color(1.0,0.52,0.22)
const FIRE_ENERGY := 0.7
const FIRE_RANGE := 0.30
## Depth of field (Medium and up): blur beyond the forces and a soft near edge keep the eye on the miniatures.
const DOF_FAR_DISTANCE := 0.60
const DOF_FAR_TRANSITION := 0.30
const DOF_NEAR_DISTANCE := 0.20
const DOF_NEAR_TRANSITION := 0.06
const DOF_AMOUNT := 0.09
var terrain_overlay: Node3D
var object_manager: ObjectManager
var lighting_controller: Node
var presentation: Node3D
var camera: Camera3D
var biome := "urban_ruins"
var model_count := 0
var _key_light: OmniLight3D
var _fire_light: OmniLight3D

class MenuObjects extends ObjectManager:
	# Visual-only container: no deferred network discovery, selection lights or
	# input setup. The inherited model lookup is used by biome contact dressing.
	func _ready() -> void:
		selection_enabled = false


class MenuSurface extends Node3D:
	signal table_resized(size_feet: Vector2)
	var table_size := Vector2(4,4)
	var _base := ShaderMaterial.new()

	func get_base_top_material() -> ShaderMaterial:
		return _base


func build(selected_biome: String, world_env: WorldEnvironment, sun: DirectionalLight3D, light: Node, lens: Camera3D) -> void:
	biome = selected_biome if selected_biome in BIOMES else "urban_ruins"
	lighting_controller = light
	world_env.reparent(self)
	world_env.name = "WorldEnvironment"
	sun.reparent(self)
	sun.name = "DirectionalLight3D"
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	add_child(pivot)
	lens.reparent(pivot)
	lens.name = "Camera3D"
	camera = lens
	var table := MenuSurface.new()
	table.name = "Table"
	add_child(table)
	var surface := MeshInstance3D.new()
	surface.name = "TableMesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4,4)
	surface.mesh = plane
	# The node owns the mesh; do not retain a resource in a cancelled coroutine.
	plane = null
	table.add_child(surface)
	var grass := Node3D.new()
	grass.name = "GrassField"
	table.add_child(grass)
	object_manager = MenuObjects.new()
	object_manager.name = "ObjectManager"
	object_manager.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(object_manager)
	terrain_overlay = load("res://scripts/terrain_overlay.gd").new()
	terrain_overlay.defer_tree_model_parse = true
	add_child(terrain_overlay)
	_build_terrain()
	progress.emit("Preparing terrain",0.15)
	# Every await can resume after the player left the menu (Create during a cold-cache
	# download): the scene is out of the tree until it is freed, so stop building quietly.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await _build_units(table)
	if not is_inside_tree():
		return
	progress.emit("Preparing biome",0.75)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	presentation = load("res://scripts/visual/grassland_reference.gd").new()
	presentation.biome = biome
	add_child(presentation)
	await presentation.prepare()
	if not is_inside_tree():
		return
	# On a cold cache the overlay shows placeholder walls and trees until their models download, and the
	# biome dressing below replaces trees only once. Dress the finished terrain, never a placeholder.
	if not _terrain_models_ready():
		progress.emit("Preparing terrain models",0.9)
		var deadline := Time.get_ticks_msec()+TERRAIN_MODELS_WAIT_MS
		while not _terrain_models_ready() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if not is_inside_tree():
				return
	presentation.apply(self)
	presentation.set_tilt_shift_enabled(false)
	# This scene owns its lighting and quality policy. Reference's daylight callback
	# must not turn the menu into a daytime scene after a live preset change.
	if GraphicsSettings.settings_applied.is_connected(presentation._on_graphics_settings_applied):
		GraphicsSettings.settings_applied.disconnect(presentation._on_graphics_settings_applied)
	terrain_overlay.set_fires_enabled(true)
	for label in terrain_overlay._terrain_labels:
		label.hide()
	_add_spill(Vector3(0.12,0.12,0.20),Color(0.78,0.84,1),0.10,0.42)
	_add_spill(Vector3(-0.03,0.045,-0.13),Color(1,0.42,0.16),0.12,0.27)
	_key_light = _add_spill(KEY_POSITION,MOON_COLOR,KEY_ENERGY,KEY_RANGE)
	_fire_light = _add_spill(FIRE_POSITION,FIRE_COLOR,FIRE_ENERGY,FIRE_RANGE)
	# After the lights exist: the tier switches in here reach them.
	apply_night()
	progress.emit("Ready",1.0)
	finished.emit()


func _terrain_models_ready() -> bool:
	return terrain_overlay._ruin_panels_ready() and terrain_overlay._tree_panels_ready() and terrain_overlay._tree_models_ready()


func _build_terrain() -> void:
	var cells: Dictionary = {}
	var walls: Array = []
	var objects: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 220922
	# The biome's wall and tree theme now (the presentation's apply() sets the same one), so their models
	# download while the miniatures and the biome sources load.
	terrain_overlay.set_biome(biome)
	for placement in [["ruine_9x9",Vector2i(11,9)], ["ruine_9x6",Vector2i(7,6)],
		["wald_9x9",Vector2i(6,9)], ["wald_9x9",Vector2i(12,4)], ["wald_9x9",Vector2i(16,8)]]:
		for cell in TerrainPrefabs.footprint_cells(placement[0],placement[1]):
			cells[cell] = TerrainPrefabs.terrain_type(placement[0])
		walls.append_array(TerrainPrefabs.wall_segments_for(placement[0],placement[1]))
		objects.append_array(TerrainPrefabs.decoration_for(placement[0],placement[1],rng))
	terrain_overlay.update_overlay(cells,Vector2(4,4),0)
	terrain_overlay.update_wall_models(walls,Vector2(4,4),0)
	terrain_overlay.update_placed_objects(objects,Vector2(4,4),0)
	terrain_overlay.set_overlay_mode(1)
	terrain_overlay.set_deployment_zones_visible(false)


func _build_units(table: Node3D) -> void:
	# Use the game's visual model builder: same resolved assets, fit, bases and materials.
	# Only two distinct models are parsed, then five instances per unit are created.
	var factory := OPRArmyManager.new()
	add_child(factory)
	factory.table = table
	factory.object_manager = object_manager
	for unit in [{"name":"Battle Brothers","faction":"battle_brothers","base":25,"center":Vector3(-0.005,0,0.135),"yaw":65.0},
		{"name":"Warriors","faction":"robot_legions","base":32,"center":Vector3(0.170,0,0.115),"yaw":-110.0}]:
		progress.emit("Preparing miniatures",0.25+float(model_count)*0.04)
		# The same manifest-backed delivery as army import; offline retains native fallback models.
		await factory.model_library.ensure_models([{"faction":unit.faction,"unit_name":unit.name}])
		if not is_inside_tree():
			return
		for index in FORMATION.size():
			var props := {"name":unit.name,"faction_folder":unit.faction,"size":5,
				"base_size_round":unit.base,"base_width_mm":unit.base,"base_depth_mm":unit.base,"base_from_tough":false}
			var model := factory.create_model_from_properties(props,1,unit.name)
			model.name = "%s_%d" % [unit.name.replace(" ","_"),index+1]
			object_manager.add_child(model)
			model.process_mode = Node.PROCESS_MODE_DISABLED
			model.collision_layer = 0
			model.collision_mask = 0
			var offset: Vector2 = FORMATION[index]
			model.position = unit.center+Vector3(0.798,0,-0.603)*offset.x+Vector3(0.603,0,0.798)*offset.y
			model.rotation.y = deg_to_rad(unit.yaw+(index%3-1)*7.0)
			model_count += 1
			await get_tree().process_frame
			if not is_inside_tree():
				return
	factory.queue_free()


func apply_night() -> void:
	if not is_instance_valid(lighting_controller):
		return
	# The hero shot's grade: a brighter moon, fuller colour and a lifted fog, so the lit faces carry the picture.
	lighting_controller.set_sun_energy(0.55)
	lighting_controller.set_sun_color(MOON_COLOR)
	lighting_controller.set_sun_angles(-40,38)
	lighting_controller.set_ambient_energy(0.13)
	lighting_controller.set_ambient_color(Color(0.32,0.43,0.67))
	lighting_controller.set_fill_light_energy(0.08)
	lighting_controller.set_fill_light_color(Color(0.55,0.66,0.95))
	lighting_controller.set_exposure(0.98)
	lighting_controller.set_saturation(1.08)
	lighting_controller.set_contrast(1.08)
	lighting_controller.set_glow_intensity(0.45)
	var env: Environment = get_node("WorldEnvironment").environment
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_light_color = Color(0.09,0.13,0.19)
	env.fog_light_energy = 0.7
	env.fog_density = 0.13
	env.fog_sky_affect = 0.35
	env.glow_bloom = 0.10
	env.sdfgi_enabled = false
	env.ssil_enabled = false
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().use_taa = false
	# Keep the accepted metre-scale contact shading; expensive effects follow quality.
	env.ssao_radius = 0.035
	env.ssao_enabled = GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.MEDIUM
	env.ssr_enabled = GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.HIGH
	env.volumetric_fog_enabled = GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.HIGH
	for light in [_key_light,_fire_light]:
		if is_instance_valid(light):
			light.shadow_enabled = GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.HIGH
	if is_instance_valid(camera):
		camera.attributes = _depth_of_field() if GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.MEDIUM else null


func _depth_of_field() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = DOF_FAR_DISTANCE
	attributes.dof_blur_far_transition = DOF_FAR_TRANSITION
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = DOF_NEAR_DISTANCE
	attributes.dof_blur_near_transition = DOF_NEAR_TRANSITION
	attributes.dof_blur_amount = DOF_AMOUNT
	return attributes


func _add_spill(position_value: Vector3, color: Color, energy: float, radius: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position_value
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	add_child(light)
	return light
