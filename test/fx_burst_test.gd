extends GdUnitTestSuite
## FxBurst (combat effects): a burst of billboard particles is budgeted per quality (Performance none, Low half), its
## particles are a pure function of the cue's seed (the same burst on every peer), it never touches the game's RNG,
## and it frees itself when its life is over.

const BurstScript = preload("res://scripts/vfx/fx_burst.gd")


func _host() -> Node3D:
	var n := auto_free(Node3D.new()) as Node3D
	add_child(n)
	return n


func test_the_budget_follows_the_quality() -> void:
	assert_int(BurstScript.budget(12, 0)).is_equal(0)    # Performance: no show
	assert_int(BurstScript.budget(12, 1)).is_equal(6)    # Low: half
	assert_int(BurstScript.budget(12, 2)).is_equal(12)
	assert_object(BurstScript.spawn(_host(), BurstScript.Look.SPARK, Vector3.ZERO, Vector3.UP, 12, 5, 0)).is_null()


func test_the_same_seed_draws_the_same_burst() -> void:
	var a: Array = BurstScript.instances(BurstScript.Look.DUST, Vector3.UP, 10, 77)
	assert_array(a).is_equal(BurstScript.instances(BurstScript.Look.DUST, Vector3.UP, 10, 77))
	assert_array(a).is_not_equal(BurstScript.instances(BurstScript.Look.DUST, Vector3.UP, 10, 78))
	assert_float(((a[0] as Array)[1] as Color).g).override_failure_message("thrown upwards").is_greater(0.0)


func test_bursts_leave_the_game_rng_alone() -> void:
	var h := _host()
	seed(31)
	var expected := randi()
	seed(31)
	for look in BurstScript.Look.values():
		BurstScript.spawn(h, look, Vector3.ZERO, Vector3.UP, 16, 9, 4)
	assert_int(randi()).is_equal(expected)


func test_a_burst_frees_itself_after_its_life(timeout := 5000) -> void:
	var h := _host()
	BurstScript.spawn(h, BurstScript.Look.SPARK, Vector3.ZERO, Vector3.UP, 8, 3, 2)
	assert_int(h.get_child_count()).is_equal(1)
	await get_tree().create_timer(BurstScript.LOOKS[BurstScript.Look.SPARK][7] + 0.3).timeout
	assert_int(h.get_child_count()).is_equal(0)
