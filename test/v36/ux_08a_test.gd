extends GdUnitTestSuite
## UX-08a (0.3.15, rules 3.6): the Game School never shows a printed page number. The lesson text
## carries no page citation; the card caption names the rules edition the build plays, read from the
## same rule-map reader the version label uses. The `rule` field stays as hidden traceability and is
## corrected for the steps whose page moved in the new edition.

const Card := preload("res://scripts/hud/lesson_card.gd")

const CHAPTERS := ["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07", "S-08",
	"S-SPELL", "S-09", "S-10"]

## The steps whose printed page moved in the 3.6 edition: step id -> corrected hidden field.
const MOVED_RULES := {
	"S-02": {"terrain_piece": "p.11", "autogen": "p.11"},
	"S-08": {"move_forest": "p.12", "difficult": "p.12", "cover": "p.12",
		"shoot_cover": "p.12", "wall": "p.12"},
}


func before_test() -> void:
	OPRApiClient._core_versions.clear()


func after_test() -> void:
	OPRApiClient._core_versions.clear()


func _rules_mm() -> String:
	return OPRApiClient._major_minor(OPRApiClient.rules_core_version("gf"))


func _step(chapter_id: String, step_id: String) -> Dictionary:
	for step in SpielschuleLessons.steps_for(chapter_id):
		if String(step.get("id", "")) == step_id:
			return step
	return {}


func test_no_lesson_step_text_carries_a_page_reference() -> void:
	var paren_page := RegEx.create_from_string("\\(p\\.")
	var bare_page := RegEx.create_from_string("\\bp\\.\\d")
	var rulebook := RegEx.create_from_string("Rulebook p")
	for chapter_id in CHAPTERS:
		for step in SpielschuleLessons.steps_for(chapter_id):
			var text := String(step.get("text", ""))
			var hit := paren_page.search(text) != null or bare_page.search(text) != null \
				or rulebook.search(text) != null
			assert_bool(hit) \
				.override_failure_message("%s step '%s' still cites a page: %s" % [
					chapter_id, step.get("id", ""), text]) \
				.is_false()


func test_lesson_caption_names_rules_version_without_page() -> void:
	var rules := _rules_mm()
	assert_str(rules).override_failure_message(
		"the GF rule map names no major.minor rules version").is_not_empty()
	var card: LessonCard = auto_free(Card.new())
	add_child(card)
	card.show_step(0, 1, {"text": "Read this.", "rule": "p.5", "all": [
		{"check": "counter_grew", "args": {"key": "continue"}}]})
	var caption := (card.get_node("Content/Rule") as Label).text
	assert_str(caption).override_failure_message(
		"the lesson caption does not name the rules edition: '%s'" % caption).is_equal("Rules " + rules)
	var page_hit := RegEx.create_from_string("p\\.\\d").search(caption) != null
	assert_bool(page_hit).override_failure_message(
		"the lesson caption still shows a page: '%s'" % caption).is_false()


func test_moved_steps_carry_the_corrected_rule_field() -> void:
	for chapter_id in MOVED_RULES:
		for step_id in MOVED_RULES[chapter_id]:
			var step := _step(chapter_id, step_id)
			assert_bool(step.is_empty()).override_failure_message(
				"%s has no step '%s'" % [chapter_id, step_id]).is_false()
			if step.is_empty():
				continue
			assert_str(String(step.get("rule", ""))).override_failure_message(
				"%s step '%s' has the wrong hidden rule field" % [chapter_id, step_id]) \
				.is_equal(MOVED_RULES[chapter_id][step_id])
