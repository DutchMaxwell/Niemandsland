extends GdUnitTestSuite
## VFX #3 spell seal (special-effects plan): the seal's outer edge is the radius it is handed (the spell-range
## ring's own convention) within 1 mm, the kind shows in colour AND rune count, success flares, a fail cracks,
## every outcome removes the seal, the still form skips the sweep, and nothing spawns when off. No RNG.

const SealScript = preload("res://scripts/vfx/spell_seal.gd")
const CENTRE := Vector3(0.2, 0.0, -0.1)


func _seals():
	var s = auto_free(SealScript.new())
	s.force_for_tests = true
	add_child(s)
	s.enabled = true   # the player setting defaults to off
	return s


func _param(seal: MeshInstance3D, key: String) -> Variant:
	return (seal.material_override as ShaderMaterial).get_shader_parameter(key)


func test_the_outer_edge_is_the_spell_range_radius() -> void:
	var s = _seals()
	var rr := RangeRingController.new()
	var radius := rr.ring_outer_radius_for_props({"base_size_round": 32}, 12)
	rr.free()
	var seal: MeshInstance3D = s.begin(CENTRE, radius, "damage")
	assert_float((seal.mesh as PlaneMesh).size.x * 0.5).is_equal_approx(0.016 + 12 * 0.0254, 0.001)
	assert_float(float(_param(seal, "band")) * radius).is_equal_approx(SealScript.BAND_M, 1e-6)
	assert_float(seal.global_position.x).is_equal_approx(CENTRE.x, 1e-6)
	assert_float(seal.global_position.z).is_equal_approx(CENTRE.z, 1e-6)


func test_kinds_differ_in_colour_and_runes() -> void:
	var s = _seals()
	var seen := {}
	for kind: String in ["damage", "buff", "debuff", "utility"]:
		var seal: MeshInstance3D = s.begin(CENTRE, 0.2, kind)
		seen["%s/%d" % [str(_param(seal, "tint")), int(_param(seal, "runes"))]] = true
	assert_int(seen.size()).is_equal(4)
	assert_int(int(_param(s.begin(CENTRE, 0.2, "no-such-kind"), "runes"))).is_equal(SealScript.KINDS["utility"][1])


func test_success_flares_fail_cracks_and_both_leave(timeout := 20000) -> void:
	var s = _seals()
	var ok: MeshInstance3D = s.begin(CENTRE, 0.2, "buff")
	var bad: MeshInstance3D = s.begin(CENTRE, 0.2, "damage")
	s.interfere(bad)
	s.finish(ok, SealScript.Outcome.SUCCESS)
	s.finish(bad, SealScript.Outcome.FAIL)
	await get_tree().create_timer(0.14).timeout
	assert_float(float(_param(ok, "flare"))).is_greater(0.5)
	assert_float(float(_param(bad, "crack"))).is_greater(0.3)
	await get_tree().create_timer(1.2).timeout
	assert_bool(is_instance_valid(ok)).is_false()
	assert_bool(is_instance_valid(bad)).is_false()


func test_still_form_skips_the_sweep_and_off_spawns_nothing() -> void:
	var s = _seals()
	var before: int = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	assert_float(float(_param(s.begin(CENTRE, 0.2, "buff"), "progress"))).is_equal(0.0)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.PERFORMANCE
	assert_float(float(_param(s.begin(CENTRE, 0.2, "buff"), "progress"))).is_equal(1.0)
	GraphicsSettings.current_preset = before
	s.enabled = false
	assert_object(s.begin(CENTRE, 0.2, "buff")).is_null()


func test_the_seal_leaves_the_game_rng_alone() -> void:
	var s = _seals()
	seed(99)
	var expected := randi()
	seed(99)
	var seal: MeshInstance3D = s.begin(CENTRE, 0.3, "debuff")
	s.interfere(seal)
	s.finish(seal, SealScript.Outcome.CANCEL)
	assert_int(randi()).is_equal(expected)
