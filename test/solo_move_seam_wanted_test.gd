extends GdUnitTestSuite

## S7 (22.09.): SoloController.move_seam_wanted — a RELEASE build routes movement planning through
## the Rust core unless NML_CORE_MOVE=0; a debug build keeps the explicit NML_CORE_MOVE=1 so every
## measurement and the test default path stay deliberate. Gate that made it a default: 2,532
## plan_unit_step self-checks over 40 games, both grades, 0 disagreements (22.09.).


func test_release_build_wants_the_core_move_planner_by_default() -> void:
	assert_bool(SoloController.move_seam_wanted("", false)).is_true()


func test_debug_build_keeps_the_explicit_switch() -> void:
	assert_bool(SoloController.move_seam_wanted("", true)).is_false()
	assert_bool(SoloController.move_seam_wanted("1", true)).is_true()


func test_explicit_values_win_and_junk_is_not_a_switch() -> void:
	assert_bool(SoloController.move_seam_wanted("0", false)).is_false()
	assert_bool(SoloController.move_seam_wanted("1", false)).is_true()
	assert_bool(SoloController.move_seam_wanted("yes", false)).is_false()
	assert_bool(SoloController.move_seam_wanted("true", true)).is_false()
