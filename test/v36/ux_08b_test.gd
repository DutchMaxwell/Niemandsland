extends GdUnitTestSuite
## UX-08b (0.3.15, rules 3.6): the Game School reads the Dangerous, rout and ruin lines of rules 3.6,
## and every consolidation combat log line names the marker outside its citation parenthetical.

const Lessons := preload("res://scripts/spielschule_lessons.gd")


func _step(chapter_id: String, step_id: String) -> Dictionary:
	for step in Lessons.steps_for(chapter_id):
		if String(step.get("id", "")) == step_id:
			return step
	return {}


func test_dangerous_lesson_step_names_one_test_per_unit() -> void:
	var step := _step("S-08", "dangerous")
	assert_bool(step.is_empty()).override_failure_message(
		"S-08 has no step 'dangerous'").is_false()
	if step.is_empty():
		return
	var text := String(step.get("text", ""))
	var lower := text.to_lower()
	assert_bool(lower.contains("one test")).override_failure_message(
		"the dangerous step does not name one test for the unit: '%s'" % text).is_true()
	assert_bool(lower.contains("wound")).override_failure_message(
		"the dangerous step does not roll a die per wound: '%s'" % text).is_true()
	assert_bool(lower.contains("per model")).override_failure_message(
		"the dangerous step still rolls one die per model: '%s'" % text).is_false()


func test_every_consolidation_log_line_names_it_outside_the_citation() -> void:
	var file := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	assert_object(file).override_failure_message(
		"cannot read res://scripts/main.gd").is_not_null()
	if file == null:
		return
	var cite_paren := RegEx.create_from_string("\\([^()]*GF v3\\.5\\.1 p\\.9[^()]*\\)")
	var checked := 0
	while not file.eof_reached():
		var line := file.get_line()
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if not line.contains("log_event"):
			continue
		if not line.to_lower().contains("consolidat"):
			continue
		if not line.contains("GF v3.5.1 p.9"):
			continue
		checked += 1
		var outside := cite_paren.sub(line, "", true)
		assert_bool(outside.to_lower().contains("consolidat")).override_failure_message(
			"this consolidation log line only names it inside the citation: '%s'" % line).is_true()
	assert_int(checked).override_failure_message(
		"found no consolidation log line carrying the citation").is_greater(0)


func test_ruins_lesson_step_names_unstable_terrain() -> void:
	var step := _step("S-08", "wall")
	assert_bool(step.is_empty()).override_failure_message(
		"S-08 has no step 'wall'").is_false()
	if step.is_empty():
		return
	var text := String(step.get("text", ""))
	assert_bool(text.contains("Unstable")).override_failure_message(
		"the ruin step does not name Unstable: '%s'" % text).is_true()
	assert_bool(text.contains("Cover")).override_failure_message(
		"the ruin step does not name Cover: '%s'" % text).is_true()
	assert_bool(text.to_lower().contains("not through")).override_failure_message(
		"the ruin step still says nobody sees through it: '%s'" % text).is_false()


func test_s07_outcome_sentence_leaves_rout_to_melee() -> void:
	var step := _step("S-07", "outcome")
	assert_bool(step.is_empty()).override_failure_message(
		"S-07 has no step 'outcome'").is_false()
	if step.is_empty():
		return
	var text := String(step.get("text", ""))
	var lower := text.to_lower()
	assert_bool(text.contains("Shaken")).override_failure_message(
		"the S-07 outcome does not name Shaken: '%s'" % text).is_true()
	assert_bool(lower.contains("melee")).override_failure_message(
		"the S-07 outcome does not leave the Rout to melee: '%s'" % text).is_true()
	assert_bool(lower.contains("routs")).override_failure_message(
		"the S-07 outcome still claims a shooting failure routs the unit: '%s'" % text).is_false()
