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


## A keyword-less big single model (Tough >= 6) is treated as a VEHICLE → OVAL base.
func test_fallback_bracketless_vehicle_is_oval() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.name = "Battle Tank"  # no walker/artillery/monster keyword → vehicle
	unit.size = 1
	unit.special_rules = ["Tough(12)"]
	unit.base_size_round = 32  # default (no recommendation)
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_bool(unit.base_is_oval).is_true()
	assert_int(unit.base_width_mm).is_equal(92)   # short axis
	assert_int(unit.base_depth_mm).is_equal(120)  # long / facing axis
	assert_int(unit.base_size_round).is_equal(120)


## A walker grows MODESTLY and stays ROUND, starting small (T6→50, T9→60, T12→80).
func test_fallback_walker_round_bands() -> void:
	for band in [[6, 50], [9, 60], [12, 80]]:
		var unit := OPRApiClient.OPRUnit.new()
		unit.name = "Assault Walker"
		unit.size = 1
		unit.special_rules = ["Tough(%d)" % band[0]]
		unit.base_size_round = 32
		OPRApiClient._apply_tough_base_fallback(unit)
		assert_bool(unit.base_is_oval).is_false()
		assert_int(unit.base_size_round).is_equal(band[1])


## A vehicle starts at 90×52 (T6) and scales up.
func test_fallback_vehicle_oval_bands() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.name = "Recon Buggy"
	unit.size = 1
	unit.special_rules = ["Tough(6)"]
	unit.base_size_round = 32
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_bool(unit.base_is_oval).is_true()
	assert_int(unit.base_width_mm).is_equal(52)
	assert_int(unit.base_depth_mm).is_equal(90)


## Artillery is OVAL but smaller/capped vs a vehicle.
func test_fallback_artillery_oval_capped() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.name = "Heavy Cannon"
	unit.size = 1
	unit.special_rules = ["Tough(9)"]
	unit.base_size_round = 32
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_bool(unit.base_is_oval).is_true()
	assert_int(unit.base_width_mm).is_equal(52)
	assert_int(unit.base_depth_mm).is_equal(90)  # capped (a vehicle T9 would be 105x70)


## A monster (creature keyword) is ROUND, using the walker ladder.
func test_fallback_monster_is_round() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.name = "Great Dragon"
	unit.size = 1
	unit.special_rules = ["Tough(12)"]
	unit.base_size_round = 32
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_bool(unit.base_is_oval).is_false()
	assert_int(unit.base_size_round).is_equal(80)  # walker ladder: T12 → 80


func test_fallback_never_shrinks_real_base() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.name = "Recon Buggy"
	unit.size = 1
	unit.special_rules = ["Tough(6)"]
	unit.base_size_round = 150  # a real, larger recommendation than the T6 vehicle oval (90)
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_int(unit.base_size_round).is_equal(150)


## A multi-model unit is never a vehicle — large infantry / cavalry stay round on the old ladder.
func test_fallback_multimodel_stays_round_infantry() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	unit.name = "Heavy Cavalry"
	unit.size = 5
	unit.special_rules = ["Tough(3)"]
	unit.base_size_round = 32
	OPRApiClient._apply_tough_base_fallback(unit)
	assert_bool(unit.base_is_oval).is_false()
	assert_int(unit.base_size_round).is_equal(40)


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
