extends GdUnitTestSuite
## Unit tests for SpielschuleLessons: S-01's six steps, and the guarantees LessonRunner relies on
## (every step has text and a check, every check name is real, an unknown chapter yields no steps).


func test_s01_has_six_steps() -> void:
	assert_array(SpielschuleLessons.steps_for("S-01")).has_size(6)


func test_s02_has_five_steps() -> void:
	assert_array(SpielschuleLessons.steps_for("S-02")).has_size(5)


func test_s03_has_four_steps() -> void:
	assert_array(SpielschuleLessons.steps_for("S-03")).has_size(4)


func test_every_step_has_text_and_at_least_one_check() -> void:
	for chapter_id in ["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07", "S-08", "S-09"]:
		for step in SpielschuleLessons.steps_for(chapter_id):
			assert_str(String(step.get("text", ""))).is_not_empty()
			var checks: Array = step.get("all", [])
			assert_bool(checks.size() >= 1).is_true()


func test_every_check_name_is_known_to_lesson_checks() -> void:
	for chapter_id in ["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07", "S-08", "S-09"]:
		for step in SpielschuleLessons.steps_for(chapter_id):
			for entry in step.get("all", []):
				var check_name := String(entry.get("check", ""))
				assert_bool(LessonChecks.KNOWN.has(check_name)) \
					.override_failure_message("'%s' is not a known LessonChecks check" % check_name) \
					.is_true()


func test_unknown_chapter_has_no_steps() -> void:
	assert_array(SpielschuleLessons.steps_for("S-99")).is_empty()


func test_step_texts_never_leak_lesson_tags() -> void:
	# The player sees unit names, not lesson tags (chapter 1 sets the tone: "one of your models").
	# A stamped display name like "Alpha Squad" is fine; the bare tag is not. The rule words
	# "Shaken"/"Tough(3)" are capitalised game terms and are allowed — only the bare lowercase tag
	# would be a leak, so the second check is case-sensitive.
	var leak := RegEx.create_from_string("(?i)\\b(?:alpha|bravo|far|target)\\b(?! squad)")
	var bare_tag := RegEx.create_from_string("\\b(?:shaken|tough)\\b")
	for chapter_id in ["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07", "S-08", "S-09"]:
		for step in SpielschuleLessons.steps_for(chapter_id):
			var text := String(step.get("text", ""))
			assert_bool(leak.search(text) != null) \
				.override_failure_message("%s step '%s' leaks a lesson tag: %s" % [
					chapter_id, step.get("id", ""), text]) \
				.is_false()
			assert_bool(bare_tag.search(text) != null) \
				.override_failure_message("%s step '%s' leaks a bare tag: %s" % [
					chapter_id, step.get("id", ""), text]) \
				.is_false()


func test_s01_ai_mode_is_none() -> void:
	assert_str(SpielschuleLessons.ai_mode("S-01")).is_equal("none")


func test_s02_ai_mode_is_none() -> void:
	assert_str(SpielschuleLessons.ai_mode("S-02")).is_equal("none")


func test_s03_ai_mode_is_none() -> void:
	assert_str(SpielschuleLessons.ai_mode("S-03")).is_equal("none")


func test_s04_has_five_steps_and_holds_the_ai() -> void:
	assert_array(SpielschuleLessons.steps_for("S-04")).has_size(5)
	assert_str(SpielschuleLessons.ai_mode("S-04")).is_equal("hold")


func test_s05_has_four_steps_and_holds_the_ai() -> void:
	assert_array(SpielschuleLessons.steps_for("S-05")).has_size(4)
	assert_str(SpielschuleLessons.ai_mode("S-05")).is_equal("hold")


func test_s06_has_five_steps_and_holds_the_ai() -> void:
	assert_array(SpielschuleLessons.steps_for("S-06")).has_size(5)
	assert_str(SpielschuleLessons.ai_mode("S-06")).is_equal("hold")


func test_s07_has_five_steps_and_holds_the_ai() -> void:
	assert_array(SpielschuleLessons.steps_for("S-07")).has_size(5)
	assert_str(SpielschuleLessons.ai_mode("S-07")).is_equal("hold")


func test_s08_has_six_steps_and_holds_the_ai() -> void:
	assert_array(SpielschuleLessons.steps_for("S-08")).has_size(6)
	assert_str(SpielschuleLessons.ai_mode("S-08")).is_equal("hold")


func test_s09_has_four_steps_and_holds_the_ai() -> void:
	assert_array(SpielschuleLessons.steps_for("S-09")).has_size(4)
	assert_str(SpielschuleLessons.ai_mode("S-09")).is_equal("hold")
