extends GdUnitTestSuite
## SpellImpacts: every element's release draws at the resolved targets, leaves the game's RNG alone and cleans up
## completely; lightning is the chain (one bolt holder), the others build their own forms at each target.

const ImpactsScript = preload("res://scripts/vfx/spell_impacts.gd")
const TARGETS := [Vector3(0.2, 0.04, 0.1), Vector3(0.26, 0.04, 0.2)]


func _host() -> Node3D:
	var n := auto_free(Node3D.new()) as Node3D
	add_child(n)
	return n


func test_every_element_releases_at_its_targets_and_cleans_up(timeout := 15000) -> void:
	var hosts := {}
	seed(29)
	var expected := randi()
	seed(29)
	for el: int in SpellLook.Element.values():
		hosts[el] = _host()
		ImpactsScript.release(hosts[el], Vector3(0, 0.08, 0), TARGETS, el, 40 + el, 2)
	assert_int(randi()).is_equal(expected)
	await get_tree().create_timer(0.5).timeout
	for el: int in hosts:
		assert_int((hosts[el] as Node3D).get_child_count()).override_failure_message("element %d drew nothing" % el) \
			.is_greater(0)
	await get_tree().create_timer(2.6).timeout
	for el: int in hosts:
		assert_int((hosts[el] as Node3D).get_child_count()).override_failure_message("element %d left nodes" % el) \
			.is_equal(0)


func test_frost_grows_prisms_and_shadow_closes_a_vortex_at_the_target(timeout := 5000) -> void:
	var frost := _host()
	var shadow := _host()
	ImpactsScript.release(frost, Vector3.ZERO, [TARGETS[0]], SpellLook.Element.FROST, 3, 2)
	ImpactsScript.release(shadow, Vector3.ZERO, [TARGETS[0]], SpellLook.Element.SHADOW, 3, 2)
	await get_tree().create_timer(0.45).timeout
	var ice := frost.find_child("IcePrisms", true, false) as Node3D
	var vortex := shadow.find_child("ShadowVortex", true, false) as Node3D
	assert_object(ice).is_not_null()
	assert_object(vortex).is_not_null()
	assert_float(Vector2(ice.global_position.x, ice.global_position.z).distance_to(Vector2(0.2, 0.1))).is_less(1e-4)
	assert_float(Vector2(vortex.global_position.x, vortex.global_position.z).distance_to(Vector2(0.2, 0.1))).is_less(1e-4)
