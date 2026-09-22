extends GdUnitTestSuite

## Ship path (22.09.): BattleSim.core_wanted — a RELEASE build asks for the Rust core
## unless NML_CORE=0; a debug build keeps the explicit NML_CORE=1 so every measurement
## and every test default stays a deliberate switch. Before this the release path never
## asked for the core at all (battle_sim.gd "DEFAULT OFF"), so the measured Erlkönig and
## the shipped opponent could not be the same planner.


func test_release_build_wants_the_core_by_default() -> void:
	assert_bool(BattleSim.core_wanted("", false)).is_true()


func test_debug_build_keeps_the_explicit_switch() -> void:
	assert_bool(BattleSim.core_wanted("", true)).is_false()
	assert_bool(BattleSim.core_wanted("1", true)).is_true()


func test_explicit_values_win_in_both_builds() -> void:
	assert_bool(BattleSim.core_wanted("0", false)).is_false()
	assert_bool(BattleSim.core_wanted("1", false)).is_true()
	assert_bool(BattleSim.core_wanted("0", true)).is_false()
	# Anything else is not a switch: "yes", "true", "2" leave the default path alone.
	assert_bool(BattleSim.core_wanted("yes", false)).is_false()
	assert_bool(BattleSim.core_wanted("true", true)).is_false()
