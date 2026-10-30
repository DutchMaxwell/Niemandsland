extends GdUnitTestSuite
## Rules 3.6 wave, row W1.2: the table's recorder stamps the wave's one rules epoch, 73 (the core's
## frozen EPOCH_73_V36 in acts.rs), so every recording and save made from here on carries it. The
## play-test fixes' mirror keeps its own frozen gate at 72, the leg below the bump.


func test_the_recorder_stamps_the_rules_3_6_wave_at_epoch_73() -> void:
	assert_int(AiActRecorder.rules_epoch) \
		.override_failure_message("the recorder must stamp the rules 3.6 epoch, 73, not %d" % AiActRecorder.rules_epoch) \
		.is_equal(73)


func test_the_play_test_fixes_mirror_stays_frozen_at_epoch_72() -> void:
	assert_int(AiActRecorder.EPOCH_72_PLAYTEST_RULES).is_equal(72)
