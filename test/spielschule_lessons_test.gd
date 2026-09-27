extends GdUnitTestSuite
## Unit tests for SpielschuleLessons: S-01's six steps, and the guarantees LessonRunner relies on
## (every step has text and a check, every check name is real, an unknown chapter yields no steps).


func test_s01_has_six_steps() -> void:
	assert_array(SpielschuleLessons.steps_for("S-01")).has_size(6)


func test_every_s01_step_has_text_and_at_least_one_check() -> void:
	for step in SpielschuleLessons.steps_for("S-01"):
		assert_str(String(step.get("text", ""))).is_not_empty()
		var checks: Array = step.get("all", [])
		assert_bool(checks.size() >= 1).is_true()


func test_every_s01_check_name_is_known_to_lesson_checks() -> void:
	for step in SpielschuleLessons.steps_for("S-01"):
		for entry in step.get("all", []):
			var check_name := String(entry.get("check", ""))
			assert_bool(LessonChecks.KNOWN.has(check_name)) \
				.override_failure_message("'%s' is not a known LessonChecks check" % check_name) \
				.is_true()


func test_unknown_chapter_has_no_steps() -> void:
	assert_array(SpielschuleLessons.steps_for("S-99")).is_empty()


func test_s01_ai_mode_is_none() -> void:
	assert_str(SpielschuleLessons.ai_mode("S-01")).is_equal("none")
