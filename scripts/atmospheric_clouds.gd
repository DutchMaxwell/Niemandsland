extends Node3D
## Low, drifting ground mist that wafts a few millimetres above the table.
##
## A volumetric FogVolume cannot resolve a sub-centimetre layer at table scale, so this
## uses a couple of very thin, soft, animated shader planes hugging the surface. The mist
## is LIT (scene lights tint it — the green selection spill, the star), drifts via TIME,
## thins out into gaps (it does not blanket the whole field), is parted around miniatures
## (clear_points, which follow them as they move), and fades in only after the table is
## built (global_alpha, driven by fade_in() on intro end). Follows the camera target.

# === Constants ===

const MIST_SHADER: Shader = preload("res://shaders/ground_mist.gdshader")
## Fallback plane edge length (metres) before set_table_size() sizes it to the table.
const PLANE_SIZE: float = 1.85
## Heights above the table for the stacked layers (metres) — ~4–6 mm: hugs the ground.
const LAYER_HEIGHTS: Array = [0.004, 0.006]
const MIST_COLOR: Color = Color(0.95, 0.96, 0.98)
const NOISE_SIZE: int = 512
## Water-like parting around each miniature: reach, outward shove, tangential swirl, core.
const CLEAR_RADIUS: float = 0.09
const PUSH_AMOUNT: float = 0.06
const SWIRL_AMOUNT: float = 0.03
const CORE_CLEAR: float = 0.35
## Max miniatures that part the mist at once (matches the shader array).
const MAX_CLEAR: int = 32
## How often (seconds) to refresh the parting points — 20 Hz is smooth + cheap.
const CLEAR_INTERVAL: float = 0.05
## Default fade-in duration once the table is built (seconds).
const FADE_IN_TIME: float = 4.0

# === Public references ===

## Kept for compatibility (main.gd assigns it); the table-bound mist no longer follows it.
var camera_controller: Node3D = null

# === Private variables ===

var _layers: Array[MeshInstance3D] = []
var _enabled: bool = true
var _global_alpha: float = 0.0
var _clear_accum: float = 0.0
var _fade_tween: Tween = null

# === Lifecycle ===

func _ready() -> void:
	_create_mist_layers()
	_set_global_alpha(0.0)  # hidden until the table is built (fade_in)


func _process(delta: float) -> void:
	if not _enabled:
		return
	# The mist is table-bound (centred on the table at the origin), so it no longer
	# follows the camera. Refresh the parting points (throttled) so it reacts to models.
	_clear_accum += delta
	if _clear_accum >= CLEAR_INTERVAL:
		_clear_accum = 0.0
		_update_clear_points()

# === Public API ===

## Size the mist to cover the whole play field (call when the table size is set). A small
## margin past the edge keeps the soft border out past the table rim.
func set_table_size(size_meters: Vector2) -> void:
	var plane_size := size_meters + Vector2(0.08, 0.08)
	for layer: MeshInstance3D in _layers:
		var plane := layer.mesh as PlaneMesh
		if plane:
			plane.size = plane_size


## Slowly reveal the mist (call once the table/field is built — e.g. on intro end).
func fade_in(duration: float = FADE_IN_TIME) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_global_alpha, _global_alpha, 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Tint the mist (kept near-white by default; the lighting does the rest).
func set_cloud_color(color: Color) -> void:
	for layer: MeshInstance3D in _layers:
		var mat := layer.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("mist_color", color)


## Set the drift direction; the passed vector scales the scroll speed per layer.
func set_wind_direction(direction: Vector2) -> void:
	var base: Vector2 = direction if direction.length() > 0.0001 else Vector2(0.011, 0.006)
	for i in range(_layers.size()):
		var mat := _layers[i].material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("scroll", base.rotated(float(i) * 1.6))


## Enable/disable the mist.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled


## Shift the mist tint for the time of day (kept subtle; daylight = white).
func set_time_of_day(hour: float) -> void:
	var color: Color
	if hour < 6.0 or hour > 20.0:
		color = Color(0.74, 0.78, 0.88)    # night — cool
	elif hour < 8.0 or hour > 18.0:
		color = Color(0.97, 0.92, 0.86)    # dawn/dusk — warm
	else:
		color = MIST_COLOR                  # day — white
	set_cloud_color(color)

# === Private helpers ===

func _set_global_alpha(value: float) -> void:
	_global_alpha = value
	for layer: MeshInstance3D in _layers:
		var mat := layer.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("global_alpha", value)


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
		mat.set_shader_parameter("density", 0.32 - float(i) * 0.1)
		mat.set_shader_parameter("noise_freq", 1.3 + float(i) * 0.4)
		mat.set_shader_parameter("scroll", Vector2(0.012, 0.007).rotated(float(i) * 1.6))
		mat.set_shader_parameter("coverage", 0.55 + float(i) * 0.06)
		mat.set_shader_parameter("softness", 0.32)
		mat.set_shader_parameter("push_radius", CLEAR_RADIUS)
		mat.set_shader_parameter("push_amount", PUSH_AMOUNT)
		mat.set_shader_parameter("swirl_amount", SWIRL_AMOUNT)
		mat.set_shader_parameter("core_clear", CORE_CLEAR)
		mesh_inst.material_override = mat

		mesh_inst.position.y = LAYER_HEIGHTS[i]
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_inst)
		_layers.append(mesh_inst)


## Push the array of miniature offsets (plane-local XZ, metres) to the shaders.
func _update_clear_points() -> void:
	var pts := PackedVector2Array()
	pts.resize(MAX_CLEAR)
	for j in range(MAX_CLEAR):
		pts[j] = Vector2(1000.0, 1000.0)  # sentinel: far away, clears nothing

	var center: Vector3 = global_position
	var half: float = PLANE_SIZE * 0.5
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("miniature"):
		if count >= MAX_CLEAR:
			break
		var mini := node as Node3D
		if mini == null:
			continue
		var ox: float = mini.global_position.x - center.x
		var oz: float = mini.global_position.z - center.z
		if absf(ox) <= half and absf(oz) <= half:
			pts[count] = Vector2(ox, oz)
			count += 1

	for layer: MeshInstance3D in _layers:
		var mat := layer.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("clear_points", pts)
			mat.set_shader_parameter("clear_count", count)


func _make_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_octaves = 3

	var tex := NoiseTexture2D.new()
	tex.width = NOISE_SIZE
	tex.height = NOISE_SIZE
	tex.seamless = true
	tex.noise = noise
	return tex
