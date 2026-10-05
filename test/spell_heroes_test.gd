extends GdUnitTestSuite
## SpellHeroes: chain lightning runs caster -> target -> target as thin bolts (seven segments a hop, 0.75 mm, the
## shared FxBolt), leaves the game's RNG alone and cleans up; a meteor falls onto its target, calls its impact exactly
## once and cleans up.

const HeroesScript = preload("res://scripts/vfx/spell_heroes.gd")


func _host() -> Node3D:
	var n := auto_free(Node3D.new()) as Node3D
	add_child(n)
	return n


func test_chain_lightning_hops_target_to_target_thin_and_cleans_up(timeout := 5000) -> void:
	var h := _host()
	var targets := [Vector3(0.2, 0.04, 0.1), Vector3(0.26, 0.04, 0.2)]
	seed(13)
	var expected := randi()
	seed(13)
	HeroesScript.chain_lightning(h, Vector3(0, 0.08, 0), targets, 21, 2)
	await get_tree().process_frame
	var bolt := h.get_child(0) as Node3D
	assert_int(bolt.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()) \
		.override_failure_message("seven segments for each hop").is_equal(7 * targets.size())
	assert_float((bolt.get_child(0) as Node3D).global_transform.basis.x.length()).is_equal_approx(0.00075, 1e-6)
	assert_int(randi()).is_equal(expected)
	await get_tree().create_timer(1.6).timeout
	assert_int(h.get_child_count()).is_equal(0)


func test_a_meteor_lands_once_and_cleans_up(timeout := 5000) -> void:
	var h := _host()
	var hits := [0]
	seed(17)
	var expected := randi()
	seed(17)
	HeroesScript.meteor(h, Vector3(0.2, 0.03, 0.1), 5, 2, func() -> void: hits[0] += 1)
	assert_int(randi()).is_equal(expected)
	await get_tree().create_timer(0.6).timeout
	assert_int(hits[0]).override_failure_message("the impact fires once").is_equal(1)
	await get_tree().create_timer(1.8).timeout
	assert_int(h.get_child_count()).is_equal(0)
