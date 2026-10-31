extends GdUnitTestSuite
## Rules 3.6 row MOR-19b: Ethereal's place-within-6" is optional and the -6" band penalty
## applies only while the model was placed this activation. Below EPOCH_73_V36 the bands keep
## today's always-on -6/-6. The core twin is core/nml-core/src/tests/unit/v36_mor_19b.rs.

const CONTROLLER := preload("res://scripts/movement_range_controller.gd")

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _props(placed: bool) -> Dictionary:
	return {
		"name": "Ghost",
		"game_system": "aof",
		"faction_folder": "ghostly_undead",
		"special_rules": ["Ethereal"],
		"teleport_used_this_activation": placed,
	}


func test_ethereal_keeps_full_bands_before_placement_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bands: Dictionary = CONTROLLER.move_bands_for_props(_props(false))
	assert_int(bands["advance"]).is_equal(6)
	assert_int(bands["rush"]).is_equal(12)


func test_ethereal_takes_the_minus_six_after_placement_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bands: Dictionary = CONTROLLER.move_bands_for_props(_props(true))
	assert_int(bands["advance"]).is_equal(0)
	assert_int(bands["rush"]).is_equal(6)


func test_ethereal_keeps_the_minus_six_unplaced_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var bands: Dictionary = CONTROLLER.move_bands_for_props(_props(false))
	assert_int(bands["advance"]).is_equal(0)
	assert_int(bands["rush"]).is_equal(6)
