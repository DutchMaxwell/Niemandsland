extends GdUnitTestSuite
## aifix_all default ON for the HAND-planner presets (measured NOT_WORSE, 07.10.) and with the shipped brain wired
## (T2a NOT_WORSE on Erlkoenig, 08.10.2026); the six planner statics follow the preset per pick and ride the header the live core reads.


func after_test() -> void:
	OS.unset_environment("NML_AIFIX")
	OS.unset_environment("NML_EVAL_VARIANT")
	BattleSim._core_env = -1
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


## A solo controller that reads as "core wanted + loaded + brain accepted" without a real GDExtension.
func _brain_wired_solo() -> SoloController:
	var solo: SoloController = auto_free(SoloController.new())
	BattleSim._core_env = 1
	solo._core_node = auto_free(Node.new())
	solo.shipped_brain_sha = "test"
	assert_bool(solo.shipped_brain_ready()).is_true()
	return solo


func test_brain_wired_planner_v0_stamps_the_measured_aifix_all_preset() -> void:
	var solo := _brain_wired_solo()
	var diff := SoloDifficulty.for_grade("planner_v0")
	assert_bool(solo._aifix_on(diff)).is_true()
	solo._apply_aifix(diff)
	# KNOB_PRESETS["aifix_all"]: opener_by_finish, no_end_threat, morale_by_probability, eval_variant 4,
	# reply_v2, reply_skip_activated, reply_hold_gate
	assert_bool(AiPlanner.opener_by_finish).is_true()
	assert_bool(AiPlanner.no_end_threat).is_true()
	assert_bool(BattleSim.morale_by_probability).is_true()
	assert_bool(BattleSim.reply_v2).is_true()
	assert_bool(BattleSim.reply_skip_activated).is_true()
	assert_bool(BattleSim.reply_hold_gate).is_true()
	assert_int(solo._eval_variant_for(diff)).is_equal(4)


func test_brain_wired_variant_is_4_only_with_aifix() -> void:
	var solo := _brain_wired_solo()
	assert_int(solo._eval_variant_for(SoloDifficulty.for_grade("planner_v0"))).is_equal(4)
	var no_aifix := SoloDifficulty.for_grade("planner_v0")
	no_aifix.aifix = false
	assert_int(solo._eval_variant_for(no_aifix)).is_equal(0)   # the net stays on arm 0 (D100)
	assert_int(solo._eval_variant_for(SoloDifficulty.for_grade("nachtmahr"))).is_equal(0)
	OS.set_environment("NML_AIFIX", "0")
	assert_bool(solo._aifix_on(SoloDifficulty.for_grade("planner_v0"))).is_false()
	assert_int(solo._eval_variant_for(SoloDifficulty.for_grade("planner_v0"))).is_equal(0)
	OS.set_environment("NML_EVAL_VARIANT", "2")
	OS.set_environment("NML_AIFIX", "1")
	assert_int(solo._eval_variant_for(SoloDifficulty.for_grade("planner_v0"))).is_equal(2)   # env override first
