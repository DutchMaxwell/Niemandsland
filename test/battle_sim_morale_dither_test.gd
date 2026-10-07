extends GdUnitTestSuite
## aifix D1 twin: the GDScript morale dither is the core's `morale_dither` (sim.rs), and it is a fair die.


func test_the_dither_matches_the_core_constant() -> void:
	# sim.rs: morale_dither(0, 1) = (0.6180339887498949 + 0.7548776662466927).fract()
	assert_float(BattleSim._morale_dither(0, 1)).is_equal_approx(0.3729116549965876, 1e-12)


func test_the_dither_breaks_each_quality_at_its_own_rate() -> void:
	for want in [1.0 / 3.0, 0.5, 2.0 / 3.0]:
		var hits := 0
		for r in range(1, 301):
			if want > BattleSim._morale_dither(0, r):
				hits += 1
		assert_float(float(hits) / 300.0).is_equal_approx(want, 0.05)
