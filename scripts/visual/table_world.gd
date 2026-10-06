extends Node3D
## Ultra's world follows the table presentation lifecycle and the atmosphere buttons.
const Biomes := preload("res://scripts/visual/reference_biomes.gd")
var _main: Node
var _profile: Dictionary
var _material: ShaderMaterial
var _state: RenderState

func setup(main: Node, profile: Dictionary) -> void:
	_main = main
	_profile = profile
	_state = main.render_state
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/visual/table_world_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _material
	_state.set_layer("world", {"sky":sky, "sdfgi_read_sky_light":true, "sdfgi_energy":0.75})
	main.atmosphere_controller.atmosphere_changed.connect(_on_mood)
	_on_mood(main.atmosphere_controller.get_current_atmosphere())

static func sky_values(profile: Dictionary, mood: String) -> Dictionary:
	return {"world_mood":["Sunset","Day","Overcast","Night","Rain"].find(mood),
		"biome_tint":profile.fog_color / Biomes.GRASSLAND.fog_color}

func _on_mood(mood: String) -> void:
	var values := sky_values(_profile, mood)
	for key in values:
		_material.set_shader_parameter(key,values[key])

func _exit_tree() -> void:
	if _state != null:
		_state.set_layer("world", {})
