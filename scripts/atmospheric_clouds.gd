extends Node3D
## Drifting low-lying atmospheric mist across the battlefield.
##
## Replaces the old flat noise-plane "cloud" layers (which read as cheap 2010s-TTS
## garbage) with real volumetric FogVolume pockets that integrate with the
## WorldEnvironment's volumetric fog. The pockets drift on the wind and follow the
## camera target so the viewed area always sits in a soft, patchy haze.
##
## The mist only renders where volumetric fog is enabled (MEDIUM+ presets), so on
## low presets the FogVolumes are effectively free and invisible.

# === Constants ===

## Number of drifting mist pockets scattered over the play area.
const NUM_POCKETS: int = 6
## Centre height of the mist above the table (metres) — hugs the ground.
const POCKET_HEIGHT: float = 0.06
## Ellipsoid extent of each pocket (metres). Must be ~>1 m or the volumetric-fog
## froxel grid (tuned for outdoor scale) cannot resolve it; kept low and wide so it
## reads as ground mist rather than a cloud bank.
const POCKET_SIZE: Vector3 = Vector3(1.25, 0.28, 1.25)
## Half-extent of the square area the pockets roam/wrap within (metres).
const DRIFT_AREA: float = 0.6
## Per-metre extinction inside a pocket (modulated down by the noise texture; added
## on top of the thin base volumetric fog). Subtle so it never floods the table.
const BASE_DENSITY: float = 0.9
## Mist tint (neutral cool white by default; retuned by set_time_of_day).
const MIST_ALBEDO: Color = Color(0.85, 0.87, 0.92)
## Golden-ratio scatter so the initial pockets do not line up on a ring.
const GOLDEN: float = 0.6180339887

# === Public references ===

## Assigned by main.gd; provides _target_position for the follow behaviour.
var camera_controller: Node3D = null

# === Private variables ===

var _pockets: Array[FogVolume] = []
var _wind: Vector2 = Vector2(0.018, 0.011)
var _enabled: bool = true
var _last_target: Vector3 = Vector3(INF, INF, INF)

# === Lifecycle ===

func _ready() -> void:
	_create_mist_pockets()
	await get_tree().process_frame
	_find_camera_controller()


func _process(delta: float) -> void:
	if not _enabled:
		return

	if not camera_controller:
		_find_camera_controller()

	# Keep the mist centred on the viewed area.
	if camera_controller and "_target_position" in camera_controller:
		var target: Vector3 = camera_controller._target_position
		if not target.is_equal_approx(_last_target):
			global_position.x = target.x
			global_position.z = target.z
			_last_target = target

	# Drift the pockets on the wind, wrapping within the drift area.
	for pocket: FogVolume in _pockets:
		var p: Vector3 = pocket.position
		p.x += _wind.x * delta
		p.z += _wind.y * delta
		if p.x > DRIFT_AREA:
			p.x -= DRIFT_AREA * 2.0
		elif p.x < -DRIFT_AREA:
			p.x += DRIFT_AREA * 2.0
		if p.z > DRIFT_AREA:
			p.z -= DRIFT_AREA * 2.0
		elif p.z < -DRIFT_AREA:
			p.z += DRIFT_AREA * 2.0
		pocket.position = p

# === Public API (kept stable for main.gd / future preset hooks) ===

## Tint all mist pockets.
func set_cloud_color(color: Color) -> void:
	for pocket: FogVolume in _pockets:
		var mat := pocket.material as FogMaterial
		if mat:
			mat.albedo = color


## Set the drift wind (table-space units/second); direction is normalised, the
## passed length scales the speed.
func set_wind_direction(direction: Vector2) -> void:
	if direction.length() > 0.0001:
		_wind = direction.normalized() * 0.02 * clampf(direction.length(), 0.5, 2.0)


## Enable/disable the mist.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled


## Shift the mist tint for the time of day.
func set_time_of_day(hour: float) -> void:
	var color: Color
	if hour < 6.0 or hour > 20.0:
		color = Color(0.4, 0.45, 0.6)      # night — cool blue
	elif hour < 8.0 or hour > 18.0:
		color = Color(0.95, 0.82, 0.72)    # dawn/dusk — warm
	else:
		color = Color(0.85, 0.87, 0.92)    # day — neutral cool white
	set_cloud_color(color)

# === Private helpers ===

func _create_mist_pockets() -> void:
	var noise_tex := _make_mist_noise()
	for i in range(NUM_POCKETS):
		var fog := FogVolume.new()
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		fog.size = POCKET_SIZE

		var mat := FogMaterial.new()
		mat.density = BASE_DENSITY
		mat.albedo = MIST_ALBEDO
		mat.edge_fade = 0.5
		mat.height_falloff = 3.0
		mat.density_texture = noise_tex
		fog.material = mat

		# Scatter across the drift area (golden-ratio angle + varied radius).
		var ang: float = TAU * float(i) * GOLDEN
		var radius: float = DRIFT_AREA * (0.25 + 0.7 * fposmod(float(i + 1) * GOLDEN, 1.0))
		fog.position = Vector3(cos(ang) * radius, POCKET_HEIGHT, sin(ang) * radius)

		add_child(fog)
		_pockets.append(fog)


func _make_mist_noise() -> NoiseTexture3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.025
	noise.fractal_octaves = 3

	var tex := NoiseTexture3D.new()
	tex.width = 48
	tex.height = 24
	tex.depth = 48
	tex.seamless = true
	tex.noise = noise
	return tex


func _find_camera_controller() -> void:
	var cameras := get_tree().get_nodes_in_group("camera_controller")
	if cameras.size() > 0:
		camera_controller = cameras[0]
		return
	camera_controller = get_node_or_null("/root/Main/CameraController")
