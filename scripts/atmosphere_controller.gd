class_name AtmosphereController
extends Node
## One-click battlefield atmosphere: each preset bundles a lighting preset
## (lighting_controller stays the single source of truth for light values) with sky
## mood, ground-mist tint/density, rain, lightning + thunder and rain audio. Presets
## blend over TRANSITION_SECONDS. Orthogonal toggles: "war-torn" ruin fires
## (terrain_overlay) and occasional distant war sounds (WarAmbience).
##
## Atmosphere is a per-player preference (not multiplayer-synced, like lighting);
## only the FIRE POSITIONS are identical on all clients because they derive
## deterministically from the synced wall data. State persists to user://atmosphere.cfg.

# === Constants ===

const CONFIG_PATH := "user://atmosphere.cfg"
const CONFIG_SECTION := "atmosphere"
const TRANSITION_SECONDS := 2.0
const DEFAULT_PRESET := "Sunset"

const LIGHTNING_MIN_INTERVAL_S := 8.0
const LIGHTNING_MAX_INTERVAL_S := 25.0
const THUNDER_MIN_DELAY_S := 0.5
const THUNDER_MAX_DELAY_S := 3.0

## space_skybox.gdshader defaults: get_shader_parameter returns NULL for parameters
## that were never explicitly set, so reads need these fallbacks.
const SKY_DEFAULT_STAR_BRIGHTNESS := 2.2
const SKY_DEFAULT_NEBULA_INTENSITY := 0.5

## Sky defaults in space_skybox.gdshader: star_brightness 2.2, nebula_intensity 0.5.
const PRESETS := {
	"Day": {
		"lighting": "Default",
		"star_brightness": 1.2, "nebula_intensity": 0.35,
		"mist_color": Color(0.95, 0.96, 0.98), "mist_density": 1.0,
		"rain": false, "lightning": false,
	},
	"Sunset": {
		"lighting": "Warm Sunset",
		"star_brightness": 1.8, "nebula_intensity": 0.55,
		"mist_color": Color(0.97, 0.92, 0.86), "mist_density": 1.0,
		"rain": false, "lightning": false,
	},
	"Night": {
		"lighting": "Night",
		"star_brightness": 3.2, "nebula_intensity": 0.7,
		"mist_color": Color(0.74, 0.78, 0.88), "mist_density": 1.1,
		"rain": false, "lightning": false,
	},
	"Overcast": {
		"lighting": "Cool Overcast",
		"star_brightness": 0.8, "nebula_intensity": 0.3,
		"mist_color": Color(0.8, 0.83, 0.88), "mist_density": 1.3,
		"rain": false, "lightning": false,
	},
	"Rain": {
		"lighting": "Storm",
		"star_brightness": 0.5, "nebula_intensity": 0.25,
		"mist_color": Color(0.62, 0.66, 0.72), "mist_density": 1.5,
		"rain": true, "lightning": true,
	},
}

## Lighting-preset keys the blend interpolates, mapped to lighting_controller setters.
const _BLEND_FLOAT_SETTERS := {
	"sun_energy": "set_sun_energy",
	"ambient_energy": "set_ambient_energy",
	"exposure": "set_exposure",
	"shadow_opacity": "set_shadow_opacity",
	"shadow_blur": "set_shadow_blur",
	"ssao_intensity": "set_ssao_intensity",
	"fill_light_energy": "set_fill_light_energy",
	"ssr_intensity": "set_ssr_intensity",
	"glow_intensity": "set_glow_intensity",
	"contrast": "set_contrast",
	"saturation": "set_saturation",
}
const _BLEND_COLOR_SETTERS := {
	"sun_color": "set_sun_color",
	"ambient_color": "set_ambient_color",
	"fill_light_color": "set_fill_light_color",
}

# === Signals ===

signal atmosphere_changed(preset_name: String)

# === Private variables ===

var _lighting: Node = null
var _world_env: WorldEnvironment = null
var _clouds: Node3D = null
var _terrain_overlay: Node3D = null
var _rain: RainEffect = null
var _war: WarAmbience = null
var _lightning_timer: Timer = null
var _transition_tween: Tween = null
var _rng := RandomNumberGenerator.new()

var _current_name := DEFAULT_PRESET
# War-torn ruin fires + distant war sounds default ON — a lived-in battlefield is the
# intended first impression. Both persist, so toggling either off in-game sticks; this
# default only applies to a fresh install (no saved atmosphere config).
var _fires_enabled := true
var _war_sounds_enabled := true
## Tracked mist state (atmospheric_clouds has no getters).
var _mist_color := Color(0.95, 0.96, 0.98)
var _mist_density := 1.0

# === Lifecycle ===

func _ready() -> void:
	_rng.randomize()  # lightning timing only; nothing here is gameplay-synced

	_rain = RainEffect.new()
	_rain.name = "RainEffect"
	add_child(_rain)

	_war = WarAmbience.new()
	_war.name = "WarAmbience"
	add_child(_war)

	_lightning_timer = Timer.new()
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_on_lightning_due)
	add_child(_lightning_timer)

# === Public ===

## Wire the scene dependencies (mirrors lighting_controller.initialize).
func initialize(lighting_ctrl: Node, world_env: WorldEnvironment, clouds: Node3D,
		terrain_overlay: Node3D) -> void:
	_lighting = lighting_ctrl
	_world_env = world_env
	_clouds = clouds
	_terrain_overlay = terrain_overlay
	if _terrain_overlay != null and _terrain_overlay.has_signal("fires_rebuilt"):
		_terrain_overlay.fires_rebuilt.connect(_on_fires_rebuilt)
	_load_config()


## Apply the saved/default atmosphere's LIGHTING (sun, sky, mist) instantly, without
## the table-dependent layers (fires, war sounds). Called at startup BEFORE the intro
## so the table is already lit in its final mood when the cinematic reveals it — avoids
## a jarring lighting snap when the intro ends.
func apply_saved_lighting() -> void:
	apply_atmosphere(_current_name, true)


## Restore the persisted atmosphere instantly (call once the table is built). The
## lighting was already applied at startup (apply_saved_lighting); this re-applies it
## (a no-op visually) and enables the table-dependent layers (fires, war sounds).
func restore_saved() -> void:
	apply_atmosphere(_current_name, true)
	if _fires_enabled and _terrain_overlay != null:
		_terrain_overlay.set_fires_enabled(true)
	if _war_sounds_enabled:
		_war.set_war_sounds_enabled(true)


func get_atmosphere_names() -> Array:
	return PRESETS.keys()


func get_current_atmosphere() -> String:
	return _current_name


## Switch the atmosphere. Lighting/sky/mist blend over TRANSITION_SECONDS unless
## instant; rain/lightning/audio toggle at the start (they fade internally).
func apply_atmosphere(preset_name: String, instant: bool = false) -> void:
	if not PRESETS.has(preset_name):
		push_warning("Unknown atmosphere '%s' (known: %s)" % [preset_name, ", ".join(PRESETS.keys())])
		return
	var preset: Dictionary = PRESETS[preset_name]
	_current_name = preset_name

	var lighting_to: Dictionary = {}
	if _lighting != null:
		lighting_to = _lighting.PRESETS.get(preset["lighting"], {})

	# Non-blended layers switch immediately (each fades internally).
	_rain.set_raining(preset["rain"])
	_war.set_rain_audio(preset["rain"])
	if preset["lightning"]:
		_schedule_lightning()
	else:
		_lightning_timer.stop()

	cancel_transition()
	if instant or _lighting == null:
		_apply_blend(1.0, {}, lighting_to, _sky_state(), preset, _mist_color, _mist_density)
	else:
		var lighting_from: Dictionary = _lighting.current_preset.duplicate()
		var sky_from := _sky_state()
		var mist_color_from := _mist_color
		var mist_density_from := _mist_density
		_transition_tween = create_tween()
		_transition_tween.tween_method(
				_apply_blend.bind(lighting_from, lighting_to, sky_from, preset,
						mist_color_from, mist_density_from),
				0.0, 1.0, TRANSITION_SECONDS)

	_save_config()
	atmosphere_changed.emit(preset_name)


## Stop a running preset blend (e.g. when the user grabs a lighting slider).
func cancel_transition() -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null


func set_fires_enabled(enabled: bool) -> void:
	_fires_enabled = enabled
	if _terrain_overlay != null:
		_terrain_overlay.set_fires_enabled(enabled)
	_save_config()


func is_fires_enabled() -> bool:
	return _fires_enabled


func set_war_sounds_enabled(enabled: bool) -> void:
	_war_sounds_enabled = enabled
	_war.set_war_sounds_enabled(enabled)
	_save_config()


func is_war_sounds_enabled() -> bool:
	return _war_sounds_enabled


func set_table_size(size_m: Vector2) -> void:
	_rain.set_table_size(size_m)

# === Private ===

## Blend step: t in 0..1 interpolates lighting (via the controller's setters, which
## keep current_preset in sync), sky shader mood and mist tint/density. Keys missing
## in `from` jump straight to the target value.
func _apply_blend(t: float, lighting_from: Dictionary, lighting_to: Dictionary,
		sky_from: Dictionary, preset: Dictionary,
		mist_color_from: Color, mist_density_from: float) -> void:
	if _lighting != null and not lighting_to.is_empty():
		for key: String in _BLEND_FLOAT_SETTERS:
			if not lighting_to.has(key):
				continue
			var to_value: float = lighting_to[key]
			var from_value: float = lighting_from.get(key, to_value)
			_lighting.call(_BLEND_FLOAT_SETTERS[key], lerpf(from_value, to_value, t))
		for key: String in _BLEND_COLOR_SETTERS:
			if not lighting_to.has(key):
				continue
			var to_color: Color = lighting_to[key]
			var from_color: Color = lighting_from.get(key, to_color)
			_lighting.call(_BLEND_COLOR_SETTERS[key], from_color.lerp(to_color, t))
		# Sun angles: horizontal wraps (take the short way), vertical lerps plainly.
		var to_h: float = lighting_to.get("sun_angle_h", 0.0)
		var from_h: float = lighting_from.get("sun_angle_h", to_h)
		var to_v: float = lighting_to.get("sun_angle_v", 45.0)
		var from_v: float = lighting_from.get("sun_angle_v", to_v)
		var h := rad_to_deg(lerp_angle(deg_to_rad(from_h), deg_to_rad(to_h), t))
		_lighting.set_sun_angles(h, lerpf(from_v, to_v, t))

	var sky := _sky_material()
	if sky != null:
		sky.set_shader_parameter("star_brightness",
				lerpf(sky_from.get("star_brightness", preset["star_brightness"]),
						preset["star_brightness"], t))
		sky.set_shader_parameter("nebula_intensity",
				lerpf(sky_from.get("nebula_intensity", preset["nebula_intensity"]),
						preset["nebula_intensity"], t))

	_mist_color = mist_color_from.lerp(preset["mist_color"], t)
	_mist_density = lerpf(mist_density_from, preset["mist_density"], t)
	if _clouds != null:
		if _clouds.has_method("set_cloud_color"):
			_clouds.set_cloud_color(_mist_color)
		if _clouds.has_method("set_density_scale"):
			_clouds.set_density_scale(_mist_density)


func _sky_material() -> ShaderMaterial:
	if _world_env == null or _world_env.environment == null or _world_env.environment.sky == null:
		return null
	return _world_env.environment.sky.sky_material as ShaderMaterial


func _sky_state() -> Dictionary:
	var sky := _sky_material()
	if sky == null:
		return {}
	# Never-set shader parameters read as NULL (the shader's own default is invisible
	# to get_shader_parameter) — fall back to the shader defaults.
	var star: Variant = sky.get_shader_parameter("star_brightness")
	var nebula: Variant = sky.get_shader_parameter("nebula_intensity")
	return {
		"star_brightness": float(star) if star != null else SKY_DEFAULT_STAR_BRIGHTNESS,
		"nebula_intensity": float(nebula) if nebula != null else SKY_DEFAULT_NEBULA_INTENSITY,
	}


func _schedule_lightning() -> void:
	_lightning_timer.wait_time = _rng.randf_range(LIGHTNING_MIN_INTERVAL_S, LIGHTNING_MAX_INTERVAL_S)
	_lightning_timer.start()


func _on_lightning_due() -> void:
	if not PRESETS[_current_name]["lightning"]:
		return
	_rain.flash_lightning()
	var delay := _rng.randf_range(THUNDER_MIN_DELAY_S, THUNDER_MAX_DELAY_S)
	get_tree().create_timer(delay).timeout.connect(_war.play_thunder.bind(delay))
	_schedule_lightning()


func _on_fires_rebuilt() -> void:
	if _terrain_overlay != null and _terrain_overlay.has_method("get_fire_positions"):
		_war.update_fire_crackle(_terrain_overlay.get_fire_positions())


func _load_config() -> void:
	# The atmosphere PRESET is NOT persisted across launches: every game starts in the
	# DEFAULT_PRESET (Sunset) as the standard look. In-game switching still works for the
	# session; it just doesn't carry over to the next start. The war-torn / war-sound
	# toggles do persist (they're independent of the lighting mood).
	_current_name = DEFAULT_PRESET
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	_fires_enabled = config.get_value(CONFIG_SECTION, "fires_enabled", true)
	_war_sounds_enabled = config.get_value(CONFIG_SECTION, "war_sounds_enabled", true)


func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "fires_enabled", _fires_enabled)
	config.set_value(CONFIG_SECTION, "war_sounds_enabled", _war_sounds_enabled)
	config.save(CONFIG_PATH)
