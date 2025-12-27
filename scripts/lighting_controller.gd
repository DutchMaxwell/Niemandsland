extends Node
## Lighting controller with real-time adjustments and preset system
## Allows fine-tuning of all lighting parameters for perfect visuals

# References to scene nodes
var _directional_light: DirectionalLight3D
var _world_environment: WorldEnvironment
var _environment: Environment

# Current lighting settings
var current_preset: Dictionary = {}

# Preset definitions
const PRESETS = {
	"Default": {
		"name": "Default (Warm & Cozy)",
		"sun_energy": 1.8,
		"sun_color": Color(1.0, 0.8, 0.6),
		"sun_angle_h": 84.0,  # Horizontal angle (degrees)
		"sun_angle_v": 43.0,   # Vertical angle (degrees)
		"ambient_energy": 0.6,
		"ambient_color": Color(0.9, 0.7, 0.5),
		"exposure": 1.3,
		"shadow_opacity": 0.7,
		"shadow_blur": 1.0,
		"shadow_bias": 0.01,  # Reduces shadow acne
		"shadow_normal_bias": 0.5,  # Prevents shadows from detaching
		"ssao_intensity": 0.9,
		"ssr_intensity": 0.2,
		"glow_intensity": 1.2,
		"contrast": 1.15,
		"saturation": 1.15,
	},
	"Warm Sunset": {
		"name": "Warm Sunset (Cozy)",
		"sun_energy": 1.5,
		"sun_color": Color(1.0, 0.8, 0.6),
		"sun_angle_h": -45.0,
		"sun_angle_v": 25.0,
		"ambient_energy": 0.6,
		"ambient_color": Color(0.9, 0.7, 0.5),
		"exposure": 1.3,
		"shadow_opacity": 0.7,
		"shadow_blur": 3.0,
		"ssao_intensity": 2.0,
		"ssr_intensity": 0.8,
		"glow_intensity": 1.2,
		"contrast": 1.15,
		"saturation": 1.15,
	},
	"Bright Studio": {
		"name": "Bright Studio (Clear)",
		"sun_energy": 1.8,
		"sun_color": Color(1.0, 1.0, 1.0),
		"sun_angle_h": 0.0,
		"sun_angle_v": 60.0,
		"ambient_energy": 0.8,
		"ambient_color": Color(0.95, 0.95, 0.95),
		"exposure": 1.4,
		"shadow_opacity": 0.6,
		"shadow_blur": 1.0,
		"ssao_intensity": 1.0,
		"ssr_intensity": 0.6,
		"glow_intensity": 0.5,
		"contrast": 1.0,
		"saturation": 1.0,
	},
	"Dramatic": {
		"name": "Dramatic (High Contrast)",
		"sun_energy": 2.0,
		"sun_color": Color(1.0, 0.95, 0.85),
		"sun_angle_h": -60.0,
		"sun_angle_v": 35.0,
		"ambient_energy": 0.3,
		"ambient_color": Color(0.6, 0.65, 0.7),
		"exposure": 1.1,
		"shadow_opacity": 0.95,
		"shadow_blur": 1.5,
		"ssao_intensity": 2.5,
		"ssr_intensity": 1.2,
		"glow_intensity": 0.6,
		"contrast": 1.25,
		"saturation": 1.1,
	},
	"Cool Overcast": {
		"name": "Cool Overcast (Moody)",
		"sun_energy": 0.8,
		"sun_color": Color(0.9, 0.95, 1.0),
		"sun_angle_h": 0.0,
		"sun_angle_v": 70.0,
		"ambient_energy": 0.7,
		"ambient_color": Color(0.7, 0.75, 0.85),
		"exposure": 1.0,
		"shadow_opacity": 0.5,
		"shadow_blur": 4.0,
		"ssao_intensity": 1.8,
		"ssr_intensity": 0.9,
		"glow_intensity": 0.4,
		"contrast": 1.05,
		"saturation": 0.95,
	},
}


func _ready() -> void:
	# Will be initialized when connected to scene nodes
	pass


## Initialize with scene references
func initialize(directional_light: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	_directional_light = directional_light
	_world_environment = world_env
	_environment = world_env.environment

	# Load default preset
	apply_preset("Default")
	print("Lighting Controller initialized")


## Apply a preset by name
func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		print("Preset not found: ", preset_name)
		return

	var preset = PRESETS[preset_name]
	current_preset = preset.duplicate()

	# Apply all settings
	set_sun_energy(preset.sun_energy)
	set_sun_color(preset.sun_color)
	set_sun_angles(preset.sun_angle_h, preset.sun_angle_v)
	set_ambient_energy(preset.ambient_energy)
	set_ambient_color(preset.ambient_color)
	set_exposure(preset.exposure)
	set_shadow_opacity(preset.shadow_opacity)
	set_shadow_blur(preset.shadow_blur)

	# Apply shadow bias settings if present (for realistic shadows)
	if preset.has("shadow_bias"):
		set_shadow_bias(preset.shadow_bias)
	if preset.has("shadow_normal_bias"):
		set_shadow_normal_bias(preset.shadow_normal_bias)

	set_ssao_intensity(preset.ssao_intensity)
	set_ssr_intensity(preset.ssr_intensity)
	set_glow_intensity(preset.glow_intensity)
	set_contrast(preset.contrast)
	set_saturation(preset.saturation)

	print("Applied lighting preset: ", preset.name)


## Get list of preset names
func get_preset_names() -> Array:
	return PRESETS.keys()


## Individual parameter setters
func set_sun_energy(value: float) -> void:
	if _directional_light:
		_directional_light.light_energy = value
		current_preset.sun_energy = value


func set_sun_color(color: Color) -> void:
	if _directional_light:
		_directional_light.light_color = color
		current_preset.sun_color = color


func set_sun_angles(horizontal: float, vertical: float) -> void:
	if _directional_light:
		# Convert angles to transform
		var h_rad = deg_to_rad(horizontal)
		var v_rad = deg_to_rad(vertical)

		# Position light in a sphere around origin
		var distance = 10.0
		var x = distance * cos(v_rad) * sin(h_rad)
		var y = distance * sin(v_rad)
		var z = distance * cos(v_rad) * cos(h_rad)

		_directional_light.position = Vector3(x, y, z)
		_directional_light.look_at(Vector3.ZERO, Vector3.UP)

		current_preset.sun_angle_h = horizontal
		current_preset.sun_angle_v = vertical


func set_ambient_energy(value: float) -> void:
	if _environment:
		_environment.ambient_light_energy = value
		current_preset.ambient_energy = value


func set_ambient_color(color: Color) -> void:
	if _environment:
		_environment.ambient_light_color = color
		current_preset.ambient_color = color


func set_exposure(value: float) -> void:
	if _environment:
		_environment.tonemap_exposure = value
		current_preset.exposure = value


func set_shadow_opacity(value: float) -> void:
	if _directional_light:
		_directional_light.shadow_opacity = value
		current_preset.shadow_opacity = value


func set_shadow_blur(value: float) -> void:
	if _directional_light:
		_directional_light.shadow_blur = value
		current_preset.shadow_blur = value


func set_shadow_bias(value: float) -> void:
	if _directional_light:
		_directional_light.directional_shadow_bias = value
		current_preset.shadow_bias = value


func set_shadow_normal_bias(value: float) -> void:
	if _directional_light:
		_directional_light.directional_shadow_normal_bias = value
		current_preset.shadow_normal_bias = value


func set_ssao_intensity(value: float) -> void:
	if _environment:
		_environment.ssao_intensity = value
		current_preset.ssao_intensity = value


func set_ssr_intensity(value: float) -> void:
	if _environment:
		_environment.ssr_fade_in = value
		current_preset.ssr_intensity = value


func set_glow_intensity(value: float) -> void:
	if _environment:
		_environment.glow_intensity = value
		current_preset.glow_intensity = value


func set_contrast(value: float) -> void:
	if _environment:
		_environment.adjustment_contrast = value
		current_preset.contrast = value


func set_saturation(value: float) -> void:
	if _environment:
		_environment.adjustment_saturation = value
		current_preset.saturation = value


## Save current settings as JSON
func export_current_settings() -> String:
	return JSON.stringify(current_preset, "\t")


## Print current settings to console
func print_current_settings() -> void:
	print("\n=== CURRENT LIGHTING SETTINGS ===")
	for key in current_preset:
		print("  %s: %s" % [key, str(current_preset[key])])
	print("=================================\n")
