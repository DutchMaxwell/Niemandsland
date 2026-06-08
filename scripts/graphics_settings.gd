extends Node
## Graphics Settings Manager
## Handles quality presets and graphics configuration

signal settings_applied(preset_name: String)

enum QualityPreset {
	PERFORMANCE,  # New: Maximum FPS mode
	LOW,
	MEDIUM,
	HIGH,
	ULTRA,
	CUSTOM
}

var current_preset: QualityPreset = QualityPreset.MEDIUM
var custom_settings: Dictionary = {}

# ===== Window / UI reachability =====
## Supported layout floor: the window can never shrink below this, so the left
## command panel, dice roller and unit card never collapse into each other. Below the
## floor, content scrolls rather than compresses. (See docs/AAA_UI_PLAYBOOK.md.)
const MIN_WINDOW_SIZE := Vector2i(1280, 720)
const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 2.0

## Whole-UI scale (content_scale_factor) for HiDPI / readability. Persisted; bound to a
## settings slider. DisplayServer.screen_get_scale() returns 1.0 on Windows/X11, so the
## manual slider stays the source of truth for 4K displays.
var ui_scale: float = 1.0

## Accessibility: when true, UI micro-interactions collapse to instant/opacity-only
## (WCAG 2.3.3). Read by UiMotion; persisted. Never gate information behind animation.
var reduce_motion: bool = false

## Borderless fullscreen (MODE_FULLSCREEN), NOT exclusive — no display mode switch, so it
## avoids the NVIDIA/X11 exclusive-fullscreen surface issues. Persisted + applied on start.
## Default on (the user wants auto-fullscreen); untick it to record with OBS (Game Capture
## stalls fullscreen Vulkan), which persists to windowed on the next launch.
var fullscreen: bool = true

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
		"sdfgi_cascades": 4,
		"volumetric_fog": false,
		"fsr_scale": 1.0,
		"glow": true,
		"glow_intensity": 0.6,
		"glow_bloom": 0.15,
	},
	QualityPreset.ULTRA: {
		"name": "Ultra",
		"description": "Maximum Quality",
		"msaa_3d": 3,  # 8x MSAA
		"use_taa": false,
		"shadow_size": 8192,
		"shadow_filter": 5,
		"ssao": true,
		"ssao_radius": 1.2,
		"ssao_intensity": 0.6,
		"ssil": true,
		"ssr": true,
		"sdfgi": false,  # Disabled by default - too expensive for most setups
		"sdfgi_cascades": 4,
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
	_apply_window_constraints()


## Enforce the minimum window size and apply the saved UI scale. Reachability floor.
func _apply_window_constraints() -> void:
	var window := get_window()
	if window:
		window.min_size = MIN_WINDOW_SIZE
	# Cap the frame rate so the non-blocking MAILBOX present mode doesn't render uncapped.
	Engine.max_fps = 120
	apply_ui_scale(ui_scale)
	# Apply the persisted fullscreen choice (default on). Driven here rather than at the
	# engine level so unticking it actually persists to a windowed start (needed for OBS).
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
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	save_settings()


## Scale the whole UI; clamps to a sane range and persists. Exposed to a settings slider.
func apply_ui_scale(factor: float) -> void:
	ui_scale = clampf(factor, UI_SCALE_MIN, UI_SCALE_MAX)
	var tree := get_tree()
	if tree and tree.root:
		tree.root.content_scale_factor = ui_scale
	save_settings()


## Apply a quality preset
func apply_preset(preset: QualityPreset) -> void:
	if preset == QualityPreset.CUSTOM:
		apply_custom_settings()
		return

	var settings = PRESETS[preset]
	current_preset = preset

	# Apply rendering settings
	apply_rendering_settings(settings)

	# Apply environment settings
	apply_environment_settings(settings)

	# Save settings
	save_settings()

	settings_applied.emit(settings["name"])


## Apply rendering settings to project
func apply_rendering_settings(settings: Dictionary) -> void:
	# MSAA
	var vp = get_viewport()
	vp.msaa_3d = settings["msaa_3d"]
	vp.use_taa = settings["use_taa"]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not settings["use_taa"] else Viewport.SCREEN_SPACE_AA_DISABLED

	# FSR Scaling
	vp.scaling_3d_scale = settings["fsr_scale"]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if settings["fsr_scale"] < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR

	# Shadow quality (runtime changes limited, mostly project settings)
	RenderingServer.directional_shadow_atlas_set_size(settings["shadow_size"], true)


## Apply environment settings
func apply_environment_settings(settings: Dictionary) -> void:
	var world_env = get_tree().root.get_node_or_null("Main/WorldEnvironment")
	if not world_env:
		push_warning("WorldEnvironment not found")
		return

	var env = world_env.environment
	if not env:
		return

	# SSAO
	env.ssao_enabled = settings["ssao"]
	if settings.has("ssao_radius"):
		env.ssao_radius = settings["ssao_radius"]
	if settings.has("ssao_intensity"):
		env.ssao_intensity = settings["ssao_intensity"]

	# SSIL
	env.ssil_enabled = settings.get("ssil", false)

	# SSR
	env.ssr_enabled = settings["ssr"]

	# --- Tier-gated atmosphere / GI (centralised so all 5 presets stay consistent) ---
	var tier: int = current_preset

	# SDFGI: realtime bounce GI — ULTRA only (expensive; can shimmer on small minis).
	if tier == QualityPreset.ULTRA:
		env.sdfgi_enabled = true
		env.sdfgi_cascades = 4
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = 0.5
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	else:
		env.sdfgi_enabled = false

	# Atmospheric fog is off: the scene is set in space (no aerial perspective), and the
	# low ground mist is now drawn by the dedicated white shader-plane system
	# (atmospheric_clouds.gd) rather than environment volumetric fog, which a 1–2 cm
	# ground layer cannot be resolved by and which tinted everything warm/brown.
	env.fog_enabled = false
	env.volumetric_fog_enabled = false

	# Auto-exposure: disabled for now — it blew the physical-sky scene out to white.
	# Re-introduce once the fixed-exposure baseline is dialled in.
	if world_env.camera_attributes:
		world_env.camera_attributes.auto_exposure_enabled = false

	# Glow
	env.glow_enabled = settings["glow"]
	if settings.has("glow_intensity"):
		env.glow_intensity = settings["glow_intensity"]
	if settings.has("glow_bloom"):
		env.glow_bloom = settings["glow_bloom"]


## Apply custom settings
func apply_custom_settings() -> void:
	if custom_settings.is_empty():
		# Fallback to medium
		apply_preset(QualityPreset.MEDIUM)
		return

	apply_rendering_settings(custom_settings)
	apply_environment_settings(custom_settings)
	settings_applied.emit("Custom")


## Get current preset name
func get_current_preset_name() -> String:
	if current_preset == QualityPreset.CUSTOM:
		return "Custom"
	return PRESETS[current_preset]["name"]


## Save settings to config file
func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("graphics", "preset", current_preset)
	config.set_value("graphics", "custom_settings", custom_settings)
	config.set_value("graphics", "ui_scale", ui_scale)
	config.set_value("graphics", "reduce_motion", reduce_motion)
	config.set_value("graphics", "fullscreen", fullscreen)
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
	custom_settings = config.get_value("graphics", "custom_settings", {})
	ui_scale = config.get_value("graphics", "ui_scale", 1.0)
	reduce_motion = config.get_value("graphics", "reduce_motion", false)
	fullscreen = config.get_value("graphics", "fullscreen", true)


## Set resolution
func set_resolution(width: int, height: int, use_fullscreen: bool = false) -> void:
	var window = get_window()
	window.size = Vector2i(width, height)

	if use_fullscreen:
		window.mode = Window.MODE_FULLSCREEN  # borderless, not EXCLUSIVE (X11/NVIDIA-safe)
	else:
		window.mode = Window.MODE_WINDOWED

	# Center window if windowed
	if not use_fullscreen:
		var screen_size = DisplayServer.screen_get_size()
		var window_pos = (screen_size - window.size) / 2
		window.position = window_pos


## Get available resolutions
func get_available_resolutions() -> Array[Vector2i]:
	return [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]


## Toggle VSync
func set_vsync(mode: int) -> void:
	# 0 = Disabled, 1 = Enabled, 2 = Adaptive
	DisplayServer.window_set_vsync_mode(mode)
