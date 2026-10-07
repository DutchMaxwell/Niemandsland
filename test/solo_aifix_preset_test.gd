extends GdUnitTestSuite
## aifix_all default ON for the HAND-planner presets (measured NOT_WORSE, 07.10.), OFF whenever the shipped brain is
## wired; the six planner statics follow the preset per pick and ride the header the live core reads.


func after_test() -> void:
	OS.unset_environment("NML_AIFIX")
	AiPlanner.opener_by_finish = false
	AiPlanner.no_end_threat = false
	BattleSim.morale_by_probability = false
	BattleSim.reply_v2 = false
	BattleSim.reply_skip_activated = false
	BattleSim.reply_hold_gate = false


func test_the_hand_planner_presets_carry_aifix_and_the_net_presets_do_not() -> void:
	for name in ["planner_v0", "planner_v0s", "planner_v0_herofold", "planner_v0_pool1", "planner_v0_both"]:
		assert_bool(SoloDifficulty.for_grade(name).aifix).is_true()
	for name in ["nachtmahr", "planner_v1", "planner_v2"]:
		assert_bool(SoloDifficulty.for_grade(name).aifix).is_false()


func test_a_hand_pick_stamps_the_bundle_and_variant_4() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	var diff := SoloDifficulty.for_grade("planner_v0")
	solo._apply_aifix(diff)
	assert_bool(AiPlanner.opener_by_finish).is_true()
	assert_bool(AiPlanner.no_end_threat).is_true()
	assert_bool(BattleSim.morale_by_probability).is_true()
	assert_bool(BattleSim.reply_v2).is_true()
	assert_bool(BattleSim.reply_skip_activated).is_true()
	assert_bool(BattleSim.reply_hold_gate).is_true()
	assert_int(solo._eval_variant_for(diff)).is_equal(4)   # preset 3 composes into 4


func test_a_preset_without_aifix_stamps_nothing_and_keeps_variant_3() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	var diff := SoloDifficulty.for_grade("planner_v0")
	diff.aifix = false
	solo._apply_aifix(diff)
	assert_bool(BattleSim.reply_v2).is_false()
	assert_int(solo._eval_variant_for(diff)).is_equal(3)


func test_the_env_switch_forces_the_bundle_either_way() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	OS.set_environment("NML_AIFIX", "0")
	assert_bool(solo._aifix_on(SoloDifficulty.for_grade("planner_v0"))).is_false()
	OS.set_environment("NML_AIFIX", "1")
	assert_bool(solo._aifix_on(SoloDifficulty.for_grade("nachtmahr"))).is_true()
