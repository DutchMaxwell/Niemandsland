extends GdUnitTestSuite
## Splatters (combat effects): a flat pool lies just above the spot it is given, its look comes from the cue's seed
## alone (no RNG), the pool is capped so a long game never piles them up (the oldest goes), and each one fades and
## frees itself after its life.

const SplattersScript = preload("res://scripts/vfx/splatters.gd")


func _splatters() -> Node3D:
	var s = auto_free(SplattersScript.new())
	add_child(s)
	return s


func test_a_splatter_lies_on_its_spot_shaped_by_the_seed() -> void:
	var s := _splatters()
	var a: MeshInstance3D = s.add(Vector3(0.2, 0.05, -0.1), 0.03, Color(0.5, 0.02, 0.02), 4242, 5.0)
	var b: MeshInstance3D = s.add(Vector3(0.2, 0.05, -0.1), 0.03, Color(0.5, 0.02, 0.02), 4242, 5.0)
	assert_float(a.global_position.y).is_equal_approx(0.05 + SplattersScript.LIFT_M, 1e-6)
	assert_float((a.mesh as PlaneMesh).size.x).is_equal_approx(0.03, 1e-6)
	assert_float(a.rotation.y).is_equal_approx(b.rotation.y, 1e-6)
	assert_float(float((a.material_override as ShaderMaterial).get_shader_parameter("seed"))) \
		.is_equal(float((b.material_override as ShaderMaterial).get_shader_parameter("seed")))


func test_the_pool_is_capped_and_the_oldest_goes() -> void:
	var s := _splatters()
	s.cap = 3
	var first: MeshInstance3D = s.add(Vector3.ZERO, 0.02, Color.RED, 1, 5.0)
	for i in 4:
		s.add(Vector3(0.01 * i, 0, 0), 0.02, Color.RED, 2 + i, 5.0)
	assert_int(s.get_child_count()).is_equal(3)
	assert_bool(first.get_parent() == s).override_failure_message("the oldest splatter is evicted").is_false()


func test_splatters_leave_the_game_rng_alone() -> void:
	var s := _splatters()
	seed(17)
	var expected := randi()
	seed(17)
	for i in 6:
		s.add(Vector3(0.01 * i, 0, 0), 0.02, Color.RED, 50 + i, 5.0, 1.0 if i % 2 == 0 else 0.0)
	assert_int(randi()).is_equal(expected)


func test_a_splatter_fades_and_frees_itself(timeout := 6000) -> void:
	var s := _splatters()
	s.add(Vector3.ZERO, 0.02, Color.RED, 9, 0.1)
	assert_int(s.get_child_count()).is_equal(1)
	await get_tree().create_timer(2.0).timeout   # life 0.1 s + the 1.5 s fade
	assert_int(s.get_child_count()).is_equal(0)
