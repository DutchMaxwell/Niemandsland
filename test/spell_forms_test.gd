extends GdUnitTestSuite
## SpellForms (the spell effects' shapes), step 1: a ribbon is a tapered strip along its path; a ring stays a ring (no
## vertex near its centre, so no spoke, centre line or crossbar can ever be drawn — maintainer 05.10.: no religious
## symbols); a target ripple is a small annulus, never the whole range disc; anything retired fades and frees itself;
## all materials share two shaders. Step 2: the ice prisms' placement is a pure function of the seed and scattered (never
## an evenly spaced radial star); a stream draws one ribbon per strand and frees them; no game RNG anywhere.

const FormsScript = preload("res://scripts/vfx/spell_forms.gd")


func _host() -> Node3D:
	var n := auto_free(Node3D.new()) as Node3D
	add_child(n)
	return n


func _vertices(m: MeshInstance3D) -> PackedVector3Array:
	return (m.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_a_ribbon_is_a_strip_along_its_path() -> void:
	var path := PackedVector3Array([Vector3.ZERO, Vector3(0.05, 0, 0), Vector3(0.1, 0.01, 0.02)])
	var v := _vertices(FormsScript.ribbon(_host(), path, 0.004, Color.WHITE))
	assert_int(v.size()).is_equal((path.size() - 1) * 6)
	assert_float(v[0].distance_to(path[0])).is_equal_approx(0.002, 1e-6)   # half the width either side
	assert_float(v[1].distance_to(path[0])).is_equal_approx(0.002, 1e-6)


func test_a_ring_has_no_spoke_and_a_ripple_is_only_an_annulus() -> void:
	var v := _vertices(FormsScript.curl(_host(), 0.05, 0.0, 1.0, 0.003, Color.WHITE))
	for p in v:
		assert_float(Vector2(p.x, p.z).length()).is_between(0.05 - 0.0016, 0.05 + 0.0016)
	var ripple: MeshInstance3D = FormsScript.ripple(_host(), Vector3(0.3, 0, 0.1), Color.WHITE, 0.075, false, true)
	for p in _vertices(ripple):
		assert_float(Vector2(p.x, p.z).length()).override_failure_message("never the whole disc").is_greater(0.07)


func test_two_materials_share_two_shaders() -> void:
	var a: ShaderMaterial = FormsScript.material(Color.RED)
	var b: ShaderMaterial = FormsScript.material(Color.BLUE)
	var c: ShaderMaterial = FormsScript.material(Color.RED, true)
	assert_object(a.shader).is_same(b.shader)
	assert_object(a.shader).is_not_same(c.shader)
	assert_float(float(a.get_shader_parameter("fade"))).is_equal(1.0)   # set first, so a tween can run it down


func test_a_retired_form_fades_and_frees_itself(timeout := 5000) -> void:
	var h := _host()
	var ring: MeshInstance3D = FormsScript.curl(h, 0.03, 0.0, 1.0, 0.002, Color.WHITE)
	FormsScript.retire(ring, 0.1, 0.2)
	await get_tree().create_timer(0.2).timeout
	assert_float(float((ring.material_override as ShaderMaterial).get_shader_parameter("fade"))).is_less(1.0)
	await get_tree().create_timer(0.4).timeout
	assert_int(h.get_child_count()).is_equal(0)


func test_ice_prisms_are_seeded_and_scattered_never_a_star() -> void:
	var plan: Array = FormsScript.crystal_plan(71, 11)
	assert_array(plan).is_equal(FormsScript.crystal_plan(71, 11))
	assert_array(plan).is_not_equal(FormsScript.crystal_plan(72, 11))
	var angles: Array = plan.map(func(t: Transform3D) -> float: return fposmod(atan2(t.origin.z, t.origin.x), TAU))
	angles.sort()
	var gaps: Array = []
	for i in angles.size():
		gaps.append(fposmod(float(angles[(i + 1) % angles.size()]) - float(angles[i]), TAU))
	gaps.sort()
	assert_float(float(gaps[-1]) - float(gaps[0])).override_failure_message("evenly spaced = a star").is_greater(0.2)
	var h := _host()
	FormsScript.crystals(h, Vector3.ZERO, 71, 11, true)
	assert_int((h.get_child(0) as MultiMeshInstance3D).multimesh.instance_count).is_equal(11)


func test_a_stream_draws_its_strands_and_frees_them(timeout := 5000) -> void:
	var h := _host()
	seed(9)
	var expected := randi()
	seed(9)
	FormsScript.stream(h, Vector3.ZERO, Vector3(0.2, 0.0, 0.1), Color.WHITE, 33, 3)
	assert_int(randi()).is_equal(expected)
	assert_int(h.get_child_count()).is_equal(3)
	await get_tree().create_timer(1.0).timeout
	assert_int(h.get_child_count()).is_equal(0)
