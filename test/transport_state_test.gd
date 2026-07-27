extends GdUnitTestSuite
## Transport(X) capacity core (NML-105 S1) — the GF v3.5.1 wording + its printed example, verbatim:
## "a unit of 10 regular models with a Tough(3) Hero occupy 11 spaces in total."


func test_spaces_follow_the_book_example() -> void:
	# Regular models and Heroes with Tough(3) or Tough(6) occupy 1 space.
	assert_int(TransportState.spaces_of(false, 0)).is_equal(1)   # regular model
	assert_int(TransportState.spaces_of(false, 1)).is_equal(1)   # 1-wound profile
	assert_int(TransportState.spaces_of(true, 3)).is_equal(1)    # Tough(3) Hero
	assert_int(TransportState.spaces_of(true, 6)).is_equal(1)    # Tough(6) Hero
	# Tough(3) (non-hero) models occupy 3 spaces.
	assert_int(TransportState.spaces_of(false, 3)).is_equal(3)
	# Tough(6) or higher can't be transported (non-hero); heroes above Tough(6) neither.
	assert_int(TransportState.spaces_of(false, 6)).is_equal(TransportState.UNTRANSPORTABLE)
	assert_int(TransportState.spaces_of(false, 12)).is_equal(TransportState.UNTRANSPORTABLE)
	assert_int(TransportState.spaces_of(true, 7)).is_equal(TransportState.UNTRANSPORTABLE)


func test_book_example_unit_occupies_11_spaces() -> void:
	var unit: Array = []
	for i in range(10):
		unit.append({"hero": false, "tough": 0})
	unit.append({"hero": true, "tough": 3})
	assert_int(TransportState.spaces_of_models(unit)).is_equal(11)
	# ... which exactly fills the Brothers APC Transport(11).
	assert_bool(TransportState.fits(unit, 11)).is_true()
	assert_bool(TransportState.fits(unit, 11, 1)).is_false()   # one space already taken
	assert_bool(TransportState.fits(unit, 6)).is_false()


func test_one_untransportable_model_keeps_the_whole_unit_out() -> void:
	var unit: Array = [{"hero": false, "tough": 0}, {"hero": false, "tough": 6}]
	assert_int(TransportState.spaces_of_models(unit)).is_equal(TransportState.UNTRANSPORTABLE)
	assert_bool(TransportState.fits(unit, 99)).is_false()


func test_rule_string_parsing_both_shapes() -> void:
	assert_int(TransportState.capacity_of_rules(["Fear", "Transport(11)"])).is_equal(11)
	assert_int(TransportState.capacity_of_rules([{"name": "Transport(6)"}])).is_equal(6)
	assert_int(TransportState.capacity_of_rules(["Fast"])).is_equal(0)
	assert_int(TransportState.tough_of_rules(["Tough(3)", "Fearless"])).is_equal(3)
	assert_int(TransportState.tough_of_rules([{"name": "Tough(12)"}])).is_equal(12)
	assert_int(TransportState.tough_of_rules(["Hero"])).is_equal(0)
