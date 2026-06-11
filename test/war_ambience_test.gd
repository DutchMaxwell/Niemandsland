extends GdUnitTestSuite
## Tests the WarAmbience scheduling/maths and the fire-crackle emitter cap.


func _ambience() -> WarAmbience:
	var ambience := WarAmbience.new()
	add_child(ambience)
	return auto_free(ambience)


func test_interval_bounds_are_sane() -> void:
	assert_float(WarAmbience.WAR_SFX_MIN_INTERVAL_S).is_greater(0.0)
	assert_float(WarAmbience.WAR_SFX_MAX_INTERVAL_S).is_greater(WarAmbience.WAR_SFX_MIN_INTERVAL_S)
	# The first shot after enabling must come quickly (audible toggle feedback).
	assert_float(WarAmbience.WAR_SFX_FIRST_DELAY_MAX_S).is_less_equal(8.0)


func test_enabling_schedules_quickly_and_fires_a_sound() -> void:
	var ambience := _ambience()
	ambience.set_war_sounds_enabled(true)
	assert_float(ambience._timer.wait_time).is_between(
			WarAmbience.WAR_SFX_FIRST_DELAY_MIN_S, WarAmbience.WAR_SFX_FIRST_DELAY_MAX_S)

	# Trigger the due-callback directly: a stream must be playing afterwards and the
	# next shot must be scheduled in the regular interval window.
	ambience._on_war_sfx_due()
	assert_bool(ambience._war_player.playing).is_true()
	assert_object(ambience._war_player.stream).is_not_null()
	assert_float(ambience._war_player.volume_db).is_between(
			WarAmbience.WAR_SFX_VOLUME_DB_MIN, WarAmbience.WAR_SFX_VOLUME_DB_MAX)
	assert_float(ambience._timer.wait_time).is_between(
			WarAmbience.WAR_SFX_MIN_INTERVAL_S, WarAmbience.WAR_SFX_MAX_INTERVAL_S)


func test_thunder_volume_falls_with_distance_delay() -> void:
	var previous := 100.0
	for delay in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		var volume: float = WarAmbience.thunder_volume_db(delay)
		assert_float(volume).is_less(previous)
		previous = volume


func test_fire_crackle_emitters_are_capped() -> void:
	var ambience := _ambience()
	var positions: Array = []
	for i in 7:
		positions.append(Vector3(float(i), 0.0, 0.0))
	ambience.update_fire_crackle(positions)

	for i in WarAmbience.MAX_FIRE_CRACKLE_EMITTERS:
		assert_bool(ambience._crackle_players[i].playing).is_true()
		assert_float(ambience._crackle_players[i].position.x).is_equal_approx(float(i), 0.001)
	assert_int(ambience._crackle_players.size()).is_equal(WarAmbience.MAX_FIRE_CRACKLE_EMITTERS)


func test_crackle_stops_when_fires_clear() -> void:
	var ambience := _ambience()
	ambience.update_fire_crackle([Vector3.ZERO, Vector3.ONE])
	ambience.update_fire_crackle([])
	for crackle in ambience._crackle_players:
		assert_bool(crackle.playing).is_false()