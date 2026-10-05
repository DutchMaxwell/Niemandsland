class_name BoneTextureIdle
extends Node3D
## Optional visual payload; the static miniature owns fitting, collisions, rules and saves.

const SHADER := preload("res://shaders/idle/bone_texture.gdshader")
const OVERLAY := preload("res://shaders/idle/bone_overlay.gdshader")
const MAX_DISTANCE := 0.85
static var _materials: Dictionary = {}
static var _overlays: Dictionary = {}

static func valid_entry(entry: Dictionary) -> bool:
	return BoneTexturePayload.valid_entry(entry)

static func phase_for(identity: String) -> float:
	return float(identity.sha256_text().substr(0, 8).hex_to_int()) / 4294967296.0


static func motion_allowed(preset: int, requested: bool, reduced: bool) -> bool:
	return preset >= 2 and requested and not reduced


## Return false without touching the original scene on absent, partial or invalid payloads.


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
