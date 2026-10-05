extends GdUnitTestSuite
## SpellHeroes, step 1: a light pillar stands on its target and fades away; the success pulse is a canvas overlay that
## peaks at a low alpha (a glow, never a flash) and goes, and never touches the Environment (RenderState owns it).

const HeroesScript = preload("res://scripts/vfx/spell_heroes.gd")


func _host() -> Node3D:
	var n := auto_free(Node3D.new()) as Node3D
	add_child(n)
	return n


func test_a_pillar_stands_on_its_target_and_fades(timeout := 5000) -> void:
	var h := _host()
	HeroesScript.pillar(h, Vector3(0.2, 0.05, 0.1), Color(1, 1, 2))
	var pillar := h.get_child(0) as MeshInstance3D
	assert_float(Vector2(pillar.global_position.x, pillar.global_position.z).distance_to(Vector2(0.2, 0.1))).is_less(1e-6)
	await get_tree().create_timer(0.4).timeout
	assert_float(float((pillar.material_override as ShaderMaterial).get_shader_parameter("fade"))).is_less(1.0)
	await get_tree().create_timer(0.5).timeout
	assert_int(h.get_child_count()).is_equal(0)


func test_the_pulse_is_a_soft_overlay_that_goes(timeout := 5000) -> void:
	var h := _host()
	HeroesScript.pulse(h, Color(1, 0.5, 0.2))
	var layer := h.get_child(0) as CanvasLayer
	assert_object(layer).is_not_null()
	var mat := (layer.get_child(0) as ColorRect).material as ShaderMaterial
	var peak := 0.0
	for i in 12:
		await get_tree().process_frame
		peak = maxf(peak, float(mat.get_shader_parameter("strength")))
	assert_float(peak).is_greater(0.0)
	assert_float(peak).override_failure_message("a glow, never a flash").is_less_equal(HeroesScript.PULSE_MAX + 1e-6)
	await get_tree().create_timer(0.5).timeout
	assert_int(h.get_child_count()).is_equal(0)
	assert_int(h.find_children("*", "WorldEnvironment", true, false).size()).is_equal(0)
