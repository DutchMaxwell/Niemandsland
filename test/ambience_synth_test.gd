extends GdUnitTestSuite
## Tests the procedural ambience synthesis (AmbienceSynth): formats, loop flags,
## seed determinism, peak limiting and loop-seam continuity — all headless-safe.


func _all_streams() -> Dictionary:
	return {
		"rain": AmbienceSynth.make_rain_loop(2.0, 1),
		"crackle": AmbienceSynth.make_fire_crackle_loop(2.0, 2),
		"thunder": AmbienceSynth.make_thunder(1.0, 3),
		"artillery": AmbienceSynth.make_artillery_rumble(4),
		"mg": AmbienceSynth.make_distant_mg(5),
	}


func test_streams_are_valid_16bit_mono() -> void:
	for name in _all_streams():
		var wav: AudioStreamWAV = _all_streams()[name]
		assert_object(wav).is_not_null()
		assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
		assert_bool(wav.stereo).is_false()
		assert_int(wav.mix_rate).is_equal(AmbienceSynth.MIX_RATE)
		assert_int(wav.data.size()).is_greater(1000)
		assert_int(wav.data.size() % 2).is_equal(0)


func test_loops_are_flagged_and_one_shots_are_not() -> void:
	var rain := AmbienceSynth.make_rain_loop(2.0, 1)
	assert_int(rain.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(rain.loop_begin).is_equal(0)
	assert_int(rain.loop_end).is_equal(rain.data.size() / 2)

	var crackle := AmbienceSynth.make_fire_crackle_loop(2.0, 2)
	assert_int(crackle.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)

	assert_int(AmbienceSynth.make_thunder(1.0, 3).loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
	assert_int(AmbienceSynth.make_artillery_rumble(4).loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
	assert_int(AmbienceSynth.make_distant_mg(5).loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_same_seed_gives_identical_bytes() -> void:
	var a := AmbienceSynth.make_thunder(1.0, 42)
	var b := AmbienceSynth.make_thunder(1.0, 42)
	assert_bool(a.data == b.data).is_true()
	var c := AmbienceSynth.make_thunder(1.0, 43)
	assert_bool(a.data == c.data).is_false()


func test_peaks_are_limited() -> void:
	for name in _all_streams():
		var wav: AudioStreamWAV = _all_streams()[name]
		var max_abs := 0
		var data := wav.data
		for i in range(0, data.size(), 2):
			max_abs = maxi(max_abs, absi(data.decode_s16(i)))
		assert_int(max_abs).is_less_equal(int(0.95 * 32767.0))


func test_loop_seam_is_continuous() -> void:
	# In a LOOP_FORWARD stream the last sample wraps to the first: that seam jump must
	# be no larger than the signal's own interior transients (else it clicks).
	for wav: AudioStreamWAV in [AmbienceSynth.make_rain_loop(2.0, 1),
			AmbienceSynth.make_fire_crackle_loop(2.0, 2)]:
		var data := wav.data
		var max_inner_jump := 0
		for i in range(2, data.size(), 2):
			max_inner_jump = maxi(max_inner_jump,
					absi(data.decode_s16(i) - data.decode_s16(i - 2)))
		var seam_jump := absi(data.decode_s16(0) - data.decode_s16(data.size() - 2))
		assert_int(seam_jump).is_less_equal(max_inner_jump)