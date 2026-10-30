extends GdUnitTestSuite
## Rules 3.6 wave, row W1.2: the table's recorder stamps the wave's one rules epoch, 73 (the core's
## frozen EPOCH_73_V36 in acts.rs), so every recording and save made from here on carries it. The
## play-test fixes' mirror keeps its own frozen gate at 72, the leg below the bump.


func test_the_recorder_stamps_the_rules_3_6_wave_at_epoch_73() -> void:
	assert_int(AiActRecorder.rules_epoch) \
		.override_failure_message("the recorder must stamp the rules 3.6 epoch, 73, not %d" % AiActRecorder.rules_epoch) \
		.is_equal(73)


## Every later 3.6 row gates its GDScript twin on the mirror constant, so it must exist and be the live
## stamp. Read through the constant map, so a missing constant fails on the assertion, not on parsing.
func test_the_rules_3_6_mirror_constant_is_the_live_stamp_at_epoch_73() -> void:
	var recorder: Script = load("res://scripts/solo/act_recorder.gd")
	var consts := recorder.get_script_constant_map()
	assert_int(int(consts.get("EPOCH_73_V36", -1))) \
		.override_failure_message("AiActRecorder has no EPOCH_73_V36 = 73 mirror") \
		.is_equal(73)
	assert_int(AiActRecorder.rules_epoch).is_equal(int(consts.get("EPOCH_73_V36", -1)))


func test_the_play_test_fixes_mirror_stays_frozen_at_epoch_72() -> void:
	assert_int(AiActRecorder.EPOCH_72_PLAYTEST_RULES).is_equal(72)
