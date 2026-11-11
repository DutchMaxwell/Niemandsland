extends GdUnitTestSuite
## Rules 3.6 row BG-03c: from EPOCH_73_V36 a ruin is Unstable, so the AI prices a leg longer than
## 6" through it as Dangerous ground (6x) while a shorter leg keeps it as open ground. Below 73 the
## planner's route pricing is unchanged.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


func _ruin_grid() -> Dictionary:
	return {Vector2i(1, 0): TerrainRules.TerrainType.RUINS}


func test_long_leg_through_a_ruin_costs_25_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var c := MovementPlanner._segment_cost(Vector2(0.0, 1.5), Vector2(10.0, 1.5), _ruin_grid(), {})
	assert_float(c).is_equal_approx(25.0, 1e-6)


func test_long_leg_through_a_ruin_costs_10_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var c := MovementPlanner._segment_cost(Vector2(0.0, 1.5), Vector2(10.0, 1.5), _ruin_grid(), {})
	assert_float(c).is_equal_approx(10.0, 1e-6)


func test_short_leg_through_a_ruin_costs_4_at_both_epochs() -> void:
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		AiActRecorder.rules_epoch = epoch
		var c := MovementPlanner._segment_cost(Vector2(3.5, 1.5), Vector2(7.5, 1.5), _ruin_grid(), {})
		assert_float(c).is_equal_approx(4.0, 1e-6)


func test_point_wise_ruin_cost_stays_open_ground_at_both_epochs() -> void:
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		AiActRecorder.rules_epoch = epoch
		var c := MovementPlanner._terrain_cost_at(Vector2(4.5, 1.5), _ruin_grid(), {})
		assert_float(c).is_equal_approx(1.0, 1e-6)
