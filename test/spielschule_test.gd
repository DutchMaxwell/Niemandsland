extends GdUnitTestSuite
## Unit tests for the Game School chapter registry (Spielschule): the ten curriculum chapters + the
## reserved spell slot, the FRESH id space (no W-/T-track bleed), and the availability rule that
## drives the picker's disabled "scenario coming soon" rows.


func test_registry_has_ten_lessons_plus_the_reserved_spell_slot() -> void:
	var chapters := Spielschule.chapters()
	# 10 curriculum chapters + 1 reserved spell slot.
	assert_int(chapters.size()).is_equal(11)
	assert_int(Spielschule.lesson_ids().size()).is_equal(10)

	# Exactly one reserved slot, and it is the spell lesson.
	var reserved: Array = []
	for c in chapters:
		if bool(c.get("reserved", false)):
			reserved.append(String(c.get("id", "")))
	assert_array(reserved).is_equal(["S-SPELL"])


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


func test_chapter_one_is_available_because_its_placeholder_scenario_ships() -> void:
	# The one working end-to-end proof: chapter 1 bundles a (placeholder) scenario, so it is playable.
	var s01 := Spielschule.chapter("S-01")
	assert_str(String(s01.get("scenario", ""))).is_equal("res://assets/tutorial/scenarios/s01_werkzeug_grundlagen.nml")
	assert_bool(FileAccess.file_exists(String(s01.get("scenario", "")))).is_true()
	assert_bool(Spielschule.is_available(s01)).is_true()


func test_chapters_without_a_bundled_scenario_are_not_available() -> void:
	# Every chapter except S-01 has no scenario yet -> the picker shows "scenario coming soon", disabled.
	for c in Spielschule.chapters():
		if String(c.get("id", "")) == "S-01":
			continue
		assert_bool(Spielschule.is_available(c)) \
			.override_failure_message("%s must be unavailable until its scenario is authored" % c.get("id", "")) \
			.is_false()


func test_reserved_spell_slot_is_never_available_even_if_a_file_appeared() -> void:
	# reserved wins regardless of any scenario path — the spell lesson waits for the spell wave.
	var reserved := {"id": "S-SPELL", "title": "Spellcasting", "goal": "x",
		"scenario": "res://assets/tutorial/scenarios/s01_werkzeug_grundlagen.nml", "reserved": true}
	assert_bool(Spielschule.is_available(reserved)).is_false()


func test_chapter_lookup_returns_empty_for_unknown_id() -> void:
	assert_dict(Spielschule.chapter("nope")).is_empty()
	assert_dict(Spielschule.chapter("S-01")).is_not_empty()
