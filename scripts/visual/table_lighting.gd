extends RefCounted
## Approved tabletop rig. Weather keeps its own light; biome palettes tint daylight.
const Lighting := preload("res://scripts/lighting_controller.gd")
const MOODS := {"Day":"Default", "Sunset":"Warm Sunset", "Night":"Night", "Rain":"Storm", "Overcast":"Cool Overcast"}

static func values(profile: Dictionary, mood: String) -> Dictionary:
	var v: Dictionary = Lighting.PRESETS[MOODS.get(mood, "Default")].duplicate()
	if mood in ["Day", "Sunset"]:
		var evening := mood == "Sunset"
		var angles: Vector2 = profile["sun_angles_sunset" if evening else "sun_angles_day"]
		v.merge({"sun_energy":profile.sun_energy * 3.0 / 2.55,
			"sun_color":profile["sun_color_sunset" if evening else "sun_color_day"],
			"sun_angle_h":-145.0 if evening else angles.y, "sun_angle_v":22.0 if evening else -angles.x,
			"ambient_energy":0.48, "ambient_color":Color(0.55,0.66,0.86).lerp(profile.ambient_color,0.2),
			"fill_light_energy":0.75, "fill_light_color":Color(0.51,0.67,1.0),
			"exposure":1.08, "shadow_opacity":0.92, "shadow_blur":1.5}, true)
		if profile.name == "grassland":
			v.ambient_color = Color(0.55,0.66,0.86)
			if evening:
				v.sun_color = Color(1.0,0.85,0.64)
		if profile.name == "arid_desert":
			v.exposure = 0.78 # Bright sand needs half a stop of highlight headroom.
	return v

static func apply(main: Node, profile: Dictionary, mood: String) -> void:
	var light: Node = main.lighting_controller
	var v := values(profile, mood)
	for key in ["sun_energy", "sun_color", "ambient_energy", "ambient_color", "fill_light_energy",
			"fill_light_color", "exposure", "shadow_opacity", "shadow_blur", "ssao_intensity"]:
		light.call("set_" + key, v[key])
	light.set_sun_angles(v.sun_angle_h, v.sun_angle_v)
	var fill: DirectionalLight3D = main.get_node("FillLight")
	fill.rotation_degrees = Vector3(-42,20,0)
	fill.light_volumetric_fog_energy = 0.0
