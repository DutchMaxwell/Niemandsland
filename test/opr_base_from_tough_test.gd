extends GdUnitTestSuite
## Tests the Tough-based base-size fallback used when Army Forge gives no base
## recommendation (vehicles / large monsters), so 3D models still scale sensibly.


func test_base_size_bands() -> void:
	assert_int(OPRApiClient._base_size_from_tough(0)).is_equal(0)
	assert_int(OPRApiClient._base_size_from_tough(2)).is_equal(0)
	assert_int(OPRApiClient._base_size_from_tough(3)).is_equal(40)
	assert_int(OPRApiClient._base_size_from_tough(5)).is_equal(40)
	assert_int(OPRApiClient._base_size_from_tough(6)).is_equal(60)
	assert_int(OPRApiClient._base_size_from_tough(9)).is_equal(80)
	assert_int(OPRApiClient._base_size_from_tough(11)).is_equal(80)
	assert_int(OPRApiClient._base_size_from_tough(12)).is_equal(120)
	assert_int(OPRApiClient._base_size_from_tough(17)).is_equal(120)
	assert_int(OPRApiClient._base_size_from_tough(18)).is_equal(150)


func test_tough_parsing() -> void:
	assert_int(OPRApiClient._tough_from_rules(["Fearless", "Tough(6)"])).is_equal(6)
	assert_int(OPRApiClient._tough_from_rules(["Fast"])).is_equal(0)


func test_fallback_enlarges_bracketless_vehicle() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.special_rules = ["Tough(12)"]
	unit.base_size_round = 32  # default (no recommendation)
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_int(unit.base_size_round).is_equal(120)
	assert_int(unit.base_width_mm).is_equal(120)
	assert_int(unit.base_depth_mm).is_equal(120)


func test_fallback_never_shrinks_real_base() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.special_rules = ["Tough(6)"]
	unit.base_size_round = 80  # a real, larger recommendation
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_int(unit.base_size_round).is_equal(80)


func test_fallback_leaves_normal_infantry() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.base_size_round = 25
	OPRApiClient._apply_tough_base_fallback(unit)  # no Tough -> no change
	assert_int(unit.base_size_round).is_equal(25)


func test_usable_base_value() -> void:
	# Army Forge sends "none" for models without a recommendation -> not usable.
	assert_bool(OPRApiClient._is_usable_base_value("none")).is_false()
	assert_bool(OPRApiClient._is_usable_base_value("None")).is_false()
	assert_bool(OPRApiClient._is_usable_base_value("")).is_false()
	assert_bool(OPRApiClient._is_usable_base_value("0")).is_false()
	assert_bool(OPRApiClient._is_usable_base_value(0)).is_false()
	# Real recommendations are usable.
	assert_bool(OPRApiClient._is_usable_base_value("32")).is_true()
	assert_bool(OPRApiClient._is_usable_base_value("120x92")).is_true()
	assert_bool(OPRApiClient._is_usable_base_value(60)).is_true()
