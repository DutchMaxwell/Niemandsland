extends GdUnitTestSuite
## The difficulty-ladder picker's model (grill 25.09.2026 Q4-Q6, NML-1018 step 2): a pick is saved and
## remembered after a downshift, every grade carries one line of description (NACHTMAHR "coming", the
## macOS Albtraum honest about the missing Erlkönig), and only a solo player or the host picks.

const CFG := "user://test_solo_grade_picker.cfg"


func before_test() -> void:
	ProjectSettings.set_setting(SoloGrade.CFG_OVERRIDE_SETTING, CFG)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func after_test() -> void:
	ProjectSettings.set_setting(SoloGrade.CFG_OVERRIDE_SETTING, "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func test_a_pick_is_saved_and_the_reserved_grade_is_refused() -> void:
	SoloGrade.save("zwielicht")
	assert_str(SoloGrade.load_saved()).is_equal("zwielicht")
	SoloGrade.save("nachtmahr")
	assert_str(SoloGrade.load_saved()).override_failure_message("the reserved grade overwrote the choice").is_equal("zwielicht")
	SoloGrade.save("daemmerung")
	assert_str(SoloGrade.load_saved()).is_equal("daemmerung")


func test_every_grade_has_a_one_line_description() -> void:
	assert_str(SoloGrade.description("daemmerung", false)).is_equal("still learning; makes visible mistakes")
	assert_str(SoloGrade.description("zwielicht", false)).is_equal("plays solidly, misses some chances")
	assert_str(SoloGrade.description("finsternis", false)).is_equal("plays the rules hard and punishes mistakes")
	assert_str(SoloGrade.description("albtraum", false)).is_equal("Erlkönig: thinks several moves ahead")
	assert_str(SoloGrade.description("nachtmahr", false)).is_equal("coming")
	for g in SoloGrade.GRADES:
		assert_str(SoloGrade.description(g, true)).override_failure_message("%s has no description" % g).is_not_empty()
		assert_bool(SoloGrade.description(g, true).contains("\n")).is_false()


func test_macos_albtraum_says_it_plays_without_erlkoenig() -> void:
	assert_str(SoloGrade.description("albtraum", true)).contains("on macOS still without Erlkönig")
	assert_str(SoloGrade.description("finsternis", true)).is_equal(SoloGrade.description("finsternis", false))


func test_only_a_solo_player_or_the_host_picks_the_grade() -> void:
	assert_bool(SoloGrade.picker_visible(false, false)).is_true()   # solo, no room
	assert_bool(SoloGrade.picker_visible(true, true)).is_true()     # co-op host
	assert_bool(SoloGrade.picker_visible(true, false)).is_false()   # co-op guest
