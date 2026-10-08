extends GdUnitTestSuite
const WORLD := "res://scripts/visual/table_world.gd"
const Biomes := preload("res://scripts/visual/reference_biomes.gd")

class Mood extends Node:
	signal atmosphere_changed(mood: String)
	func get_current_atmosphere() -> String:
		return "Sunset"

class Board extends Node3D:
	var table_size := Vector2(6,4)

class Host extends Node:
	var render_state: RenderState
	var atmosphere_controller: Node

func test_world_gate_palette_and_weather_follow_player_choices() -> void:
	assert_bool(FileAccess.file_exists(WORLD)).is_true()
	if not FileAccess.file_exists(WORLD):
		return
	var script = load(WORLD)
	for tier in 5:
		assert_bool(GraphicsSettings.call("world_enabled",tier)).is_equal(tier >= 3)   # High and Ultra stand in the landscape
	var desert: Dictionary = script.sky_values(Biomes.ARID_DESERT,"Sunset")
	var tundra: Dictionary = script.sky_values(Biomes.FROZEN_TUNDRA,"Sunset")
	assert_float(desert.biome_tint.r).is_greater(tundra.biome_tint.r)
	assert_float(desert.biome_tint.b).is_less(tundra.biome_tint.b)
	assert_int(script.sky_values(Biomes.GRASSLAND,"Night").world_mood).is_equal(3)
	assert_int(script.sky_values(Biomes.GRASSLAND,"Rain").world_mood).is_equal(4)

func test_world_removal_restores_sky_and_disables_sky_gi() -> void:
	if not FileAccess.file_exists(WORLD):
		return
	var main: Host = auto_free(Host.new())
	add_child(main)
	var table := Board.new()
	table.name = "Table"
	main.add_child(table)
	main.atmosphere_controller = Mood.new()
	main.add_child(main.atmosphere_controller)
	var env := Environment.new()
	var original := Sky.new()
	env.sky = original
	env.sdfgi_read_sky_light = false
	main.render_state = RenderState.new(env)
	var world: Node3D = load(WORLD).new()
	main.add_child(world)
	world.setup(main,Biomes.GRASSLAND)
	assert_object(env.sky).is_not_same(original)
	assert_bool(env.sdfgi_read_sky_light).is_true()
	main.atmosphere_controller.atmosphere_changed.emit("Rain")
	assert_int((env.sky.sky_material as ShaderMaterial).get_shader_parameter("world_mood")).is_equal(4)
	world.free()
	assert_object(env.sky).is_same(original)
	assert_bool(env.sdfgi_read_sky_light).is_false()
