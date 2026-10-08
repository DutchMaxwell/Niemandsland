extends GdUnitTestSuite
## Unit tests for the Game School chapter registry (Spielschule): the eleven curriculum chapters, the
## FRESH id space (no W-/T-track bleed), and the availability rule that drives the picker's disabled
## "scenario coming soon" rows.


func test_registry_has_eleven_lessons() -> void:
	var chapters := Spielschule.chapters()
	assert_int(chapters.size()).is_equal(11)
	assert_int(Spielschule.lesson_ids().size()).is_equal(11)
	# The spell lesson now sits between terrain (S-08) and objectives (S-09), printed-rulebook order.
	assert_array(Spielschule.ids()).is_equal(["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07",
		"S-08", "S-SPELL", "S-09", "S-10"])


func test_chapter_ids_are_fresh_and_never_a_w_or_t_track_id() -> void:
	# The mission's HARD rule: fresh ids so progress can never migrate/collide with the old tutorial.
	for id in Spielschule.ids():
		assert_bool(id.begins_with("S-")) \
			.override_failure_message("chapter id '%s' must be a fresh Game School id (S-*)" % id) \
			.is_true()
		assert_bool(id.begins_with("W")).is_false()
		assert_bool(id.begins_with("T-")).is_false()


func test_every_chapter_has_a_title_and_a_one_line_goal() -> void:
	for c in Spielschule.chapters():
		assert_str(String(c.get("title", ""))).is_not_empty()
		assert_str(String(c.get("goal", ""))).is_not_empty()


func test_chapter_one_is_available_because_its_scenario_ships() -> void:
	# Chapter 1 bundles a scenario, so it is playable.
	var s01 := Spielschule.chapter("S-01")
	assert_str(String(s01.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s01_werkzeug_grundlagen.nml")
	assert_bool(FileAccess.file_exists(String(s01.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s01)).is_true()


func test_chapter_two_is_available_because_its_scenario_ships() -> void:
	var s02 := Spielschule.chapter("S-02")
	assert_str(String(s02.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s02_table_setup.nml")
	assert_bool(FileAccess.file_exists(String(s02.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s02)).is_true()


func test_chapter_three_is_available_because_its_scenario_ships() -> void:
	var s03 := Spielschule.chapter("S-03")
	assert_str(String(s03.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s03_bring_your_army.nml")
	assert_bool(FileAccess.file_exists(String(s03.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s03)).is_true()


func test_chapter_four_is_available_and_titled_activate_and_move() -> void:
	var s04 := Spielschule.chapter("S-04")
	assert_str(String(s04.get("title", ""))).is_equal("Activate & Move")
	assert_str(String(s04.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s04_activate_and_move.nml")
	assert_bool(FileAccess.file_exists(String(s04.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s04)).is_true()


func test_chapter_five_is_available_and_titled_shooting() -> void:
	var s05 := Spielschule.chapter("S-05")
	assert_str(String(s05.get("title", ""))).is_equal("Shooting")
	assert_str(String(s05.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s05_shooting.nml")
	assert_bool(FileAccess.file_exists(String(s05.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s05)).is_true()


func test_chapter_six_is_available_and_titled_melee() -> void:
	var s06 := Spielschule.chapter("S-06")
	assert_str(String(s06.get("title", ""))).is_equal("Melee")
	assert_str(String(s06.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s06_melee.nml")
	assert_bool(FileAccess.file_exists(String(s06.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s06)).is_true()


func test_chapters_without_a_bundled_scenario_are_not_available() -> void:
	# Every chapter whose scenario file has not been authored yet stays unavailable ("coming soon").
	for c in Spielschule.chapters():
		if FileAccess.file_exists(String(c.get("scenario", ""))):
			continue
		assert_bool(Spielschule.is_available(c)) \
			.override_failure_message("%s must be unavailable until its scenario is authored" % c.get("id", "")) \
			.is_false()


func test_chapter_lookup_returns_empty_for_unknown_id() -> void:
	assert_dict(Spielschule.chapter("nope")).is_empty()
	assert_dict(Spielschule.chapter("S-01")).is_not_empty()
