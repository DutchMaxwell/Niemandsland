extends GdUnitTestSuite
## Tests for OPRArmyManager round bookkeeping: advance_round() does the standard
## OPR round transition (every unit may activate again, casters regain per-round
## points capped at 6), set_current_round() clamps, clear_all() resets to 1.
## Pure logic - no scene tree needed.


func _mgr() -> OPRArmyManager:
	# Not in the tree, so _ready() (HTTPRequest + registry) is skipped.
	return auto_free(OPRArmyManager.new())


func _caster_unit() -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_properties = {"special_rules": ["Caster(2)"]}
	unit.initialize_caster_points()  # casts_per_round = 2, casts_current = 2
	return unit


func test_advance_round_increments_and_resets_activation() -> void:
	var mgr := _mgr()
	var unit := GameUnit.new()
	unit.is_activated = true
	mgr.game_units["u1"] = unit

	assert_int(mgr.current_round).is_equal(1)
	mgr.advance_round()
	assert_int(mgr.current_round).is_equal(2)
	assert_bool(unit.is_activated).is_false()


func test_advance_round_accumulates_caster_points_capped() -> void:
	var mgr := _mgr()
	var caster := _caster_unit()
	caster.casts_current = 0  # spent everything last round
	mgr.game_units["c1"] = caster

	mgr.advance_round()
	assert_int(caster.casts_current).is_equal(2)  # +2 per round

	caster.casts_current = 5
	mgr.advance_round()
	assert_int(caster.casts_current).is_equal(6)  # 5 + 2 capped at 6


func test_set_current_round_clamps_to_minimum_one() -> void:
	var mgr := _mgr()
	mgr.set_current_round(4)
	assert_int(mgr.current_round).is_equal(4)
	mgr.set_current_round(0)
	assert_int(mgr.current_round).is_equal(1)
	mgr.set_current_round(-3)
	assert_int(mgr.current_round).is_equal(1)


func test_clear_all_resets_round() -> void:
	var mgr := _mgr()
	mgr.advance_round()
	mgr.advance_round()
	assert_int(mgr.current_round).is_equal(3)

	mgr.clear_all()
	assert_int(mgr.current_round).is_equal(1)
