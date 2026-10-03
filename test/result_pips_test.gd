extends GdUnitTestSuite
## VFX #1 result pips (INV_vfx §5): the marks read the allocation the resolver already made — one tick per
## wound that landed on a surviving model, one cross per casualty — and spawn nothing when switched off,
## for a zero count, or headless without the test opt-in. They never touch the game's RNG.

const ResultPipsScript = preload("res://scripts/vfx/result_pips.gd")


func _pips():
	var p = auto_free(ResultPipsScript.new())
	p.force_for_tests = true
	add_child(p)
	p.enabled = true   # the player setting defaults to off (see the first test)
	return p


func test_off_by_default_until_the_look_is_approved() -> void:
	var p = auto_free(ResultPipsScript.new())
	p.force_for_tests = true
	add_child(p)
	assert_bool(GraphicsSettings.show_combat_effects).is_false()
	assert_object(p.mark(ResultPipsScript.Kind.KILL, Vector3.ZERO, 1)).is_null()
	GraphicsSettings.show_combat_effects = true
	var q = auto_free(ResultPipsScript.new())
	q.force_for_tests = true
	add_child(q)
	GraphicsSettings.show_combat_effects = false
	assert_object(q.mark(ResultPipsScript.Kind.KILL, Vector3.ZERO, 1)).is_not_null()


func _model_at(pos: Vector3) -> ModelInstance:
	var mi := ModelInstance.new()
	mi.node = auto_free(Node3D.new())
	add_child(mi.node)
	mi.node.global_position = pos
	return mi


func test_wound_ticks_count_the_landed_wounds() -> void:
	var p = _pips()
	var pip: MeshInstance3D = p.mark(ResultPipsScript.Kind.WOUND, Vector3(1, 0, 2), 3)
	assert_object(pip).is_not_null()
	var mat := pip.material_override as ShaderMaterial
	assert_int(int(mat.get_shader_parameter("count"))).is_equal(3)
	assert_int(int(mat.get_shader_parameter("shape"))).is_equal(ResultPipsScript.Kind.WOUND)
	assert_float((pip.mesh as QuadMesh).size.x).is_equal_approx(3 * ResultPipsScript.SIZE_M, 1e-6)


func test_a_long_strip_is_capped_at_ten_symbols() -> void:
	var pip: MeshInstance3D = _pips().mark(ResultPipsScript.Kind.HIT, Vector3.ZERO, 23)
	assert_int(int((pip.material_override as ShaderMaterial).get_shader_parameter("count"))).is_equal(ResultPipsScript.MAX_TICKS)
	assert_float((pip.mesh as QuadMesh).size.x).is_equal_approx(ResultPipsScript.MAX_TICKS * ResultPipsScript.SIZE_M, 1e-6)


func test_a_casualty_gets_a_cross_over_its_eye() -> void:
	var p = _pips()
	var mi := _model_at(Vector3(0.5, 0.1, -0.3))
	var pip: MeshInstance3D = p.mark_model(ResultPipsScript.Kind.KILL, mi, 1)
	assert_int(int((pip.material_override as ShaderMaterial).get_shader_parameter("shape"))) \
		.is_equal(ResultPipsScript.Kind.KILL)
	var eye_m := VolumetricLos.height_in_for_base_mm(VolumetricLos.model_base_radius_m(mi) * 2000.0) \
		* VolumetricLos.INCHES_TO_METERS
	assert_float(pip.global_position.y).is_equal_approx(0.1 + eye_m + ResultPipsScript.LIFT_M, 1e-5)
	assert_float(pip.global_position.x).is_equal_approx(0.5, 1e-6)


func test_off_or_zero_spawns_nothing() -> void:
	var p = _pips()
	assert_object(p.mark(ResultPipsScript.Kind.WOUND, Vector3.ZERO, 0)).is_null()
	p.enabled = false
	assert_object(p.mark(ResultPipsScript.Kind.KILL, Vector3.ZERO, 1)).is_null()
	assert_int(p.get_child_count()).is_equal(0)


func test_the_pool_is_capped() -> void:
	var p = _pips()
	for i in ResultPipsScript.MAX_LIVE + 9:
		p.mark(ResultPipsScript.Kind.WOUND, Vector3(i * 0.01, 0, 0), 1)
	assert_int(p.get_child_count()).is_equal(ResultPipsScript.MAX_LIVE)


func test_low_tiers_and_reduce_motion_get_the_still_form() -> void:
	assert_bool(ResultPipsScript.still_form(0, false)).is_true()    # Performance
	assert_bool(ResultPipsScript.still_form(1, false)).is_true()    # Low
	assert_bool(ResultPipsScript.still_form(2, false)).is_false()   # Medium
	assert_bool(ResultPipsScript.still_form(4, true)).is_true()     # Reduce Motion wins on Ultra


func test_marks_leave_the_game_rng_alone() -> void:
	var p = _pips()
	seed(4242)
	var expected := randi()
	seed(4242)
	p.mark(ResultPipsScript.Kind.WOUND, Vector3.ZERO, 2)
	p.mark_model(ResultPipsScript.Kind.KILL, _model_at(Vector3.ONE), 1)
	assert_int(randi()).is_equal(expected)
