extends GdUnitTestSuite
## UiFeedback autoload: every BaseButton gets hover/click/focus sound wiring
## (playbook: "UI audio — a UiSound autoload auto-wiring BaseButton signals").

# ===== Auto-wiring =====


func test_button_added_to_tree_gets_wired() -> void:
	var btn: Button = auto_free(Button.new())
	add_child(btn)
	await get_tree().process_frame
	assert_bool(btn.has_meta(UiFeedback.WIRED_META)).is_true()
	assert_int(btn.pressed.get_connections().size()).is_greater(0)
	assert_int(btn.mouse_entered.get_connections().size()).is_greater(0)
	assert_int(btn.focus_entered.get_connections().size()).is_greater(0)


func test_wiring_is_idempotent() -> void:
	var btn: Button = auto_free(Button.new())
	add_child(btn)
	await get_tree().process_frame
	var pressed_count := btn.pressed.get_connections().size()
	UiFeedback._wire(btn)  # second wire attempt must be a no-op
	assert_int(btn.pressed.get_connections().size()).is_equal(pressed_count)

# ===== Procedural tones =====


func test_tone_produces_mono_16bit_wav_of_expected_length() -> void:
	var w: AudioStreamWAV = UiFeedback._tone([1000.0], 0.05, 0.2)
	assert_object(w).is_not_null()
	assert_bool(w.stereo).is_false()
	assert_int(w.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	# 0.05 s at 22050 Hz, 2 bytes per sample.
	assert_int(w.data.size()).is_equal(int(0.05 * 22050.0) * 2)


func test_all_feedback_tones_exist() -> void:
	assert_object(UiFeedback._snd_click).is_not_null()
	assert_object(UiFeedback._snd_confirm).is_not_null()
	assert_object(UiFeedback._snd_back).is_not_null()
	assert_object(UiFeedback._snd_hover).is_not_null()
	assert_object(UiFeedback._snd_focus).is_not_null()

# ===== Which tone a button plays =====


## The house gold main actions confirm, the house danger button goes back; every other button clicks
## (red on main: the lookup still named the pre-September variants, so both returned the click).
func _tone_of(variant: StringName) -> AudioStreamWAV:
	var btn: Button = auto_free(Button.new())
	btn.theme_type_variation = variant
	return UiFeedback._sound_for(btn)


func test_house_primary_variants_play_the_confirm_tone() -> void:
	for variant: StringName in [HouseStyle.PRIMARY, HouseStyle.BAR_PRIMARY, &"PrimaryButton"]:
		assert_object(_tone_of(variant)) \
			.override_failure_message("%s does not confirm" % variant) \
			.is_same(UiFeedback._snd_confirm)


func test_house_danger_variant_plays_the_back_tone() -> void:
	for variant: StringName in [HouseStyle.DANGER_BUTTON, &"DangerButton"]:
		assert_object(_tone_of(variant)) \
			.override_failure_message("%s does not go back" % variant) \
			.is_same(UiFeedback._snd_back)


func test_other_buttons_keep_the_click_tone() -> void:
	for variant: StringName in [&"", HouseStyle.BUTTON, HouseStyle.SEGMENT]:
		assert_object(_tone_of(variant)) \
			.override_failure_message("%s does not click" % variant) \
			.is_same(UiFeedback._snd_click)

# ===== Persisted buses =====


func test_ui_bus_exists_and_is_persisted() -> void:
	assert_int(AudioServer.get_bus_index(AudioManager.BUS_UI)).is_greater_equal(0)
	assert_bool(AudioManager.PERSISTED_BUSES.has(AudioManager.BUS_UI)).is_true()
