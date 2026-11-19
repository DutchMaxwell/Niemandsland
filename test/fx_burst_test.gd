extends GdUnitTestSuite
## FxBurst (combat effects): a burst of billboard particles is budgeted per quality (Performance none, Low half), its
## particles are a pure function of the cue's seed (the same burst on every peer), it never touches the game's RNG,
## and it frees itself when its life is over.

const BurstScript = preload("res://scripts/vfx/fx_burst.gd")
var _motion_before: bool


func before_test() -> void:
	_motion_before = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = false


func after_test() -> void:
	GraphicsSettings.reduce_motion = _motion_before


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


func test_channel_atlas_is_256_rgba_with_four_distinct_channels_and_no_rng_drift() -> void:
	seed(919)
	var expected := randi()
	seed(919)
	var tex: ImageTexture = BurstScript.channel_atlas()
	assert_object(tex).is_not_null()
	assert_object(BurstScript.channel_atlas()).override_failure_message("cached atlas reused").is_same(tex)
	assert_int(tex.get_width()).is_equal(BurstScript.ATLAS_SIZE)
	assert_int(tex.get_height()).is_equal(BurstScript.ATLAS_SIZE)
	var img := tex.get_image()
	var center := img.get_pixel(128, 128)
	var edge := img.get_pixel(4, 4)
	assert_float(center.r).is_greater(0.8)
	assert_float(center.g).is_greater(0.2)
	assert_float(center.b).is_greater(0.4)
	assert_float(center.a).is_greater(0.8)
	assert_float(edge.r + edge.g + edge.b + edge.a).is_less(0.05)
	assert_int(randi()).is_equal(expected)


func test_v3_looks_wire_stretch_bounce_smoke_drift_and_free(timeout := 5000) -> void:
	var h := _host()
	var spark: FxBurst = BurstScript.spawn(h, BurstScript.Look.SPARK, Vector3(0, 0.03, 0), Vector3.UP, 6, 11, 2)
	var chip: FxBurst = BurstScript.spawn(h, BurstScript.Look.CHIP, Vector3(0, 0.03, 0), Vector3.UP, 6, 12, 2)
	var puff: FxBurst = BurstScript.spawn(h, BurstScript.Look.PUFF, Vector3(0, 0.03, 0), Vector3.UP, 4, 13, 2)
	var smat := spark.material_override as ShaderMaterial
	var cmat := chip.material_override as ShaderMaterial
	var pmat := puff.material_override as ShaderMaterial
	assert_int(int(smat.get_shader_parameter("channel_mode"))).is_equal(BurstScript.Channel.SPARK_B)
	assert_float(float(smat.get_shader_parameter("stretch"))).is_greater(1.0)
	assert_float(float(cmat.get_shader_parameter("bounce"))).is_greater(0.2)
	assert_int(int(cmat.get_shader_parameter("channel_mode"))).is_equal(BurstScript.Channel.CLOD_A)
	assert_int(int(pmat.get_shader_parameter("channel_mode"))).is_equal(BurstScript.Channel.SMOKE_G)
	assert_float(float(pmat.get_shader_parameter("life"))).is_equal_approx(2.2, 1e-4)
	assert_float(float(pmat.get_shader_parameter("alpha_cap"))).is_less_equal(0.35)
	assert_float((pmat.get_shader_parameter("wind") as Vector3).length()).is_greater(0.001)
	await get_tree().create_timer(2.5).timeout
	assert_int(h.get_child_count()).override_failure_message("all v3 bursts freed with no orphans").is_equal(0)


func test_reduce_motion_uses_static_path_and_suppresses_flash_strobe(timeout := 5000) -> void:
	GraphicsSettings.reduce_motion = true
	var h := _host()
	assert_object(BurstScript.spawn(h, BurstScript.Look.FLASH, Vector3.ZERO, Vector3.UP, 1, 5, 2)) \
		.override_failure_message("no flash strobe under reduce motion").is_null()
	var puff: FxBurst = BurstScript.spawn(h, BurstScript.Look.PUFF, Vector3.ZERO, Vector3.UP, 4, 6, 2)
	assert_object(puff).is_not_null()
	var mat := puff.material_override as ShaderMaterial
	assert_float(float(mat.get_shader_parameter("static_mode"))).is_equal_approx(1.0, 1e-5)
	assert_float(float(mat.get_shader_parameter("life"))).is_equal_approx(BurstScript.REDUCED_LIFE_S, 1e-5)
	await get_tree().create_timer(BurstScript.REDUCED_LIFE_S + 0.25).timeout
	assert_int(h.get_child_count()).override_failure_message("static reduced-motion burst freed cleanly").is_equal(0)
