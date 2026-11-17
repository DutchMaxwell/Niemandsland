extends GdUnitTestSuite

## Ship path (22.09., P4.D-68): BattleSim.core_wanted - EVERY build asks for the Rust core
## unless NML_CORE=0. Release builds since 22.09. (before, the release path never asked for the
## core at all, so the measured Erlkönig and the shipped opponent could not be the same planner);
## debug builds and the test binary since P4.D-68, so the tests play the shipped path.


func test_release_build_wants_the_core_by_default() -> void:
	assert_bool(BattleSim.core_wanted("", false)).is_true()


func test_debug_build_wants_the_core_by_default_too() -> void:
	assert_bool(BattleSim.core_wanted("", true)).is_true()
	assert_bool(BattleSim.core_wanted("1", true)).is_true()


func test_explicit_values_win_in_both_builds() -> void:
	assert_bool(BattleSim.core_wanted("0", false)).is_false()
	assert_bool(BattleSim.core_wanted("1", false)).is_true()
	assert_bool(BattleSim.core_wanted("0", true)).is_false()
	# Anything else is not a switch: "yes", "true", "2" do not ask for the core.
	assert_bool(BattleSim.core_wanted("yes", false)).is_false()
	assert_bool(BattleSim.core_wanted("true", true)).is_false()
