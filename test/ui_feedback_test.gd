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


# ===== Panel and sheet sounds =====


## Power of `samples` (floats, -1..1) at `hz` by the Goertzel recurrence, per sample.
func _power_at(samples: PackedFloat32Array, hz: float, rate: float) -> float:
	var k := 2.0 * cos(TAU * hz / rate)
	var s1 := 0.0
	var s2 := 0.0
	for x in samples:
		var s0 := x + k * s1 - s2
		s2 = s1
		s1 = s0
	return (s1 * s1 + s2 * s2 - k * s1 * s2) / float(samples.size() * samples.size())


## The level of a signal in the 400 - 1600 Hz band (dB, mean power over seven bins).
func _band_db(samples: PackedFloat32Array, rate: float) -> float:
	var total := 0.0
	for hz: float in [400.0, 550.0, 750.0, 1000.0, 1250.0, 1450.0, 1600.0]:
		total += _power_at(samples, hz, rate)
	return 10.0 * log(maxf(total / 7.0, 1e-20)) / log(10.0)


func _floats(w: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in w.data.size() / 2:
		out.append(float(w.data.decode_s16(i * 2)) / 32767.0)
	return out


## The panel sounds exist with the lengths and the level of the sound table, and sit at least 6 dB
## above the music bed in their band (house audibility rule). The bed is the menu drone at its
## -12 dB; a version without the sound (silence) is red. RED on main: there is no panel sound.
func test_panel_sounds_exist_and_are_audible_over_the_music_bed() -> void:
	var inward: Variant = UiFeedback.get("_snd_panel_in")
	var outward: Variant = UiFeedback.get("_snd_panel_out")
	assert_bool(inward is AudioStreamWAV and outward is AudioStreamWAV).override_failure_message(
		"no panel sounds").is_true()
	if inward is not AudioStreamWAV or outward is not AudioStreamWAV:
		return
	assert_int(inward.data.size()).is_equal(int(0.18 * 22050.0) * 2)
	assert_int(outward.data.size()).is_equal(int(0.14 * 22050.0) * 2)
	var bed_wav := AmbienceSynth.make_menu_drone_pad()
	var bed := PackedFloat32Array()
	var bed_offset := int(2.0 * 22050.0)
	var bed_gain := pow(10.0, -12.0 / 20.0)
	for i in 3969:
		bed.append(float(bed_wav.data.decode_s16((bed_offset + i) * 2)) / 32767.0 * bed_gain)
	var bed_db := _band_db(bed, 22050.0)
	for sound: AudioStreamWAV in [inward, outward]:
		var peak := 0.0
		for x in _floats(sound):
			peak = maxf(peak, absf(x))
		assert_float(peak).is_between(0.05, 0.061)
		var margin := _band_db(_floats(sound), 22050.0) - bed_db
		assert_float(margin).override_failure_message(
			"only %.1f dB above the music bed" % margin).is_greater_equal(6.0)
	var silent := AudioStreamWAV.new()
	silent.data.resize(inward.data.size())
	var silent_margin := _band_db(_floats(silent), 22050.0) - bed_db
	assert_float(silent_margin).override_failure_message("the check cannot fail").is_less(6.0)


## Opening and closing a sub-menu plays the panel sound.
func test_the_sub_menu_plays_the_panel_sound() -> void:
	if not UiFeedback.has_method("play_panel"):
		fail("no play_panel")
		return
	var view: Control = auto_free(load("res://scripts/startup_menu_view.gd").new())
	add_child(view)
	await get_tree().process_frame
	var played := func(sound: AudioStreamWAV) -> bool:
		return UiFeedback._players.any(func(p: AudioStreamPlayer) -> bool: return p.stream == sound)
	view.show_route("help")
	assert_bool(played.call(UiFeedback._snd_panel_in)).override_failure_message(
		"opening the sub-menu played no panel sound").is_true()
	view.close_route()
	assert_bool(played.call(UiFeedback._snd_panel_out)).override_failure_message(
		"closing the sub-menu played no panel sound").is_true()
