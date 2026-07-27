class_name FireProp
extends Node3D
## A small battlefield fire at miniature scale (~1.5 cm flames): additive flame
## particles, an optional rising smoke column and an optional flickering warm
## OmniLight3D. Spawned deterministically at ruin walls by terrain_overlay.gd
## (the "war-torn" toggle); purely decorative, no collision.

# === Constants ===

const FLAME_AMOUNT := 12
const FLAME_LIFETIME_S := 0.5
const FLAME_HEIGHT_M := 0.018      # flames rise ~1.5-2 cm
const FLAME_BASE_RADIUS_M := 0.006
const FLAME_QUAD_M := 0.008
const FLAME_HDR_ENERGY := 2.0      # readable without glow; ACES washes hotter stacks out

const SMOKE_AMOUNT := 8
const SMOKE_LIFETIME_S := 2.5
const SMOKE_RISE_M := 0.08         # 6-8 cm column
const SMOKE_QUAD_M := 0.012
const SMOKE_WIND_DRIFT := Vector3(0.01, 0.0, 0.006)  # matches the ground-mist drift
const SMOKE_COLOR := Color(0.35, 0.34, 0.33, 0.55)

const LIGHT_ENERGY_BASE := 0.18
const LIGHT_ENERGY_FLICKER := 0.07
const LIGHT_RANGE_M := 0.15
const LIGHT_COLOR := Color(1.0, 0.55, 0.2)
## Two incommensurate sine frequencies make a cheap organic flicker. Kept SLOW
## (a gentle breathing glow): faster values read as nervous strobing at table scale.
const FLICKER_HZ_A := 2.3
const FLICKER_HZ_B := 4.7

const GRADIENT_TEXTURE_SIZE := 64

# === Private variables ===

var _light: OmniLight3D = null
var _time := 0.0
var _phase := 0.0

# === Lifecycle ===

func _process(delta: float) -> void:
	# Pure float math, no allocations. Guard the light: _process is enabled by default on any
	# node that defines it, so it can tick in the window before setup() runs (or when setup was
	# called with_light=false) — flickering a null light spammed the headless log 68k×/run.
	if _light == null:
		return
	_time += delta
	_light.light_energy = LIGHT_ENERGY_BASE + LIGHT_ENERGY_FLICKER \
			* (0.6 * sin(_time * TAU * FLICKER_HZ_A + _phase)
			+ 0.4 * sin(_time * TAU * FLICKER_HZ_B + _phase * 1.7))

# === Public ===

## Build the fire. rng_seed varies the flicker phase per fire; with_light/with_smoke
## let the caller gate cost by graphics quality tier.
func setup(rng_seed: int, with_light: bool, with_smoke: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	_phase = rng.randf() * TAU

	add_child(_make_flames())
	if with_smoke:
		add_child(_make_smoke())
	if with_light:
		_light = OmniLight3D.new()
		_light.light_color = LIGHT_COLOR
		_light.light_energy = LIGHT_ENERGY_BASE
		_light.omni_range = LIGHT_RANGE_M
		_light.shadow_enabled = false
		_light.position.y = FLAME_HEIGHT_M * 0.6
		add_child(_light)
	set_process(with_light)

# === Private ===

func _make_flames() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = FLAME_AMOUNT
	particles.lifetime = FLAME_LIFETIME_S
	particles.local_coords = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = FLAME_BASE_RADIUS_M
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = FLAME_HEIGHT_M / FLAME_LIFETIME_S * 0.8
	process.initial_velocity_max = FLAME_HEIGHT_M / FLAME_LIFETIME_S * 1.2
	process.gravity = Vector3.ZERO  # default -9.8 is catastrophic at 1.5 cm scale
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.15))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	process.scale_curve = shrink_tex
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(FLAME_QUAD_M, FLAME_QUAD_M)
	quad.material = _billboard_material(
			_soft_dot_texture(Color(1.0, 0.85, 0.35), Color(1.0, 0.35, 0.05)),
			BaseMaterial3D.BLEND_MODE_ADD, FLAME_HDR_ENERGY)
	particles.draw_pass_1 = quad
	return particles


func _make_smoke() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = SMOKE_AMOUNT
	particles.lifetime = SMOKE_LIFETIME_S
	particles.local_coords = false  # smoke trails in world space when the piece moves
	# Above the ground-mist planes in the transparent queue (they hug y=4-6 mm).
	particles.position.y = FLAME_HEIGHT_M

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = FLAME_BASE_RADIUS_M
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = SMOKE_RISE_M / SMOKE_LIFETIME_S * 0.8
	process.initial_velocity_max = SMOKE_RISE_M / SMOKE_LIFETIME_S * 1.2
	# Constant sideways "wind" (via gravity) so columns lean with the mist drift; the
	# default -9.8 gravity would be catastrophic at this scale.
	process.gravity = SMOKE_WIND_DRIFT
	process.linear_accel_min = 0.002
	process.linear_accel_max = 0.004
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.8))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	process.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	process.color_ramp = fade_tex
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(SMOKE_QUAD_M, SMOKE_QUAD_M)
	var mat := _billboard_material(
			_soft_dot_texture(SMOKE_COLOR, Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.0)),
			BaseMaterial3D.BLEND_MODE_MIX, 1.0)
	mat.render_priority = 1  # draw over the ground-mist planes, not under them
	quad.material = mat
	particles.draw_pass_1 = quad
	return particles


## Unshaded billboard particle material with vertex-color modulation (for color ramps).
func _billboard_material(tex: Texture2D, blend: BaseMaterial3D.BlendMode, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	if energy > 1.0:
		mat.emission_enabled = true
		mat.emission_texture = tex
		mat.emission_energy_multiplier = energy
	mat.disable_receive_shadows = true
	return mat


## Soft radial gradient dot from core to edge colour (alpha falls off to 0 at the rim).
## Same approach as the cinematic intro's data motes, parameterized by colour ramp.
func _soft_dot_texture(core: Color, edge: Color) -> ImageTexture:
	var size := GRADIENT_TEXTURE_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center) / (size / 2.0)
			var t := clampf(d, 0.0, 1.0)
			var color := core.lerp(edge, t)
			color.a *= clampf(1.0 - t * t, 0.0, 1.0)
			img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
