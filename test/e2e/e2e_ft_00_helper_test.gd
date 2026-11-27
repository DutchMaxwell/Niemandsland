extends GdUnitTestSuite
## Feature tests FT-0: the skirmish feature-test facade (test/support/skirmish_table.gd) itself. A booted hot-seat table
## holds a gff unit and an aofs unit with their system on the table and live; a pending epoch pinned through the facade
## is recorded and the table runs at it; teardown brings the shipped epoch back.
## Real: the main scene, its army manager, the battle log tap.

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func test_both_systems_stand_on_the_table() -> void:
	var a := _t.unit("gff", 1, "Rangers", 3, 1, 0.0, 0.0)
	var b := _t.unit("aofs", 2, "Wardens", 2, 3, 12.0, 0.0)
	var units: Dictionary = _t.main.opr_army_manager.game_units
	assert_bool(units.has(a.unit_id) and units.has(b.unit_id)).override_failure_message("both units on the table").is_true()
	assert_str(str(a.unit_properties["game_system"])).is_equal("gff")
	assert_str(str(b.unit_properties["game_system"])).is_equal("aofs")
	assert_int(a.models.size()).is_equal(3)
	assert_int((b.models[1] as ModelInstance).wounds_max).is_equal(3)
	var gap: float = (a.models[0] as ModelInstance).node.global_position.distance_to((b.models[0] as ModelInstance).node.global_position)
	assert_float(gap / SkirmishTable.INCH).override_failure_message("placed 12 in apart").is_equal_approx(12.0, 0.01)


func test_a_pinned_epoch_is_recorded_and_restored() -> void:
	var shipped := AiActRecorder.rules_epoch
	_t.need_epoch(106)
	assert_int(AiActRecorder.rules_epoch).override_failure_message("the table runs at the pin").is_equal(106)
	assert_bool(SkirmishTable.pins.has(106)).override_failure_message("the pin is on record").is_true()
	_t.teardown()
	_t = null
	assert_int(AiActRecorder.rules_epoch).override_failure_message("teardown restores the shipped epoch").is_equal(shipped)
