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


## A row that draws its own text answers the pointer with a fill and a tick, never with a scale
## (scaled, the text turns soft). RED on main: the row grew to 1.02. The plain button proves the
## hover scale itself still works.
func test_flat_control_keeps_scale_one_on_hover() -> void:
	var flat: Button = auto_free(Button.new())
	flat.set_meta("ui_motion_flat", true)
	var plain: Button = auto_free(Button.new())
	add_child(flat)
	add_child(plain)
	await get_tree().process_frame
	flat.mouse_entered.emit()
	plain.mouse_entered.emit()
	await get_tree().create_timer(0.3).timeout
	assert_float(plain.scale.x).override_failure_message(
		"the plain button no longer scales on hover").is_greater(1.0)
	assert_float(flat.scale.x).override_failure_message(
		"a flat control scaled to %s on hover" % flat.scale.x).is_equal(1.0)
