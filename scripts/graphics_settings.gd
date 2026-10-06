extends Node
## Graphics Settings Manager
## Handles quality presets and graphics configuration

signal settings_applied(preset_name: String)
signal idle_motion_changed()

enum QualityPreset {
	PERFORMANCE,  # New: Maximum FPS mode
	LOW,
	MEDIUM,
	HIGH,
	ULTRA
}

var current_preset: QualityPreset = QualityPreset.MEDIUM
var table_frame_style: int = 0  # Today's look / Walnut / Oak / Ivory.
var _frame_materials: Dictionary = {}  # Two shared grain orientations, independent of table size.

## Midtone RGB curve, saturation, AgX contrast, highlight glow. Black/white stay neutral.
const BIOME_GRADES := {
	"temperate_grassland": [Color(0.49, 0.53, 0.46), 1.06, 1.15, 0.12],
	"arid_desert": [Color(0.55, 0.51, 0.45), 0.96, 1.10, 0.10],
	"frozen_tundra": [Color(0.47, 0.50, 0.55), 0.88, 1.08, 0.08],
	"volcanic_ash": [Color(0.52, 0.46, 0.43), 0.92, 1.20, 0.18],
	"alien_jungle": [Color(0.47, 0.55, 0.46), 1.12, 1.16, 0.14],
	"urban_ruins": [Color(0.47, 0.49, 0.51), 0.85, 1.18, 0.10],
}
## Maintainer render picks (1oEL55): Subtle = 0.65, Clear = 1.8.
## Alien jungle has no saved pick; retain its previous Clear default.
const BIOME_GRADE_WEIGHTS := {
	"temperate_grassland": 0.65, "arid_desert": 1.8, "frozen_tundra": 0.65,
	"urban_ruins": 1.8, "volcanic_ash": 0.65, "alien_jungle": 1.8,
}
var _biome_grade_curves := {}


func biome_grade_values(biome: String, mood := "Sunset") -> Dictionary:
	if current_preset < QualityPreset.MEDIUM or not BIOME_GRADES.has(biome):
		return {}
	var grade: Array = BIOME_GRADES[biome]
	var weight: float = BIOME_GRADE_WEIGHTS[biome]
	var key := biome + mood
	if not _biome_grade_curves.has(key):
		var curve := GradientTexture1D.new()
		curve.width = 256
		curve.gradient = Gradient.new()
		curve.gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		curve.gradient.colors = PackedColorArray([Color.BLACK, Color(0.5, 0.5, 0.5).lerp(grade[0], weight), Color.WHITE])
		if mood == "Sunset":
			var tint: Color = (grade[0] - BIOME_GRADES["temperate_grassland"][0]) * weight
			curve.gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
			curve.gradient.colors = PackedColorArray([Color.BLACK, Color(0.20,0.20,0.205),
				Color(0.52,0.50,0.48) + tint, Color(0.82,0.80,0.76), Color.WHITE])
		_biome_grade_curves[key] = curve
	if mood == "Sunset":
		return {"adjustment_enabled":true, "adjustment_color_correction":_biome_grade_curves[key],
			"adjustment_contrast":1.12, "adjustment_saturation":1.03 + (grade[1] - 1.06) * weight,
			"tonemap_agx_contrast":1.15, "glow_intensity":0.30, "glow_bloom":0.0}
	return {"adjustment_enabled": true, "adjustment_color_correction": _biome_grade_curves[key],
		"adjustment_contrast": 1.0 + 0.05 * weight, "adjustment_saturation": lerpf(1.0, grade[1], weight),
		"tonemap_agx_contrast": lerpf(1.0, grade[2], weight), "glow_intensity": grade[3], "glow_bloom": 0.0}


func _on_grading_biome_changed(_biome: String) -> void:
	apply_environment_settings(PRESETS[current_preset])

# ===== Window / UI reachability =====
## Supported layout floor: the window can never shrink below this, so the left
## command panel, dice roller and unit card never collapse into each other. Below the
## floor, content scrolls rather than compresses.
const MIN_WINDOW_SIZE := Vector2i(1280, 720)
const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 2.0

## Whole-UI scale (content_scale_factor) for HiDPI / readability. Persisted; bound to a
## settings slider. DisplayServer.screen_get_scale() returns 1.0 on Windows/X11, so the
## manual slider stays the source of truth for 4K displays.
var ui_scale: float = 1.0

## Accessibility: when true, UI micro-interactions collapse to instant/opacity-only
## (WCAG 2.3.3). Read by UiMotion; persisted. Never gate information behind animation.
var reduce_motion: bool = false:
	set(value):
		reduce_motion = value
		idle_motion_changed.emit()

## Real idle is opt-in per asset; old models stay static. Persist the user's preference.
var idle_motion: bool = true:
	set(value):
		idle_motion = value
		idle_motion_changed.emit()

## Borderless fullscreen (MODE_FULLSCREEN), NOT exclusive — no display mode switch, so it
## avoids the NVIDIA/X11 exclusive-fullscreen surface issues. Persisted + applied on start.
## Default on (the user wants auto-fullscreen); untick it to record with OBS (Game Capture
## stalls fullscreen Vulkan), which persists to windowed on the next launch.
var fullscreen: bool = true

## NML-1078 / GH #363 — Discord playtest feedback: on a two-monitor PC the window opened on
## the second monitor (initial_position_type=3 centres it on whatever screen the mouse is on)
## and fullscreen never moved it, since borderless fullscreen just covers the CURRENT screen.
## -1 = primary screen (the default the maintainer promised); 0..N-1 = a specific monitor.
## Persisted; set via the graphics panel's Monitor dropdown.
var screen_index: int = -1

## Path-painting move trails: show the chalk trails at all (the visible layer only — the
## move ledger always records for MP proof). Persisted; bound to the T hotkey and the
## Settings "Show Move Trails" toggle. Default on; auto-suppressed during deployment.
var show_move_trails: bool = true
## Transparency stage 2: rising rule texts at the table ("Blast ×3", "Artillery +1").
var show_rule_floats: bool = true
## Combat effects (result marks, shots, falls, spells, hero auras). ON by default (maintainer look GO, 05.10.);
## one switch turns them all off.
var show_combat_effects: bool = true
## Cinematic depth of field ("tilt-shift") on the table camera: sharp while zoomed
## out, softly blurred in the foreground/background as the camera zooms towards the
## models. On by default (the intended look); persisted; bound to the Settings
## "Tilt-Shift" toggle and applied by CameraController.
var tilt_shift: bool = true
## Pacing grill 31.07.: the central combat stage (solo) — phases hold, click skips.
var show_combat_stage: bool = true
var combat_stage_hold_s: float = 2.5
## How bloody the combat effects are: 0 Off (dust instead of blood), 1 Normal, 2 Extra. Players and streamers turn it down.
var gore_level: int = 1

## Strict "dry brush" movement enforcement: hard-stop a movement path-paint / drag at the
## model's MAX legal band (Rush/Charge). ON = Strict (the maintainer's default — you learn the
## ranges as you play); OFF = Casual (free drag, as before). Persisted; bound to the Settings
## "Enforce Movement Limit" toggle. Movement only — never gates shooting or other actions.
var enforce_movement_limit: bool = true

## NML-955 — AI EXPLANATION toasts (which unit NACHTMAHR picked, what it shot, what the roll did)
## stay on screen until the next event replaces them or you click them away, instead of fading after
## six seconds. The maintainer could not study them otherwise. Plain operational notices (export
## path, autosave, a refused button) keep their fade either way — this switch does not touch them.
var ai_explain_persistent: bool = true

# Preset configurations - optimized for tabletop gaming performance
const PRESETS = {
	QualityPreset.PERFORMANCE: {
		"name": "Performance",
		"description": "Maximum FPS, Minimal Effects",
		"msaa_3d": 0,  # No MSAA - use FXAA only
		"use_taa": false,
		"shadow_size": 1024,
		"shadow_filter": 1,  # Basic shadows
		"ssao": false,  # Disabled for max performance
		"ssao_radius": 0.5,
		"ssao_intensity": 0.5,
		"ssil": false,
		"ssr": false,
		"sdfgi": false,
		"volumetric_fog": false,
		"fsr_scale": 0.77,  # FSR Quality mode for extra FPS
		"glow": false,
		"glow_intensity": 0.0,
		"glow_bloom": 0.0,
	},
	QualityPreset.LOW: {
		"name": "Low",
		"description": "Good Performance",
		"msaa_3d": 1,  # 2x MSAA (was 4x)
		"use_taa": false,
		"shadow_size": 2048,
		"shadow_filter": 2,
		"ssao": false,  # Disabled for better FPS
		"ssao_radius": 0.8,
		"ssao_intensity": 0.8,
		"ssil": false,
		"ssr": false,
		"sdfgi": false,
		"volumetric_fog": false,
		"fsr_scale": 1.0,
		"glow": false,
		"glow_intensity": 0.4,
		"glow_bloom": 0.05,
	},
	QualityPreset.MEDIUM: {
		"name": "Medium",
		"description": "Balanced Quality/Performance",
		"msaa_3d": 2,  # 4x MSAA (was 8x)
		"use_taa": false,
		"shadow_size": 4096,
		"shadow_filter": 3,
		"ssao": true,
		"ssao_radius": 0.8,
		"ssao_intensity": 0.4,
		"ssil": false,
		"ssr": false,  # Disabled - expensive and not critical for tabletop
		"sdfgi": false,
		"volumetric_fog": false,
		"fsr_scale": 1.0,
		"glow": true,
		"glow_intensity": 0.5,
		"glow_bloom": 0.1,
	},
	QualityPreset.HIGH: {
		"name": "High",
		"description": "High Quality",
		"msaa_3d": 2,  # 4x MSAA (was 8x)
		"use_taa": false,
		"shadow_size": 4096,  # Reduced from 8192
		"shadow_filter": 4,
		"ssao": true,
		"ssao_radius": 1.0,
		"ssao_intensity": 0.5,
		"ssil": false,  # Disabled - very expensive
		"ssr": true,
		"sdfgi": false,  # Disabled - extremely expensive
		"volumetric_fog": false,
		"fsr_scale": 1.0,
		"glow": true,
		"glow_intensity": 0.6,
		"glow_bloom": 0.15,
	},
	QualityPreset.ULTRA: {
		"name": "Ultra",
		"description": "Maximum Quality",
		"msaa_3d": 2,  # 4x MSAA (8x doubled the render target — huge on a 2560x1600
		# fullscreen 8GB GPU — for no visible gain; 4x matches High)
		"use_taa": false,
		"shadow_size": 8192,
		"shadow_filter": 5,
		"ssao": true,
		"ssao_radius": 1.2,
		"ssao_intensity": 0.6,
		"ssil": true,
		"ssr": true,
		"sdfgi": false,  # Disabled by default - too expensive for most setups
		"volumetric_fog": false,
		"fsr_scale": 1.0,
		"glow": true,
		"glow_intensity": 0.7,
		"glow_bloom": 0.2,
	},
}


func _ready() -> void:
	# Load saved settings or use default
	load_settings()
	apply_preset(current_preset)
	apply_window_constraints()


## Enforce the minimum window size and apply the saved UI scale. Reachability floor. Also called by the game scene
## at its start (main.gd), when the real game window is up.
func apply_window_constraints() -> void:
	var window := get_window()
	if window:
		window.min_size = MIN_WINDOW_SIZE
	# Cap the frame rate so the non-blocking MAILBOX present mode doesn't render uncapped.
	Engine.max_fps = 120
	apply_ui_scale(ui_scale)
	# Apply the persisted fullscreen choice (default on). Driven here rather than at the
	# engine level so unticking it actually persists to a windowed start (needed for OBS).
	# An explicit windowed launch (side-by-side test instances, capture setups) wins over the
	# persisted preference for THIS run. Godot CONSUMES its own `--windowed` before scripts can
	# see it (it is not in get_cmdline_args — verified on 4.6), so the supported forms are the
	# user arg `-- --windowed` and the env var NML_WINDOWED=1; the plain engine arg is checked
	# too in case a future Godot passes it through.
	var launch_args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var wants_windowed: bool = launch_args.has("--windowed") or OS.get_environment("NML_WINDOWED") == "1"
	apply_screen(screen_index)
	if wants_windowed:
		print("[Graphics] windowed launch requested — skipping fullscreen restore")
		apply_fullscreen(false)
	else:
		apply_fullscreen(fullscreen)


## Toggle borderless fullscreen (safe MODE_FULLSCREEN, never EXCLUSIVE). Persisted.
## In fullscreen we use a NON-blocking present mode (MAILBOX): with blocking FIFO vsync, an
## OBS screen capture perturbing NVIDIA's page-flip makes vkAcquireNextImageKHR block, which
## stalls the whole main loop and freezes the (Tween-driven) cinematic intro while recording
## (Godot #105583 / #80550). MAILBOX never blocks, so the loop keeps running during capture.
func apply_fullscreen(on: bool) -> void:
	fullscreen = on
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
		# Fullscreen only ever covers the CURRENT screen — re-assert the chosen monitor so
		# toggling fullscreen never silently jumps the window back to whatever screen it
		# was already on (NML-1078 / GH #363).
		if DisplayServer.get_screen_count() > 1:
			var target := screen_index
			if target < 0 or target >= DisplayServer.get_screen_count():
				target = DisplayServer.get_primary_screen()
			DisplayServer.window_set_current_screen(target)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	save_settings()


## Move the window onto the requested monitor (idx), falling back to the primary screen when
## idx is invalid (unknown/removed monitor, or the default -1). NML-1078 / GH #363: a
## borderless-fullscreen window cannot reliably be moved to another screen while fullscreen,
## so this drops to windowed, moves it, then restores fullscreen. On a single-screen or
## headless run window_set_current_screen would be a pointless no-op, so it is skipped — but
## the log line always fires so playtesters and tests can see what was resolved.
func apply_screen(idx: int) -> void:
	var count := DisplayServer.get_screen_count()
	var target := idx
	if target < 0 or target >= count:
		target = DisplayServer.get_primary_screen()
	if count > 1:
		var was_fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if was_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(target)
		if was_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	print("[Graphics] window on screen %d of %d (requested %d)" % [target, count, idx])


## Scale the whole UI; clamps to a sane range and persists. Exposed to a settings slider.
func apply_ui_scale(factor: float) -> void:
	ui_scale = clampf(factor, UI_SCALE_MIN, UI_SCALE_MAX)
	var tree := get_tree()
	if tree and tree.root:
		tree.root.content_scale_factor = ui_scale
	save_settings()


## Apply a quality preset
func apply_preset(preset: QualityPreset) -> void:
	var settings = PRESETS[preset]
	if current_preset != preset:
		idle_motion = preset >= QualityPreset.MEDIUM
	current_preset = preset

	# Apply rendering settings
	apply_rendering_settings(settings)

	# Apply environment settings
	apply_environment_settings(settings)

	# Save settings
	save_settings()

	settings_applied.emit(settings["name"])


## Finish the existing frame boxes; cheap tiers keep their original material.
func table_frame_material(original: Material, along_z: bool) -> Material:
	if current_preset < QualityPreset.MEDIUM or table_frame_style == 0:
		return original
	if not _frame_materials.has(along_z):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/table_frame.gdshader")
		mat.set_shader_parameter("along_z", along_z)
		_frame_materials[along_z] = mat
	_frame_materials[along_z].set_shader_parameter("frame_strength", table_frame_style - 1)
	return _frame_materials[along_z]


func set_table_frame_style(style: int) -> void:
	table_frame_style = clampi(style, 0, 3)
	var table := get_node_or_null("/root/Main/Table")
	if table != null:
		table._apply_frame_finish()
	save_settings()


## Apply rendering settings to project
func apply_rendering_settings(settings: Dictionary) -> void:
	# MSAA
	var vp = get_viewport()
	vp.msaa_3d = settings["msaa_3d"]
	vp.use_taa = settings["use_taa"]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not settings["use_taa"] else Viewport.SCREEN_SPACE_AA_DISABLED

	# Shadow quality (runtime changes limited, mostly project settings)
	RenderingServer.directional_shadow_atlas_set_size(settings["shadow_size"], true)

	# 3D resolution scaling. Performance (0.77) is the ONLY sub-native tier, so this is
	# the only preset switch that RESIZES the 3D render target. Bundling that resize in
	# the same frame as the MSAA + shadow-atlas reallocation above is the app's heaviest
	# single-frame GPU buffer churn, and crossing the Performance boundary in fullscreen
	# froze the picture (a Vulkan-swapchain stall under load — NVIDIA 580.x pre-.142 /
	# Godot #80550 history). Keep the MODE constant (always bilinear; toggling it also
	# recreates the swap chain) and DEFER the scale change to its own later frames so the
	# others' deferred buffer frees complete first. No-op when the scale is unchanged, so
	# Low<->Ultra switches (all 1.0) stay instant — only Performance<->X actually defers.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_apply_scaling_3d_staggered(settings["fsr_scale"])


## Applies the 3D resolution scale on a later frame to de-burst the Performance-boundary
## GPU reallocation (see apply_rendering_settings). Fire-and-forget coroutine; only the
## render-target resize is deferred, and only when the scale actually changes.
func _apply_scaling_3d_staggered(scale: float) -> void:
	var vp := get_viewport()
	if vp == null or is_equal_approx(vp.scaling_3d_scale, scale):
		return  # no render-target resize needed
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	vp = get_viewport()
	if vp:
		# The preset current NOW, not the one that started this wait: a second preset inside the two frames
		# (Performance -> Low) returned early above and would otherwise get the stale 0.77.
		vp.scaling_3d_scale = PRESETS[current_preset]["fsr_scale"]


## Apply environment settings
func apply_environment_settings(settings: Dictionary) -> void:
	var world_env = get_tree().root.get_node_or_null("Main/WorldEnvironment")
	if not world_env:
		# The Main scene isn't loaded at the startup menu, so environment settings simply don't apply
		# there — that is expected, not an error. Only warn if Main IS loaded but has no
		# WorldEnvironment (a genuinely broken scene). Fixes the spurious boot warning (G5).
		if get_tree().root.get_node_or_null("Main") != null:
			push_warning("WorldEnvironment not found under Main")
		return

	var env = world_env.environment
	if not env:
		return

	# The game table's RenderState owns these values: the preset is its lowest layer (the mood light, the biome
	# reference and the intro sit above it), so the end state no longer depends on which script ran last.
	var values := environment_values(settings, current_preset)
	var render_state = world_env.get_parent().get("render_state")
	if render_state != null:
		render_state.set_layer("preset", values)
		var table: Node = world_env.get_parent().get_node_or_null("Table")
		if table != null:
			var atmosphere: Node = world_env.get_parent().get("atmosphere_controller")
			var mood: String = atmosphere.get_current_atmosphere() if atmosphere != null else "Sunset"
			render_state.set_layer("grading", biome_grade_values(str(table.biome), mood))
			if atmosphere != null and not atmosphere.atmosphere_changed.is_connected(_on_grading_biome_changed):
				atmosphere.atmosphere_changed.connect(_on_grading_biome_changed)
			if not table.biome_changed.is_connected(_on_grading_biome_changed):
				table.biome_changed.connect(_on_grading_biome_changed)
	else:
		for key: String in values:
			env.set(key, values[key])

	# Auto-exposure: disabled for now — it blew the physical-sky scene out to white.
	# Re-introduce once the fixed-exposure baseline is dialled in.
	if world_env.camera_attributes:
		world_env.camera_attributes.auto_exposure_enabled = false


## The preset's Environment values: SSAO, SSIL, SSR, glow; SDFGI on ULTRA only; fog off.
static func environment_values(settings: Dictionary, tier: int) -> Dictionary:
	var values := {"ssao_enabled": settings["ssao"], "ssil_enabled": settings.get("ssil", false),
		"ssr_enabled": settings["ssr"], "glow_enabled": settings["glow"],
		# SDFGI: realtime bounce GI — ULTRA only (expensive; can shimmer on small minis).
		"sdfgi_enabled": tier == QualityPreset.ULTRA,
		# Atmospheric fog is off: the scene is set in space (no aerial perspective), and the
		# low ground mist is now drawn by the dedicated white shader-plane system
		# (atmospheric_clouds.gd) rather than environment volumetric fog, which a 1–2 cm
		# ground layer cannot be resolved by and which tinted everything warm/brown.
		"fog_enabled": false, "volumetric_fog_enabled": false}
	for key: String in ["ssao_radius", "ssao_intensity", "glow_intensity", "glow_bloom"]:
		if settings.has(key):
			values[key] = settings[key]
	if tier == QualityPreset.ULTRA:
		# Do NOT inject the procedural sky into SDFGI: the space-skybox radiance bake is
		# an unreliable light source (intermittent GPU-garbage cubemap floods the scene
		# magenta/green/white). Scene lighting is decoupled from the sky (ambient=Color,
		# reflections disabled in main.tscn); SDFGI keeps geometry bounce only.
		values.merge({"sdfgi_cascades": 4, "sdfgi_use_occlusion": true, "sdfgi_read_sky_light": false,
			"sdfgi_bounce_feedback": 0.5, "sdfgi_min_cell_size": 0.2,
			"sdfgi_y_scale": Environment.SDFGI_Y_SCALE_75_PERCENT})
	return values


## Medium and above keep the tabletop in focus at normal play distance.
static func table_focus_amount(tier: int) -> float:
	return 0.11 if tier >= QualityPreset.MEDIUM else 0.0


## Get current preset name
func get_current_preset_name() -> String:
	return PRESETS[current_preset]["name"]


## Save settings to config file
func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("graphics", "table_frame_style", table_frame_style)
	config.set_value("graphics", "preset", current_preset)
	config.set_value("graphics", "ui_scale", ui_scale)
	config.set_value("graphics", "reduce_motion", reduce_motion)
	config.set_value("graphics", "idle_motion", idle_motion)
	config.set_value("graphics", "fullscreen", fullscreen)
	config.set_value("graphics", "screen_index", screen_index)
	config.set_value("graphics", "show_move_trails", show_move_trails)
	config.set_value("graphics", "show_rule_floats", show_rule_floats)
	config.set_value("graphics", "show_combat_effects", show_combat_effects)
	config.set_value("graphics", "tilt_shift", tilt_shift)
	config.set_value("graphics", "show_combat_stage", show_combat_stage)
	config.set_value("graphics", "combat_stage_hold_s", combat_stage_hold_s)
	config.set_value("graphics", "gore_level", gore_level)
	config.set_value("graphics", "enforce_movement_limit", enforce_movement_limit)
	config.set_value("graphics", "ai_explain_persistent", ai_explain_persistent)
	config.save("user://graphics_settings.cfg")


## Load settings from config file
func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://graphics_settings.cfg")

	if err != OK:
		# Default to medium
		current_preset = QualityPreset.MEDIUM
		return

	current_preset = config.get_value("graphics", "preset", QualityPreset.MEDIUM)
	table_frame_style = clampi(int(config.get_value("graphics", "table_frame_style", 0)), 0, 3)
	ui_scale = config.get_value("graphics", "ui_scale", 1.0)
	reduce_motion = config.get_value("graphics", "reduce_motion", false)
	idle_motion = config.get_value("graphics", "idle_motion", current_preset >= QualityPreset.MEDIUM)
	fullscreen = config.get_value("graphics", "fullscreen", true)
	screen_index = config.get_value("graphics", "screen_index", -1)
	show_move_trails = config.get_value("graphics", "show_move_trails", true)
	show_rule_floats = config.get_value("graphics", "show_rule_floats", true)
	show_combat_effects = config.get_value("graphics", "show_combat_effects", true)
	tilt_shift = config.get_value("graphics", "tilt_shift", true)
	show_combat_stage = config.get_value("graphics", "show_combat_stage", true)
	combat_stage_hold_s = float(config.get_value("graphics", "combat_stage_hold_s", 2.5))
	gore_level = clampi(int(config.get_value("graphics", "gore_level", 1)), 0, 2)
	enforce_movement_limit = config.get_value("graphics", "enforce_movement_limit", true)
	ai_explain_persistent = config.get_value("graphics", "ai_explain_persistent", true)
