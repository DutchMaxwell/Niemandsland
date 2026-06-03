extends Node3D
## Low, white, drifting ground mist that wafts a centimetre or two above the table.
##
## Replaces both the old high noise-plane "clouds" and the later FogVolume pockets: a
## volumetric FogVolume cannot resolve a 1–2 cm layer at table scale (the froxel grid
## is far too coarse, and it inherited a warm/brown tint). This uses a few very thin,
## soft, animated shader planes hugging the surface — white, drifting via TIME, with a
## little parallax between layers for a hint of volume. Follows the camera target so
## the mist stays under the viewed area.

# === Constants ===

const MIST_SHADER: Shader = preload("res://shaders/ground_mist.gdshader")
## Plane edge length (metres) — covers a 4x4 ft (1.22 m) table with margin.
const PLANE_SIZE: float = 1.5
## Heights above the table for the stacked layers (metres) — 12–20 mm: low waft.
const LAYER_HEIGHTS: Array = [0.012, 0.016, 0.020]
const MIST_COLOR: Color = Color(0.92, 0.94, 0.97)
const NOISE_SIZE: int = 512

# === Public references ===

## Assigned by main.gd; provides _target_position for the follow behaviour.
var camera_controller: Node3D = null

# === Private variables ===

var _layers: Array[MeshInstance3D] = []
var _enabled: bool = true
var _last_target: Vector3 = Vector3(INF, INF, INF)

# === Lifecycle ===

func _ready() -> void:
	_create_mist_layers()
	await get_tree().process_frame
	_find_camera_controller()


func _process(_delta: float) -> void:
	# Drift is TIME-driven in the shader; here we only keep the mist under the view.
	if not _enabled:
		return
	if not camera_controller:
		_find_camera_controller()
	if camera_controller and "_target_position" in camera_controller:
		var target: Vector3 = camera_controller._target_position
		if not target.is_equal_approx(_last_target):
			global_position.x = target.x
			global_position.z = target.z
			_last_target = target

# === Public API (kept stable for main.gd / future preset hooks) ===

## Tint the mist (kept white by default).
func set_cloud_color(color: Color) -> void:
	for layer: MeshInstance3D in _layers:
		var mat := layer.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("mist_color", color)


## Set the drift direction; the passed vector scales the scroll speed per layer.
func set_wind_direction(direction: Vector2) -> void:
	var base: Vector2 = direction if direction.length() > 0.0001 else Vector2(0.012, 0.007)
	for i in range(_layers.size()):
		var mat := _layers[i].material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("scroll", base.rotated(float(i) * 1.3))


## Enable/disable the mist.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled


## Shift the mist tint for the time of day (kept subtle; daylight = white).
func set_time_of_day(hour: float) -> void:
	var color: Color
	if hour < 6.0 or hour > 20.0:
		color = Color(0.7, 0.74, 0.85)     # night — cool
	elif hour < 8.0 or hour > 18.0:
		color = Color(0.96, 0.9, 0.85)     # dawn/dusk — warm
	else:
		color = MIST_COLOR                  # day — white
	set_cloud_color(color)

# === Private helpers ===

func _create_mist_layers() -> void:
	var noise := _make_noise()
	for i in range(LAYER_HEIGHTS.size()):
		var mesh_inst := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(PLANE_SIZE, PLANE_SIZE)
		mesh_inst.mesh = plane

		var mat := ShaderMaterial.new()
		mat.shader = MIST_SHADER
		mat.set_shader_parameter("noise_tex", noise)
		mat.set_shader_parameter("mist_color", MIST_COLOR)
		mat.set_shader_parameter("density", 0.95 - float(i) * 0.15)
		mat.set_shader_parameter("tiling", 2.2 + float(i) * 0.7)
		mat.set_shader_parameter("scroll", Vector2(0.012, 0.007).rotated(float(i) * 1.3))
		mat.set_shader_parameter("wisp", 0.34 + float(i) * 0.05)
		mesh_inst.material_override = mat

		mesh_inst.position.y = LAYER_HEIGHTS[i]
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_inst)
		_layers.append(mesh_inst)


func _make_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.015
	noise.fractal_octaves = 4

	var tex := NoiseTexture2D.new()
	tex.width = NOISE_SIZE
	tex.height = NOISE_SIZE
	tex.seamless = true
	tex.noise = noise
	return tex


func _find_camera_controller() -> void:
	var cameras := get_tree().get_nodes_in_group("camera_controller")
	if cameras.size() > 0:
		camera_controller = cameras[0]
		return
	camera_controller = get_node_or_null("/root/Main/CameraController")
