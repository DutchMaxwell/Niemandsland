extends Node3D
class_name TronIntro
## Cinematic launch sequence — directed in a Christopher Nolan / Interstellar register:
## a single unbroken ~12 s IMAX-style take. We open from black, drift in the void on a
## long lens (telephoto compression of the table against the stars), then begin a slow,
## relentless monumental descent while a cool "engineering blueprint" grid prints onto the
## table. At the reveal a restrained light-swell blooms (never a flash), the holo dissolves
## into the real table, a held breath of near-silence follows, then the IMAX letterbox bars
## retract and control is handed over — seamlessly, on the gameplay camera's resting pose.
##
## Everything is Tween-choreographed and driven through shader uniforms (no per-frame
## allocations). Deep blacks, disciplined bloom (no white-wash, no volumetric haze).
## Visuals scale with the GraphicsSettings preset; audio fires through the AudioManager
## autoload (files optional — missing ones warn, never crash).

# === Constants ===

## Single continuous take (seconds) — ONE relentless ease, no segment stop/start. ~12 s
## so the sequence can breathe (Nolan lets shots run); the camera glides in and decelerates
## to a dead stop on the gameplay pose, so the hand-off cut is invisible.
const FLIGHT_TIME: float = 11.5
const INTRO_FADE_IN: float = 1.5   # slow, deliberate rise from black

## Blueprint grid build timeline — the void breathes first, then the grid prints over the
## descent and dissolves into the real table.
const BUILD_START_DELAY: float = 2.5
const BUILD_TIME: float = 5.0
const HANDOFF_FADE: float = 1.8    # holo grid fade-out
const TABLE_FADE_TIME: float = 1.8 # real table fades in (cross-dissolves with the grid)

## Sky / brightness: dim the star-wash during the boot, then ease back to the gameplay
## values over the final stretch so the white fades out into the calm star field.
const STAR_BRIGHTNESS_INTRO: float = 0.45
const GLOW_BLOOM_INTRO: float = 0.28
const GLOW_THRESHOLD_INTRO: float = 1.25
## All hand-off transitions FINISH ~0.5 s before the camera cut, so the final beat is
## completely still — no brightness/DOF/vignette change at the moment control is handed over.
const ENV_SETTLE_START: float = 8.6   # when the white begins fading out
const ENV_SETTLE_TIME: float = 2.4    # ends at 11.0 s (cut is at FLIGHT_TIME = 11.5 s)

## IMAX letterbox bars (2.39:1) that retract into the gameplay frame at the hand-off.
const LETTERBOX_ASPECT: float = 2.39
const BAR_RETRACT_START: float = 10.2
const BAR_RETRACT_TIME: float = 1.3   # ends at 11.5 s = the cut

## Camera framing. A long lens (tight FOV) compresses the distant table against the stars —
## the telephoto look that opens many Nolan/IMAX vistas — easing out to the gameplay FOV.
const FOV_START: float = 30.0
const FALLBACK_FOV: float = 60.0

## A subtle "shot-on-film" gate weave on the camera, faded out as it settles.
const WEAVE_AMPLITUDE: float = 0.035

## Start far, high and back ON the gameplay axis (yaw 0): a clean monumental pitch-down
## descent with no lateral swing.
const POS_START := Vector3(0.0, 22.0, 34.0)
const FALLBACK_FINAL_POS := Vector3(0.0, 7.07, 7.07)
const LOOK_TARGET := Vector3(0.0, 0.0, 0.0)

## Holo grid — cool "engineering blueprint" light, not neon Tron cyan.
const GRID_SPACING: float = 0.1524   # ~6" between lines
const HOLO_HEIGHT: float = 0.03      # above the table surface to avoid z-fighting
const HOLO_COLOR := Color(0.55, 0.72, 1.0)
const HOLO_CORE_COLOR := Color(0.85, 0.92, 1.0)

## Particle "data motes".
const MOTE_SPHERE_RADIUS: float = 6.0
const MOTE_LIFETIME: float = 2.4
const MOTE_AMOUNT_FULL: int = 300
const MOTE_AMOUNT_LOW: int = 120

## Audio asset paths (drop matching .ogg files here to enable — optional). Designed for
## the Interstellar register: a low drone bed, a ticking clock (time), then an organ-like
## swell at the reveal, with a held breath of silence between tick and swell.
const AUDIO_DRONE := "res://assets/audio/music/intro_boot_drone.ogg"
const AUDIO_TICK := "res://assets/audio/ui/intro_ticking.ogg"
const AUDIO_SWELL := "res://assets/audio/ui/intro_swell.ogg"

## Shaders.
const HOLO_SHADER := preload("res://assets/shaders/intro_holo_grid.gdshader")
const SCREEN_FX_SHADER := preload("res://assets/shaders/intro_screen_fx.gdshader")

# === Signals ===

signal intro_finished
signal intro_skipped

# === Scene references ===

var main_scene: Node3D
var world_environment: WorldEnvironment
var table: Node3D
var original_camera_pivot: Node3D

# === Intro elements ===

var intro_camera: Camera3D
var holo_plane: MeshInstance3D
var holo_material: ShaderMaterial
var motes: GPUParticles3D
var energy_ring: MeshInstance3D
var ring_material: StandardMaterial3D
var canvas_layer: CanvasLayer
var black_overlay: ColorRect
var screen_fx_rect: ColorRect
var screen_fx_material: ShaderMaterial
var top_bar: ColorRect
var bottom_bar: ColorRect
var skip_label: Label

# === State ===

var _is_playing: bool = false
var _tweens: Array[Tween] = []
var _weave_phase: float = 0.0   # accumulated time for the camera gate weave
var _bars_retracting: bool = false   # stop size-driven resizing once the bars open

## Saved originals (restored on finish/skip so nothing leaks into gameplay).
var _orig_bg_mode: int = Environment.BG_SKY
var _orig_bg_color: Color = Color.BLACK
var _orig_glow_enabled: bool = false
var _orig_glow_intensity: float = 1.0
var _orig_glow_bloom: float = 0.0
var _orig_glow_blend: int = Environment.GLOW_BLEND_MODE_SOFTLIGHT
var _orig_glow_threshold: float = 1.0
var _orig_fog_enabled: bool = false
var _orig_cam_attributes: CameraAttributes = null

## Skybox star brightness is dimmed during the intro then eased back, so the white
## star-wash fades out into the calm gameplay star field on hand-off.
var _sky_material: ShaderMaterial = null
var _orig_star_brightness: float = 1.1


# === Lifecycle ===

func _input(event: InputEvent) -> void:
	if not _is_playing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_skip_intro()
	elif event is InputEventMouseButton and event.pressed:
		_skip_intro()


# === Public API ===

## Start the intro. `main` is the gameplay root (Main).
func play_intro(main: Node3D) -> void:
	main_scene = main
	world_environment = main.get_node_or_null("WorldEnvironment")
	table = main.get_node_or_null("Table")
	original_camera_pivot = main.get_node_or_null("CameraPivot")

	_is_playing = true
	_save_environment()
	_hide_main_scene()
	_setup_environment()
	_create_overlay()
	_create_camera()
	_create_holo_grid()
	_create_motes()
	_create_energy_ring()

	# NOTE: the intro does not touch the gameplay UI. main.gd keeps it hidden during the
	# intro and fades it in only AFTER intro_finished, once the table is fully built.

	_play_audio_music(AUDIO_DRONE)
	_start_choreography()


# === Setup ===

func _save_environment() -> void:
	if not (world_environment and world_environment.environment):
		return
	var env := world_environment.environment
	_orig_bg_mode = env.background_mode
	_orig_bg_color = env.background_color
	_orig_glow_enabled = env.glow_enabled
	_orig_glow_intensity = env.glow_intensity
	_orig_glow_bloom = env.glow_bloom
	_orig_glow_blend = env.glow_blend_mode
	_orig_glow_threshold = env.glow_hdr_threshold
	_orig_fog_enabled = env.volumetric_fog_enabled

	# Skybox star brightness (dimmed during the boot, eased back on hand-off).
	if env.sky and env.sky.sky_material is ShaderMaterial:
		_sky_material = env.sky.sky_material
		var sb = _sky_material.get_shader_parameter("star_brightness")
		if sb != null:
			_orig_star_brightness = float(sb)


func _setup_environment() -> void:
	if not (world_environment and world_environment.environment):
		return
	var env := world_environment.environment

	# Keep the star-field skybox as the backdrop.
	env.background_mode = Environment.BG_SKY

	# Calm boot glow — same Softlight blend as gameplay and a raised HDR threshold so
	# clustered stars stay as crisp points instead of blooming into white sheets. The
	# strongly-emissive holo grid is far above the threshold, so it still blooms.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 1.2
	env.glow_bloom = GLOW_BLOOM_INTRO
	env.glow_hdr_threshold = GLOW_THRESHOLD_INTRO

	# NOTE: no volumetric fog. It scattered the scene's warm directional light into an
	# ugly brown wash over the whole intro, and rendering it sharp (DOF-free) for one
	# frame at the camera cut produced a bright flash. The skybox + holo glow read better.

	# Dim the star-wash while the camera is far (where the sky fills the frame).
	if _sky_material:
		_sky_material.set_shader_parameter("star_brightness", STAR_BRIGHTNESS_INTRO)


func _create_overlay() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	# Screen-space framing (vignette / chromatic aberration / grain / boot glitch).
	# Clean & smooth: only a soft cinematic vignette — no film grain / chromatic
	# aberration / scanlines / glitch (those read as "white noise" over the dark space).
	screen_fx_material = ShaderMaterial.new()
	screen_fx_material.shader = SCREEN_FX_SHADER
	screen_fx_material.set_shader_parameter("fx_strength", 1.0)
	screen_fx_material.set_shader_parameter("vignette_strength", 0.55)
	screen_fx_material.set_shader_parameter("aberration", 0.0)
	screen_fx_material.set_shader_parameter("grain_amount", 0.0)
	screen_fx_material.set_shader_parameter("scanline_strength", 0.0)
	screen_fx_material.set_shader_parameter("glitch_amount", 0.0)

	screen_fx_rect = ColorRect.new()
	screen_fx_rect.color = Color(1, 1, 1, 1)
	screen_fx_rect.material = screen_fx_material
	screen_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(screen_fx_rect)

	# IMAX letterbox bars (2.39:1), retract at hand-off. Height is set one frame later
	# (_init_letterbox_bars) once the viewport actually has a size — at _ready it is still 0.
	top_bar = ColorRect.new()
	top_bar.color = Color.BLACK
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 0.0
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(top_bar)

	bottom_bar = ColorRect.new()
	bottom_bar.color = Color.BLACK
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = 0.0
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(bottom_bar)
	# Size now, again next frame (viewport size is 0 during _ready), and on every later
	# resize (e.g. windowed→fullscreen) — until the bars retract.
	_apply_letterbox_bars()
	call_deferred("_apply_letterbox_bars")
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_apply_letterbox_bars)

	# Opening black fade.
	black_overlay = ColorRect.new()
	black_overlay.color = Color.BLACK
	black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(black_overlay)

	skip_label = Label.new()
	skip_label.text = "Press any key to skip"
	skip_label.add_theme_color_override("font_color", HOLO_COLOR.darkened(0.35))
	skip_label.add_theme_font_size_override("font_size", 14)
	skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_label.offset_left = -180
	skip_label.offset_top = -30
	skip_label.modulate.a = 0.0
	canvas_layer.add_child(skip_label)


func _create_camera() -> void:
	intro_camera = Camera3D.new()
	intro_camera.name = "IntroCamera"
	intro_camera.fov = FOV_START
	intro_camera.near = 0.05
	intro_camera.far = 200.0

	# Depth of field so the far backdrop is soft and the table "snaps" into focus.
	if _effects_enabled():
		var attrs := CameraAttributesPractical.new()
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = 14.0
		attrs.dof_blur_far_transition = 8.0
		attrs.dof_blur_amount = 0.1
		intro_camera.attributes = attrs

	add_child(intro_camera)
	intro_camera.global_transform = _look_xform(POS_START)
	intro_camera.current = true


func _create_holo_grid() -> void:
	var size_m := _table_size_m()
	var plane := PlaneMesh.new()
	plane.size = size_m

	holo_material = ShaderMaterial.new()
	holo_material.shader = HOLO_SHADER
	holo_material.set_shader_parameter("build_progress", 0.0)
	holo_material.set_shader_parameter("sweep_pos", 0.0)
	holo_material.set_shader_parameter("plane_radius", 0.5 * size_m.length())
	holo_material.set_shader_parameter("grid_spacing", GRID_SPACING)
	holo_material.set_shader_parameter("line_color", HOLO_COLOR)
	holo_material.set_shader_parameter("core_color", HOLO_CORE_COLOR)
	holo_material.set_shader_parameter("alpha", 1.0)

	holo_plane = MeshInstance3D.new()
	holo_plane.name = "HoloGrid"
	holo_plane.mesh = plane
	holo_plane.material_override = holo_material
	holo_plane.position = Vector3(0, HOLO_HEIGHT, 0)
	add_child(holo_plane)


func _create_motes() -> void:
	motes = GPUParticles3D.new()
	motes.name = "DataMotes"
	motes.amount = MOTE_AMOUNT_FULL if _effects_enabled() else MOTE_AMOUNT_LOW
	motes.lifetime = MOTE_LIFETIME
	motes.one_shot = true
	motes.explosiveness = 0.35
	motes.emitting = false
	motes.position = Vector3(0, HOLO_HEIGHT, 0)

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = MOTE_SPHERE_RADIUS
	proc.gravity = Vector3.ZERO
	proc.initial_velocity_min = 0.2
	proc.initial_velocity_max = 0.6
	proc.radial_accel_min = -7.0   # accelerate toward the emission centre = convergence
	proc.radial_accel_max = -4.0
	proc.damping_min = 1.0
	proc.damping_max = 2.0
	proc.scale_min = 0.4
	proc.scale_max = 1.0
	# Each mote gets a random colour sampled from a bright (HDR) rainbow ramp, so the
	# converging "data" sparkles in many colours instead of a single blue.
	proc.color = Color.WHITE
	proc.color_initial_ramp = _rainbow_ramp()
	motes.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)   # bigger so each mote's colour reads, not a 1px white dot
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# MIX (not ADD): additive sums overlapping motes to white and ACES desaturates the
	# highlights — MIX keeps each mote's colour saturated against the dark void.
	mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Soft round dot (radial alpha) tinted by the per-particle vertex colour, so each mote
	# is a soft coloured glow rather than a hard white square that washes out additively.
	mote_mat.albedo_color = Color.WHITE
	mote_mat.vertex_color_use_as_albedo = true
	mote_mat.albedo_texture = _soft_dot_texture()
	quad.material = mote_mat
	motes.draw_pass_1 = quad

	add_child(motes)


## A soft round dot (white centre → transparent edge) used as the mote sprite.
func _soft_dot_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex


## A bright (HDR) rainbow gradient — each mote samples a random colour from it.
func _rainbow_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	# Saturated, ~1.0-peak colours: bright enough to read on the dark void but NOT so HDR
	# that the ACES tonemap desaturates them back to white.
	grad.offsets = PackedFloat32Array([0.0, 0.17, 0.34, 0.5, 0.67, 0.84, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.08, 0.12),   # red
		Color(1.0, 0.5, 0.05),    # orange
		Color(0.9, 0.9, 0.1),     # yellow
		Color(0.1, 1.0, 0.2),     # green
		Color(0.1, 0.85, 1.0),    # cyan
		Color(0.2, 0.35, 1.0),    # blue
		Color(1.0, 0.15, 0.9),    # magenta
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _create_energy_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0

	ring_material = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_material.albedo_color = Color(0.8, 0.98, 1.0, 0.0)
	ring_material.emission_enabled = true
	ring_material.emission = HOLO_CORE_COLOR
	ring_material.emission_energy_multiplier = 2.5

	energy_ring = MeshInstance3D.new()
	energy_ring.name = "EnergyRing"
	energy_ring.mesh = torus
	energy_ring.material_override = ring_material
	energy_ring.position = Vector3(0, HOLO_HEIGHT, 0)
	energy_ring.scale = Vector3(0.05, 0.05, 0.05)
	energy_ring.visible = false
	add_child(energy_ring)


# === Choreography ===

func _start_choreography() -> void:
	var final_xform := _final_camera_xform()
	var final_fov := _final_camera_fov()

	# Opening black fade + skip prompt.
	var fade := create_tween()
	fade.tween_property(black_overlay, "modulate:a", 0.0, INTRO_FADE_IN)
	fade.parallel().tween_property(skip_label, "modulate:a", 0.5, INTRO_FADE_IN)
	_tweens.append(fade)

	# Camera: ONE continuous, velocity-smooth glide from far space onto the gameplay
	# angle. EASE_IN_OUT decelerates to zero at the end → gentle settle, no snap. The
	# end transform is the camera-controller's resting pose, so the hand-off is seamless.
	var cam := create_tween()
	cam.tween_method(_apply_cam.bind(_look_xform(POS_START), final_xform),
		0.0, 1.0, FLIGHT_TIME).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	cam.parallel().tween_property(intro_camera, "fov", final_fov, FLIGHT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam.tween_callback(_finish_intro)
	_tweens.append(cam)

	# Effects timeline: data-motes converge, the grid prints, then it ignites and
	# cross-fades into the real table — all finished well before the camera settles.
	var fx := create_tween()
	fx.tween_interval(BUILD_START_DELAY)
	fx.tween_callback(_begin_materialization)
	fx.tween_property(holo_material, "shader_parameter/build_progress", 1.0, BUILD_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fx.parallel().tween_property(holo_material, "shader_parameter/sweep_pos", 1.15, BUILD_TIME) \
		.set_trans(Tween.TRANS_SINE)
	fx.tween_callback(_ignite)
	fx.tween_property(holo_material, "shader_parameter/alpha", 0.0, HANDOFF_FADE) \
		.set_trans(Tween.TRANS_SINE)
	_tweens.append(fx)

	# (The gameplay UI is revealed by main.gd AFTER the intro finishes, not during it.)

	# Brightness settle: over the final stretch the boot bloom eases down and the dimmed
	# stars rise to full, so the white star-wash fades out and a crisp gameplay star field
	# resolves in — control begins on a proper starry sky, not a white frame.
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		var settle := create_tween()
		settle.tween_interval(ENV_SETTLE_START)
		settle.set_parallel(true)
		settle.tween_property(env, "glow_bloom", _orig_glow_bloom, ENV_SETTLE_TIME) \
			.set_trans(Tween.TRANS_SINE)
		settle.tween_property(env, "glow_hdr_threshold", _orig_glow_threshold, ENV_SETTLE_TIME) \
			.set_trans(Tween.TRANS_SINE)
		if _sky_material:
			settle.tween_property(_sky_material, "shader_parameter/star_brightness",
				_orig_star_brightness, ENV_SETTLE_TIME).set_trans(Tween.TRANS_SINE)
		# Ease the cinematic vignette and the camera's depth-of-field off BEFORE the cut,
		# so switching to the (DOF-free) gameplay camera is seamless — no last-second
		# sharpen-pop of the bloomed star field, no abrupt edge brightening.
		if screen_fx_material:
			settle.tween_property(screen_fx_material, "shader_parameter/fx_strength", 0.0,
				ENV_SETTLE_TIME).set_trans(Tween.TRANS_SINE)
		if intro_camera and intro_camera.attributes is CameraAttributesPractical:
			settle.tween_property(intro_camera, "attributes:dof_blur_amount", 0.0,
				ENV_SETTLE_TIME).set_trans(Tween.TRANS_SINE)
		_tweens.append(settle)

	# IMAX letterbox bars retract into the gameplay frame, finishing exactly at the cut —
	# the "step out of the cinema into the game" beat.
	if top_bar and bottom_bar:
		var bars := create_tween()
		bars.tween_interval(BAR_RETRACT_START)
		bars.tween_callback(func() -> void: _bars_retracting = true)
		bars.set_parallel(true)
		bars.tween_property(top_bar, "offset_bottom", 0.0, BAR_RETRACT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		bars.tween_property(bottom_bar, "offset_top", 0.0, BAR_RETRACT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tweens.append(bars)


## The descent begins: data-motes converge and the ticking clock (time motif) starts.
func _begin_materialization() -> void:
	if motes:
		motes.emitting = true
	_play_audio_sfx(AUDIO_TICK)


## Grid fully printed — the reveal. A restrained light-swell (NOT a flash) blooms outward,
## the real table is shown for the cross-fade, and the organ-like swell lands after the
## held breath of silence that followed the ticking.
func _ignite() -> void:
	_play_audio_sfx(AUDIO_SWELL)
	_reveal_table()

	# Restrained expanding light-swell — slow and soft, Interstellar discipline, not a Bay
	# shockwave. Low emission so it never blows out into a flash.
	if energy_ring:
		energy_ring.visible = true
		var size_m := _table_size_m()
		var max_scale: float = maxf(size_m.x, size_m.y) * 0.6
		var ring := create_tween()
		ring.tween_property(energy_ring, "scale", Vector3.ONE * max_scale, 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ring.parallel().tween_property(ring_material, "albedo_color:a", 0.0, 1.4)
		ring.parallel().tween_property(ring_material, "emission_energy_multiplier", 0.0, 1.4)
		_tweens.append(ring)


## Make the real table visible but fully transparent, then fade it in (per-instance
## transparency) so it cross-dissolves with the dissolving grid instead of popping in.
func _reveal_table() -> void:
	if not table:
		return
	table.visible = true
	var meshes := _table_meshes()
	if meshes.is_empty():
		return
	var fade := create_tween()
	fade.set_parallel(true)
	for m in meshes:
		m.transparency = 1.0
		fade.tween_property(m, "transparency", 0.0, TABLE_FADE_TIME).set_trans(Tween.TRANS_SINE)
	_tweens.append(fade)


## All MeshInstance3D nodes that make up the table (surface + border), recursively.
func _table_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if table:
		_collect_meshes(table, result)
	return result


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_collect_meshes(child, out)


## Force the table fully opaque (called on finish/skip so no transparency leaks into play).
func _reset_table_transparency() -> void:
	for m in _table_meshes():
		m.transparency = 0.0


# === Camera helpers ===

## Apply an eased interpolation between two world transforms (t already eased by the tween),
## plus a subtle "shot-on-film" gate weave that fades out as the camera settles.
func _apply_cam(t: float, from_x: Transform3D, to_x: Transform3D) -> void:
	if not intro_camera:
		return
	var base := from_x.interpolate_with(to_x, t)
	_weave_phase = float(Time.get_ticks_msec()) * 0.001
	var weave := Vector3(sin(_weave_phase * 1.3), cos(_weave_phase * 1.7) * 0.6,
		sin(_weave_phase * 0.9) * 0.4)
	base.origin += weave * WEAVE_AMPLITUDE * (1.0 - t)
	intro_camera.global_transform = base


## A transform positioned at `pos` looking at the table centre.
func _look_xform(pos: Vector3) -> Transform3D:
	var xform := Transform3D(Basis.IDENTITY, pos)
	return xform.looking_at(LOOK_TARGET, Vector3.UP)


## The exact pose the camera_controller will rest at after the intro, derived from its
## default pitch/zoom/target/yaw — NOT from the scene-default Camera3D node, which the
## controller overrides on its first frame (that mismatch was the end-of-intro snap).
func _final_camera_xform() -> Transform3D:
	if original_camera_pivot:
		var zoom = original_camera_pivot.get("_current_zoom")
		var pitch = original_camera_pivot.get("_pitch")
		var target = original_camera_pivot.get("_target_position")
		var yaw = original_camera_pivot.get("_yaw")
		if zoom != null and pitch != null and target != null:
			var pitch_rad := deg_to_rad(float(pitch))
			var offset := Vector3(0, -sin(pitch_rad), cos(pitch_rad)) * float(zoom)
			var yaw_rad := deg_to_rad(float(yaw)) if yaw != null else 0.0
			var pivot_xform := Transform3D(Basis(Vector3.UP, yaw_rad), target)
			var cam_pos: Vector3 = pivot_xform * offset
			return Transform3D(Basis.IDENTITY, cam_pos).looking_at(target, Vector3.UP)
	return _look_xform(FALLBACK_FINAL_POS)


func _final_camera_fov() -> float:
	if original_camera_pivot:
		var cam := original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			return cam.fov
	return FALLBACK_FOV


# === Scene show/hide ===

func _hide_main_scene() -> void:
	if table:
		table.visible = false
	if original_camera_pivot:
		var cam := original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = false


func _restore_environment() -> void:
	if not (world_environment and world_environment.environment):
		return
	var env := world_environment.environment
	env.background_mode = _orig_bg_mode
	env.background_color = _orig_bg_color
	env.glow_enabled = _orig_glow_enabled
	env.glow_intensity = _orig_glow_intensity
	env.glow_bloom = _orig_glow_bloom
	env.glow_blend_mode = _orig_glow_blend
	env.glow_hdr_threshold = _orig_glow_threshold
	env.volumetric_fog_enabled = _orig_fog_enabled
	if _sky_material:
		_sky_material.set_shader_parameter("star_brightness", _orig_star_brightness)


func _show_main_scene() -> void:
	if table:
		table.visible = true
	_reset_table_transparency()
	_restore_environment()
	if original_camera_pivot:
		var cam := original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true
	# The gameplay UI is revealed by main.gd's _on_intro_finished, not here.


# === Finish / skip ===

func _finish_intro() -> void:
	if not _is_playing:
		return
	_is_playing = false
	_stop_audio_music()
	_show_main_scene()
	if intro_camera:
		intro_camera.current = false

	# The vignette/DOF already eased off during the settle, so the cut is seamless here.
	var tween := create_tween()
	tween.tween_property(skip_label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_cleanup)
	intro_finished.emit()


func _skip_intro() -> void:
	if not _is_playing:
		return
	_is_playing = false
	_kill_tweens()
	_stop_audio_music()
	_show_main_scene()
	if intro_camera:
		intro_camera.current = false

	var tween := create_tween()
	if black_overlay:
		tween.tween_property(black_overlay, "modulate:a", 1.0, 0.08)
		tween.tween_property(black_overlay, "modulate:a", 0.0, 0.12)
	tween.tween_callback(_cleanup)
	intro_skipped.emit()


func _kill_tweens() -> void:
	for tween in _tweens:
		if tween and tween.is_valid():
			tween.kill()
	_tweens.clear()


func _cleanup() -> void:
	_kill_tweens()
	# canvas_layer frees its children (bars, vignette, skip label) with it.
	for node in [holo_plane, motes, energy_ring, intro_camera, canvas_layer]:
		if is_instance_valid(node):
			node.queue_free()


# === Quality / audio / table helpers ===

func _effects_enabled() -> bool:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs == null:
		return true
	# Heavy effects only above the low-end presets (PERFORMANCE = 0, LOW = 1).
	return int(gs.current_preset) > 1


func _table_size_m() -> Vector2:
	var size_feet := Vector2(4, 4)
	if table and table.get("table_size") != null:
		size_feet = table.table_size
	return size_feet * 0.3048


## (Re)size the letterbox bars to frame the current viewport at LETTERBOX_ASPECT. Bound to
## the viewport's size_changed so it stays correct across windowed→fullscreen changes.
func _apply_letterbox_bars() -> void:
	if _bars_retracting:
		return
	var bar_h := _letterbox_bar_height()
	if is_instance_valid(top_bar):
		top_bar.offset_bottom = bar_h
	if is_instance_valid(bottom_bar):
		bottom_bar.offset_top = -bar_h


## Height (px) of each letterbox bar for the current viewport.
func _letterbox_bar_height() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	var target_h := size.x / LETTERBOX_ASPECT
	return maxf(0.0, (size.y - target_h) * 0.5)


func _play_audio_music(path: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and ResourceLoader.exists(path):
		am.play_music_from_path(path)


func _stop_audio_music() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.stop_music()


func _play_audio_sfx(path: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and ResourceLoader.exists(path):
		am.play_sfx_at_path(path)
