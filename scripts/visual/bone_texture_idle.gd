class_name BoneTextureIdle
extends Node3D
## Optional visual payload; the static miniature owns fitting, collisions, rules and saves.

const SHADER := preload("res://shaders/idle/bone_texture.gdshader")
const OVERLAY := preload("res://shaders/idle/bone_overlay.gdshader")
const MAX_DISTANCE := 0.85
static var _materials: Dictionary = {}
static var _overlays: Dictionary = {}
var _static_meshes: Array[MeshInstance3D] = []
var _original_visibility: Array[bool] = []
var _visual: MeshInstance3D
var _dead := false
var _elapsed := 0.0


static func valid_entry(entry: Dictionary) -> bool:
	return BoneTexturePayload.valid_entry(entry)




static func phase_for(identity: String) -> float:
	return float(identity.sha256_text().substr(0, 8).hex_to_int()) / 4294967296.0


static func motion_allowed(preset: int, requested: bool, reduced: bool) -> bool:
	return preset >= 2 and requested and not reduced


## Return false without touching the original scene on absent, partial or invalid payloads.
static func attach(model: Node3D, paths: Dictionary, entry: Dictionary, identity: String) -> bool:
	if DisplayServer.get_name() == "headless" or not valid_entry(entry) or paths.is_empty():
		return false
	if not FileAccess.file_exists(str(paths.get("mesh", ""))) or not FileAccess.file_exists(str(paths.get("poses", ""))):
		return false
	var mesh := ResourceLoader.load(paths.mesh, "ArrayMesh") as ArrayMesh
	var poses := ResourceLoader.load(paths.poses, "ImageTexture") as ImageTexture
	if not valid_resources(mesh, poses, entry):
		return false
	var idle := BoneTextureIdle.new()
	idle.name = "BoneTextureIdle"
	for node in model.find_children("*", "MeshInstance3D", true, false):
		idle._static_meshes.append(node)
		idle._original_visibility.append(node.visible)
	idle._visual = MeshInstance3D.new()
	idle._visual.mesh = mesh
	idle._visual.visible = false
	var b: Array = entry.bounds
	idle._visual.custom_aabb = AABB(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]))
	idle._visual.set_instance_shader_parameter("idle_phase", phase_for(identity))
	idle._visual.set_meta("bone_idle_payload", {"poses": poses, "frames": entry.frames, "fps": entry.fps})
	var textures := {}
	for surface: Dictionary in paths.get("materials", []):
		textures[int(surface.surface)] = surface
	for s in mesh.get_surface_count():
		idle._visual.set_surface_override_material(s, material_for(mesh.surface_get_material(s), poses, entry, textures.get(s, {})))
	idle.add_child(idle._visual)
	model.add_child(idle)
	return true


static func valid_resources(mesh: ArrayMesh, poses: ImageTexture, entry: Dictionary) -> bool:
	if mesh == null or poses == null or mesh.get_surface_count() == 0:
		return false
	if poses.get_width() != int(entry.bones) * 3 or poses.get_height() != int(entry.frames):
		return false
	for s in mesh.get_surface_count():
		var format := mesh.surface_get_format(s)
		if not (format & Mesh.ARRAY_FORMAT_CUSTOM0) or not (format & Mesh.ARRAY_FORMAT_CUSTOM1):
			return false
	return true


static func material_for(source: Material, poses: Texture2D, entry: Dictionary, textures: Dictionary = {}) -> ShaderMaterial:
	var base := source as StandardMaterial3D
	var key := [source.get_instance_id() if source else 0, poses.get_instance_id(), entry.frames, entry.fps, textures]
	if _materials.has(key) and _materials[key].get_ref() != null:
		return _materials[key].get_ref()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("pose_tex", poses)
	mat.set_shader_parameter("frames", int(entry.frames))
	mat.set_shader_parameter("fps", float(entry.fps))
	if base:
		mat.set_shader_parameter("albedo_tex", base.albedo_texture)
		mat.set_shader_parameter("albedo_tint", base.albedo_color)
		mat.set_shader_parameter("normal_tex", base.normal_texture)
		mat.set_shader_parameter("has_normal", base.normal_enabled and base.normal_texture != null)
		mat.set_shader_parameter("normal_scale", base.normal_scale)
	if textures.has("albedo"):
		mat.set_shader_parameter("albedo_tex", CtexLoader.load_ctex(textures.albedo))
	if textures.has("normal"):
		mat.set_shader_parameter("normal_tex", CtexLoader.load_ctex(textures.normal))
		mat.set_shader_parameter("has_normal", true)
	_materials[key] = weakref(mat)
	return mat


static func overlay_for(mesh: MeshInstance3D, source: StandardMaterial3D) -> Material:
	if not mesh.has_meta("bone_idle_payload"):
		return source
	var data: Dictionary = mesh.get_meta("bone_idle_payload")
	var key := [source.get_instance_id(), data.poses.get_instance_id(), data.frames, data.fps]
	if _overlays.has(key) and _overlays[key].get_ref() != null:
		return _overlays[key].get_ref()
	var mat := ShaderMaterial.new()
	mat.shader = OVERLAY
	mat.set_shader_parameter("pose_tex", data.poses)
	mat.set_shader_parameter("frames", data.frames)
	mat.set_shader_parameter("fps", data.fps)
	mat.set_shader_parameter("tint", source.albedo_color)
	mat.set_shader_parameter("emission_color", source.emission * source.emission_energy_multiplier if source.emission_enabled else Color.BLACK)
	mat.set_shader_parameter("shell", source.grow_amount if source.grow else 0.0)
	_overlays[key] = weakref(mat)
	return mat


static func set_dead(model: Node3D, dead: bool) -> void:
	for idle in model.find_children("BoneTextureIdle", "Node3D", true, false):
		if idle is BoneTextureIdle:
			idle._dead = dead
			idle.refresh()


func _ready() -> void:
	GraphicsSettings.idle_motion_changed.connect(refresh)
	GraphicsSettings.settings_applied.connect(_preset_changed)
	_preset_changed("")


func _preset_changed(_preset: String) -> void:
	refresh()
	var rim: float = GraphicsSettings.PRESETS[GraphicsSettings.current_preset].get("miniature_rim", 0.0)
	for s in _visual.mesh.get_surface_count():
		(_visual.get_surface_override_material(s) as ShaderMaterial).set_shader_parameter("rim_amount", rim)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_inside_tree() or _visual == null:
		return
	var camera := get_viewport().get_camera_3d()
	var active := not _dead and camera != null and motion_allowed(GraphicsSettings.current_preset,
		GraphicsSettings.idle_motion, GraphicsSettings.reduce_motion)
	if active:
		active = camera.global_position.distance_squared_to(global_position) <= MAX_DISTANCE * MAX_DISTANCE
	_visual.visible = active
	for i in _static_meshes.size():
		_static_meshes[i].visible = _original_visibility[i] and not active
