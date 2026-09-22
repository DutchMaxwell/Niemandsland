extends GdUnitTestSuite
## The dead look (OPRArmyManager._desaturate_model) must never park a surface material UNDER a
## material_override. The override hides it anyway, and Godot 4.6 never tracks a surface material
## that an override shadows: freeing such a node on a real renderer prints four engine errors per
## mesh ('Parameter "material" is null' at material_casts_shadows, material_is_animated,
## material_get_instance_shader_parameters, material_update_dependency) — 104 of them per game.
## Every model's BaseDecor base (rim, top, affiliation ring) carries exactly such an override.


func _model() -> Node3D:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	add_child(body)
	var figure := MeshInstance3D.new()
	figure.name = "Figure"
	figure.mesh = BoxMesh.new()
	body.add_child(figure)
	body.add_child(BaseDecor.build_base(false, false, 0.025, 0.025, 0.0125, Color.RED, true, null))
	return body


func test_dead_look_greys_the_figure_but_never_puts_a_material_under_an_override() -> void:
	var mgr: OPRArmyManager = auto_free(OPRArmyManager.new())
	var body := _model()
	var figure := body.get_node("Figure") as MeshInstance3D
	mgr._desaturate_model(body)
	# The figure (no override) still gets the greyscale material ...
	assert_object(figure.get_surface_override_material(0)).is_instanceof(ShaderMaterial)
	# ... but no overridden base mesh carries a surface material.
	var overridden := 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.material_override == null:
			continue
		overridden += 1
		for s in mi.mesh.get_surface_count():
			var why := "%s surface %d has a material under its override" % [mi.name, s]
			assert_object(mi.get_surface_override_material(s)).override_failure_message(why).is_null()
	assert_int(overridden).is_equal(3)   # BaseRim, BaseTop, AffiliationRing
	# Revive restores the figure's original (empty) surface override.
	mgr._restore_model_material(body)
	assert_object(figure.get_surface_override_material(0)).is_null()
