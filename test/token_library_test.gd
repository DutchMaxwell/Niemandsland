extends GdUnitTestSuite
## Tests the reusable custom-token library: define/lookup, rename rules,
## and save/load round-trip.


func test_define_and_lookup() -> void:
	var lib := TokenLibrary.new()
	lib.define("Havoc", Color(0.9, 0.1, 0.1), true, "+1 to hit per token")

	assert_bool(lib.has("Havoc")).is_true()
	assert_bool(lib.is_counter("Havoc")).is_true()
	assert_str(lib.get_effect("Havoc")).is_equal("+1 to hit per token")
	assert_float(lib.get_color("Havoc").r).is_equal_approx(0.9, 0.01)


func test_unknown_token_returns_defaults() -> void:
	var lib := TokenLibrary.new()
	assert_bool(lib.has("Nope")).is_false()
	assert_bool(lib.is_counter("Nope")).is_false()
	assert_str(lib.get_effect("Nope")).is_equal("")


func test_rename_moves_definition() -> void:
	var lib := TokenLibrary.new()
	lib.define("Havoc", Color.RED, true, "eff")
	assert_bool(lib.rename("Havoc", "Surge")).is_true()
	assert_bool(lib.has("Havoc")).is_false()
	assert_bool(lib.has("Surge")).is_true()
	assert_str(lib.get_effect("Surge")).is_equal("eff")
	assert_bool(lib.is_counter("Surge")).is_true()


func test_rename_rejects_collision_and_missing() -> void:
	var lib := TokenLibrary.new()
	lib.define("A", Color.RED, false, "")
	lib.define("B", Color.BLUE, false, "")
	assert_bool(lib.rename("A", "B")).is_false()      # target exists
	assert_bool(lib.rename("X", "Y")).is_false()      # source missing
	assert_bool(lib.rename("A", "A")).is_false()      # no-op
	assert_bool(lib.has("A")).is_true()


func test_save_load_round_trip() -> void:
	var lib := TokenLibrary.new()
	lib.define("Havoc", Color(0.2, 0.4, 0.6, 1.0), true, "resource")
	lib.define("Stealth", Color(0.1, 0.8, 0.1, 1.0), false, "-1 to be hit")

	var restored := TokenLibrary.new()
	restored.from_dict(lib.to_dict())

	assert_int(restored.names().size()).is_equal(2)
	assert_bool(restored.is_counter("Havoc")).is_true()
	assert_str(restored.get_effect("Stealth")).is_equal("-1 to be hit")
	assert_float(restored.get_color("Havoc").b).is_equal_approx(0.6, 0.01)
