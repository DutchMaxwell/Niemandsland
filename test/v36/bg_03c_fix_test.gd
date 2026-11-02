extends GdUnitTestSuite
## Rules 3.6 row BG-03c-fix (audit A): the GDScript planner must price a long leg through ruin
## ground exactly like the Rust core. The long-ruin Dangerous price outranks the Difficult debuff,
## a Dangerous cell outranks it too, and a Flying unit is exempt from the ruin price. Epoch 72
## keeps today's numbers and its old multiplier order.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _ruin_grid() -> Dictionary:
	return {Vector2i(1, 0): TerrainRules.TerrainType.RUINS}


func _dangerous_grid() -> Dictionary:
	return {Vector2i(1, 0): TerrainRules.TerrainType.DANGEROUS}


func test_long_ruin_leg_with_difficult_debuff_costs_32_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var c := MovementPlanner._segment_cost(Vector2(0.0, 1.5), Vector2(10.0, 1.5), _ruin_grid(),
		{"difficult_debuff": true})
	assert_float(c).is_equal_approx(32.0, 1e-6)


func test_short_ruin_leg_keeps_the_difficult_price_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var c := MovementPlanner._segment_cost(Vector2(3.5, 1.5), Vector2(7.5, 1.5), _ruin_grid(),
		{"difficult_debuff": true})
	assert_float(c).is_equal_approx(8.0, 1e-6)


func test_dangerous_cell_with_difficult_debuff_costs_6_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var c := MovementPlanner._terrain_cost_at(Vector2(4.5, 1.5), _dangerous_grid(),
		{"difficult_debuff": true})
	assert_float(c).is_equal_approx(6.0, 1e-6)


func test_flying_unit_ignores_the_ruin_price_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var c := MovementPlanner._segment_cost(Vector2(0.0, 1.5), Vector2(10.0, 1.5), _ruin_grid(),
		{"flying": true})
	assert_float(c).is_equal_approx(10.0, 1e-6)


func test_non_flying_unit_still_pays_the_ruin_price_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var c := MovementPlanner._segment_cost(Vector2(0.0, 1.5), Vector2(10.0, 1.5), _ruin_grid(), {})
	assert_float(c).is_equal_approx(25.0, 1e-6)


func test_epoch_72_keeps_todays_numbers_and_order() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var long_leg := MovementPlanner._segment_cost(Vector2(0.0, 1.5), Vector2(10.0, 1.5),
		_ruin_grid(), {"difficult_debuff": true})
	assert_float(long_leg).is_equal_approx(20.0, 1e-6)
	var danger := MovementPlanner._terrain_cost_at(Vector2(4.5, 1.5), _dangerous_grid(),
		{"difficult_debuff": true})
	assert_float(danger).is_equal_approx(2.0, 1e-6)
