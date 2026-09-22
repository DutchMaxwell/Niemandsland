class_name MenuDiorama
extends SubViewportContainer
## Live, isolated nighttime biome vignette. The menu UI remains usable while assets
## prepare. Performance/test mode keeps the inexpensive procedural sky.

signal first_frame_rendered
signal loading_progress(label: String, ratio: float)
signal diorama_ready
signal rebuild_started
signal lighting_changed(controller: Node)

enum Mode { AUTO, FORCED, SKY_ONLY }
@export var mode: Mode = Mode.AUTO
@export_enum("urban_ruins", "alien_jungle", "grassland", "arid_desert", "frozen_tundra", "volcanic_ash") var biome := "urban_ruins"

const Battlefield = preload("res://scripts/menu_battlefield.gd")
const SKYBOX_MATERIAL_PATH := "res://materials/space_skybox.tres"
var _viewport: SubViewport
var _camera: Camera3D
var _lighting: Node
var _battlefield: Node3D
var _diorama_built := false
var _generation := 0
var _drift_t := 0.0
var _fov_bias := 0.0
var _ambience_enabled := true
var _war: WarAmbience


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var config := ConfigFile.new()
	if config.load("user://menu.cfg") == OK:
		var saved: String = str(config.get_value("menu","biome","urban_ruins"))
		if saved in Battlefield.BIOMES:
			biome = saved
	_setup()
	GraphicsSettings.settings_applied.connect(_on_graphics_settings_applied)


static func should_build_diorama(tier: int) -> bool:
	return tier > GraphicsSettings.QualityPreset.PERFORMANCE


func _diorama_active() -> bool:
	if mode == Mode.FORCED:
		return true
	if mode == Mode.SKY_ONLY or DisplayServer.get_name() == "headless":
		return false
	var scene_root: Node = owner if owner != null else self
	return should_build_diorama(GraphicsSettings.current_preset) and get_tree().current_scene == scene_root


func set_biome(value: String) -> void:
	if value not in Battlefield.BIOMES or value == biome:
		return
	biome = value
	if is_node_ready():
		_rebuild()


func get_lighting_controller() -> Node:
	return _lighting


func set_fov_bias(value: float) -> void:
	_fov_bias = clampf(value,-0.5,0.5)


func set_ambience_enabled(value: bool) -> void:
	_ambience_enabled = value
	if is_instance_valid(_war):
		_war.set_war_sounds_enabled(value)


func _setup() -> void:
	_generation += 1
	var generation := _generation
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	stretch_shrink = 2 if GraphicsSettings.current_preset == GraphicsSettings.QualityPreset.LOW else 1
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.sky = Sky.new()
	env.sky.sky_material = load(SKYBOX_MATERIAL_PATH).duplicate()
	env.sky.sky_material.set_shader_parameter("star_brightness",2.8)
	env.sky.sky_material.set_shader_parameter("nebula_intensity",0.8)
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.MEDIUM
	_viewport.add_child(sun)
	_lighting = load("res://scripts/lighting_controller.gd").new()
	_viewport.add_child(_lighting)
	_lighting.initialize(sun,world,null)
	_lighting.apply_preset("Night")
	lighting_changed.emit(_lighting)
	_camera = Camera3D.new()
	_camera.fov = 35
	_camera.h_offset = -0.075
	_viewport.add_child(_camera)
	_place_camera()
	await get_tree().process_frame
	if generation != _generation:
		return
	first_frame_rendered.emit()
	if not _diorama_active():
		diorama_ready.emit()
		return
	var stage := Battlefield.new()
	_battlefield = stage
	_viewport.add_child(stage)
	stage.progress.connect(func(label: String, ratio: float) -> void: loading_progress.emit(label,ratio))
	await stage.build(biome,world,sun,_lighting,_camera)
	if generation != _generation or not is_instance_valid(stage):
		return
	_diorama_built = true
	_war = WarAmbience.new()
	stage.add_child(_war)
	_war.set_volume_offset_db(-10)
	_war.set_war_sounds_enabled(_ambience_enabled)
	_war.update_fire_crackle(stage.terrain_overlay.get_fire_positions())
	diorama_ready.emit()


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	if not GraphicsSettings.reduce_motion:
		_drift_t += delta
	_place_camera()


func _place_camera() -> void:
	# Small drift preserves both five-model units in frame throughout the cycle.
	var drift := 0.0 if GraphicsSettings.reduce_motion else sin(_drift_t*TAU/40.0)
	_camera.position = Vector3(0.34+drift*0.007,0.12,0.45-drift*0.004)
	_camera.look_at(Vector3(0,0.024,-0.01))
	_camera.fov = 35.0 if GraphicsSettings.reduce_motion else 35.0+_fov_bias


func _rebuild() -> void:
	rebuild_started.emit()
	_generation += 1
	_diorama_built = false
	_battlefield = null
	_camera = null
	_lighting = null
	_war = null
	if is_instance_valid(_viewport):
		remove_child(_viewport)
		_viewport.queue_free()
	_setup()


func _on_graphics_settings_applied(_preset_name: String) -> void:
	if mode != Mode.AUTO:
		return
	if _diorama_built != _diorama_active():
		_rebuild()
	elif is_instance_valid(_battlefield):
		stretch_shrink = 2 if GraphicsSettings.current_preset == GraphicsSettings.QualityPreset.LOW else 1
		_battlefield.get_node("DirectionalLight3D").shadow_enabled = GraphicsSettings.current_preset >= GraphicsSettings.QualityPreset.MEDIUM
		_battlefield.apply_night()
