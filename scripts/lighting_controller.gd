extends Node
## Lighting controller with real-time adjustments and preset system
## Allows fine-tuning of all lighting parameters for perfect visuals

# References to scene nodes
var _directional_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _world_environment: WorldEnvironment
var _environment: Environment

# Current lighting settings
var current_preset: Dictionary = {}

# Lighting definitions backing each ATMOSPHERE mood (Day->Default, Sunset->Warm
# Sunset, Night->Night, Overcast->Cool Overcast, Rain->Storm). These are no longer a
# user-facing preset list — moods are chosen via the AtmosphereController only; this
# table is the internal lighting data its presets blend between.
const PRESETS = {
	"Default": {
		"name": "Default (Warm & Cozy)",
		"sun_energy": 1.8,
		"sun_color": Color(1.0, 0.8, 0.6),
		"sun_angle_h": 84.0,  # Horizontal angle (degrees)
		"sun_angle_v": 43.0,   # Vertical angle (degrees)
		# Sky-driven ambient now adds fill, and AgX tonemap has its own contrast/colour
		# response — so ambient/exposure/glow are dialled down vs the old ACES setup (the
		# bright physical sky + sky-ambient otherwise blow the scene out to white).
		"ambient_energy": 0.25,
		"ambient_color": Color(0.85, 0.82, 0.78),
		"exposure": 0.9,
		"shadow_opacity": 0.85,
		"shadow_blur": 1.5,
		"shadow_bias": 0.03,  # Balanced to prevent acne and detachment
		"shadow_normal_bias": 1.0,  # Higher prevents shadow detachment on slopes
		"ssao_intensity": 0.4,
		"fill_light_energy": 0.3,
		"fill_light_color": Color(0.7, 0.8, 1.0),
		"ssr_intensity": 0.2,
		"glow_intensity": 0.9,
		"contrast": 1.05,
		"saturation": 1.05,
	},
	"Warm Sunset": {
		"name": "Warm Sunset (Cozy)",
		"sun_energy": 1.5,
		"sun_color": Color(1.0, 0.8, 0.6),
		"sun_angle_h": -45.0,
		"sun_angle_v": 25.0,
		"ambient_energy": 0.7,
		"ambient_color": Color(0.85, 0.82, 0.78),
		"exposure": 1.3,
		"shadow_opacity": 0.7,
		"shadow_blur": 3.0,
		"ssao_intensity": 0.4,
		"fill_light_energy": 0.3,
		"fill_light_color": Color(0.7, 0.75, 0.9),
		"ssr_intensity": 0.8,
		"glow_intensity": 1.2,
		"contrast": 1.15,
		"saturation": 1.15,
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
		"ssao_intensity": 0.4,
		"fill_light_energy": 0.25,
		"fill_light_color": Color(0.75, 0.8, 0.95),
		"ssr_intensity": 0.9,
		"glow_intensity": 0.4,
		"contrast": 1.05,
		"saturation": 0.95,
	},
	"Night": {
		"name": "Night (Moonlit)",
		"sun_energy": 0.35,  # the sun doubles as cool moonlight
		"sun_color": Color(0.65, 0.72, 1.0),
		"sun_angle_h": 120.0,
		"sun_angle_v": 35.0,
		"ambient_energy": 0.12,
		"ambient_color": Color(0.2, 0.25, 0.4),
		"exposure": 0.8,
		"shadow_opacity": 0.9,
		"shadow_blur": 2.0,
		"ssao_intensity": 0.5,
		"fill_light_energy": 0.1,
		"fill_light_color": Color(0.5, 0.6, 0.9),
		"ssr_intensity": 0.3,
		"glow_intensity": 1.3,  # emissive props (ruin fires) pop in the dark
		"contrast": 1.1,
		"saturation": 0.9,
	},
	"Storm": {
		"name": "Storm (Rain)",
		"sun_energy": 0.5,
		"sun_color": Color(0.75, 0.8, 0.9),
		"sun_angle_h": 0.0,
		"sun_angle_v": 65.0,
		"ambient_energy": 0.45,
		"ambient_color": Color(0.55, 0.6, 0.7),
		"exposure": 0.85,
		"shadow_opacity": 0.35,
		"shadow_blur": 4.5,
		"ssao_intensity": 0.4,
		"fill_light_energy": 0.2,
		"fill_light_color": Color(0.7, 0.75, 0.85),
		"ssr_intensity": 0.9,  # wet-table sheen
		"glow_intensity": 0.5,
		"contrast": 1.05,
		"saturation": 0.85,
	},
}


func _ready() -> void:
	# Will be initialized when connected to scene nodes
	pass


## Initialize with scene references
func initialize(directional_light: DirectionalLight3D, world_env: WorldEnvironment, fill_light: DirectionalLight3D = null) -> void:
	_directional_light = directional_light
	_fill_light = fill_light
	_world_environment = world_env
	_environment = world_env.environment

	# Apply a baseline preset synchronously (the light + environment are passed in, so
	# they already exist). Deferring it raced the atmosphere controller's startup mood:
	# the deferred Default fired AFTER the atmosphere applied its preset, snapping the
	# table back to Default mid-intro. main.gd applies the real startup mood (Sunset)
	# right after this, overriding the baseline deterministically.
	apply_preset("Default")


## Apply a preset by name
func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		push_warning("Preset not found: ", preset_name)
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
	if preset.has("fill_light_energy"):
		set_fill_light_energy(preset.fill_light_energy)
	if preset.has("fill_light_color"):
		set_fill_light_color(preset.fill_light_color)
	set_ssr_intensity(preset.ssr_intensity)
	set_glow_intensity(preset.glow_intensity)
	set_contrast(preset.contrast)
	set_saturation(preset.saturation)


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
		_directional_light.shadow_bias = value  # Correct property name in Godot 4
		current_preset.shadow_bias = value


func set_shadow_normal_bias(value: float) -> void:
	if _directional_light:
		_directional_light.shadow_normal_bias = value  # Correct property name in Godot 4
		current_preset.shadow_normal_bias = value


func set_fill_light_energy(value: float) -> void:
	if _fill_light:
		_fill_light.light_energy = value
		current_preset.fill_light_energy = value


func set_fill_light_color(color: Color) -> void:
	if _fill_light:
		_fill_light.light_color = color
		current_preset.fill_light_color = color


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


## Print current settings to console
func print_current_settings() -> void:
	print("\n=== CURRENT LIGHTING SETTINGS ===")
	for key in current_preset:
		print("  %s: %s" % [key, str(current_preset[key])])
	print("=================================\n")
