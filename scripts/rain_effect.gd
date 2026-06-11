class_name RainEffect
extends Node3D
## Table-wide rain: one GPUParticles3D box emitter dropping elongated streak billboards
## onto the play field, plus a dedicated lightning flash light. Owned by
## AtmosphereController; sized via set_table_size (follows table resizes).
##
## Drop speed is stylized (real ~9 m/s reads as flicker at miniature scale). `amount`
## restarts the particle system, so it is only recomputed on resize/quality change —
## runtime on/off fades through amount_ratio + emitting.

# === Constants ===

const EMIT_HEIGHT_M := 1.0
const DROP_SPEED_MPS := 2.5
const DROP_SIZE_M := Vector2(0.0012, 0.035)
const DROP_COLOR := Color(0.75, 0.8, 0.9, 0.4)
const BASE_DROPS_PER_M2 := 350.0
const TABLE_MARGIN := 1.1  # emission box 10% wider than the table
const FADE_SECONDS := 1.5

const FLASH_ENERGY := 2.5
const FLASH_COLOR := Color(0.9, 0.93, 1.0)
const FLASH_RISE_S := 0.04
const FLASH_FALL_S := 0.12
const DOUBLE_STROKE_CHANCE := 0.4
const DOUBLE_STROKE_GAP_S := 0.12

## Drop-count scale per graphics quality tier (PERFORMANCE..ULTRA order).
const TIER_AMOUNT_SCALE: Array[float] = [0.25, 0.5, 1.0, 1.25, 1.25]
const WEB_AMOUNT_SCALE := 0.5

# === Private variables ===

var _particles: GPUParticles3D = null
var _flash: DirectionalLight3D = null
var _fade_tween: Tween = null
var _flash_tween: Tween = null
var _rng := RandomNumberGenerator.new()
var _table_size := Vector2(1.22, 1.22)
var _raining := false

# === Lifecycle ===

func _ready() -> void:
	_rng.randomize()  # visual-only randomness (flash strokes)

	_particles = GPUParticles3D.new()
	_particles.emitting = false
	_particles.amount_ratio = 0.0
	_particles.lifetime = EMIT_HEIGHT_M / DROP_SPEED_MPS
	_particles.local_coords = true
	_particles.position.y = EMIT_HEIGHT_M

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.direction = Vector3.DOWN
	process.spread = 2.0
	process.initial_velocity_min = DROP_SPEED_MPS * 0.9
	process.initial_velocity_max = DROP_SPEED_MPS * 1.1
	process.gravity = Vector3.ZERO  # constant velocity reads better over a 1 m fall
	_particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = DROP_SIZE_M
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y  # streaks stay vertical
	mat.albedo_color = DROP_COLOR
	mat.disable_receive_shadows = true
	quad.material = mat
	_particles.draw_pass_1 = quad
	add_child(_particles)

	_flash = DirectionalLight3D.new()
	_flash.light_energy = 0.0
	_flash.light_color = FLASH_COLOR
	_flash.shadow_enabled = false
	_flash.rotation_degrees = Vector3(-65.0, 20.0, 0.0)
	add_child(_flash)

	_apply_emission_size()
	GraphicsSettings.settings_applied.connect(_on_quality_changed)

# === Public ===

## Resize the emission box + drop count to the table (metres). Restarts the system —
## call only on actual size changes.
func set_table_size(size_m: Vector2) -> void:
	if size_m.is_equal_approx(_table_size):
		return
	_table_size = size_m
	_apply_emission_size()


## Fade the rain in or out (runtime-safe: tweens amount_ratio, no restart).
func set_raining(on: bool) -> void:
	if on == _raining:
		return
	_raining = on
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	if on:
		_particles.emitting = true
		_fade_tween.tween_property(_particles, "amount_ratio", 1.0, FADE_SECONDS)
	else:
		_fade_tween.tween_property(_particles, "amount_ratio", 0.0, FADE_SECONDS)
		_fade_tween.tween_callback(func() -> void: _particles.emitting = false)


## One lightning flash (sometimes a double stroke) on the dedicated flash light —
## never the sun, so a flash can't corrupt a running atmosphere transition.
func flash_lightning() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "light_energy", FLASH_ENERGY, FLASH_RISE_S)
	_flash_tween.tween_property(_flash, "light_energy", 0.0, FLASH_FALL_S)
	if _rng.randf() < DOUBLE_STROKE_CHANCE:
		_flash_tween.tween_interval(DOUBLE_STROKE_GAP_S)
		_flash_tween.tween_property(_flash, "light_energy", FLASH_ENERGY * 0.7, FLASH_RISE_S)
		_flash_tween.tween_property(_flash, "light_energy", 0.0, FLASH_FALL_S)

# === Private ===

func _apply_emission_size() -> void:
	var process := _particles.process_material as ParticleProcessMaterial
	var extents := Vector3(_table_size.x * TABLE_MARGIN / 2.0, 0.02, _table_size.y * TABLE_MARGIN / 2.0)
	process.emission_box_extents = extents

	var tier := clampi(GraphicsSettings.current_preset, 0, TIER_AMOUNT_SCALE.size() - 1)
	var scale_factor := TIER_AMOUNT_SCALE[tier]
	if OS.has_feature("web"):
		scale_factor *= WEB_AMOUNT_SCALE
	var area := _table_size.x * TABLE_MARGIN * _table_size.y * TABLE_MARGIN
	_particles.amount = maxi(16, int(area * BASE_DROPS_PER_M2 * scale_factor))


func _on_quality_changed(_preset_name: String) -> void:
	_apply_emission_size()
