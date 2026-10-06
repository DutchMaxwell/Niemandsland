extends GdUnitTestSuite
const Settings := preload("res://scripts/graphics_settings.gd")
const Reference := preload("res://scripts/visual/grassland_reference.gd")

class Host extends Node:
	var render_state: RenderState

func test_high_gi_and_mist_survive_the_reference_and_downgrade() -> void:
	var old := GraphicsSettings.current_preset
	var env := Environment.new()
	var main: Host = auto_free(Host.new())
	main.render_state = RenderState.new(env)
	var reference: Node3D = auto_free(Reference.new())
	reference.table_tier = true
	reference.set("_main", main)
	add_child(reference)
	reference.set_process(false)
	for tier in [3,4,2,1]:
		GraphicsSettings.current_preset = tier as GraphicsSettings.QualityPreset
		main.render_state.set_layer("preset", Settings.environment_values(Settings.PRESETS[tier],tier))
		if tier >= 2:
			reference.call("_apply_reference_environment")
		else:
			main.render_state.set_layer("reference", {})
		assert_bool(env.sdfgi_enabled).is_equal(tier >= 3)
		assert_bool(env.ssil_enabled).is_equal(tier >= 3)
		assert_bool(env.volumetric_fog_enabled).is_equal(tier >= 3)
		if tier >= 3:
			assert_float(env.sdfgi_min_cell_size).is_less(0.02)
			assert_float(env.volumetric_fog_length).is_equal_approx(6.0,0.001)
	GraphicsSettings.current_preset = old
	reference.set("_main", null)
