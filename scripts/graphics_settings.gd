extends Node
## Graphics Settings Manager
## Handles quality presets and graphics configuration

signal settings_applied(preset_name: String)

enum QualityPreset {
	LOW,
	MEDIUM,
	HIGH,
	ULTRA,
	CUSTOM
}

var current_preset: QualityPreset = QualityPreset.MEDIUM
var custom_settings: Dictionary = {}

# Preset configurations
const PRESETS = {
	QualityPreset.ULTRA: {
		"name": "Ultra",
		"description": "4K, All Effects",
		"msaa_3d": 3,  # 8x
		"use_taa": false,  # Disabled to prevent ghosting
		"shadow_size": 4096,
		"shadow_filter": 3,
		"ssao": true,
		"ssil": true,
		"ssr": true,
		"sdfgi": true,
		"sdfgi_cascades": 6,
		"volumetric_fog": true,
		"fsr_scale": 1.0,  # Native
		"glow": true,
	},
	QualityPreset.HIGH: {
		"name": "High",
		"description": "1440p, Most Effects",
		"msaa_3d": 3,  # 8x
		"use_taa": false,  # Disabled to prevent ghosting
		"shadow_size": 2048,
		"shadow_filter": 2,
		"ssao": true,
		"ssil": false,
		"ssr": true,
		"sdfgi": false,
		"volumetric_fog": false,
		"fsr_scale": 0.77,  # FSR Quality
		"glow": true,
	},
	QualityPreset.MEDIUM: {
		"name": "Medium",
		"description": "1080p, Balanced",
		"msaa_3d": 2,  # 4x (increased from 2x)
		"use_taa": false,  # Disabled to prevent ghosting
		"shadow_size": 2048,
		"shadow_filter": 1,
		"ssao": true,
		"ssil": false,
		"ssr": false,
		"sdfgi": false,
		"volumetric_fog": false,
		"fsr_scale": 0.67,  # FSR Balanced
		"glow": true,
	},
	QualityPreset.LOW: {
		"name": "Low",
		"description": "1080p, Performance",
		"msaa_3d": 0,  # Disabled
		"use_taa": false,
		"shadow_size": 1024,
		"shadow_filter": 0,
		"ssao": false,
		"ssil": false,
		"ssr": false,
		"sdfgi": false,
		"volumetric_fog": false,
		"fsr_scale": 0.59,  # FSR Performance
		"glow": false,
	}
}


func _ready() -> void:
	# Load saved settings or use default
	load_settings()
	apply_preset(current_preset)


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

	print("Graphics preset applied: %s" % settings["name"])
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

	# SSIL
	env.ssil_enabled = settings.get("ssil", false)

	# SSR
	env.ssr_enabled = settings["ssr"]

	# SDFGI
	if settings.get("sdfgi", false):
		env.sdfgi_enabled = true
		env.sdfgi_cascades = settings.get("sdfgi_cascades", 4)
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = 0.5
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	else:
		env.sdfgi_enabled = false

	# Volumetric Fog
	env.volumetric_fog_enabled = settings.get("volumetric_fog", false)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.01
		env.volumetric_fog_albedo = Color(0.9, 0.9, 1.0)
		env.volumetric_fog_gi_inject = 0.5

	# Glow
	env.glow_enabled = settings["glow"]


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


## Set resolution
func set_resolution(width: int, height: int, fullscreen: bool = false) -> void:
	var window = get_window()
	window.size = Vector2i(width, height)

	if fullscreen:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED

	# Center window if windowed
	if not fullscreen:
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
