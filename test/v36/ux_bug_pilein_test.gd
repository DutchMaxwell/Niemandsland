extends GdUnitTestSuite

## Issue #1935: the Game School melee lesson (S-06 step "pile_in") waits for log:pile_in. When every
## defender model already touches its enemy, main.gd logs "no pile-in needed" (hyphen) instead of
## "pile in" — the pile-in phase still happened, so the marker must fire.

const Facts := preload("res://scripts/lesson_facts.gd")

class FakeLog extends Node:
	signal entry_added(entry: Dictionary)


func _facts_on(log_node: FakeLog) -> Facts:
	var facts := Facts.new()
	facts.setup({"battle_log": log_node})
	return facts


func test_no_pile_in_needed_line_marks_the_pile_in_event() -> void:
	var log_node: FakeLog = auto_free(FakeLog.new())
	add_child(log_node)
	var facts := _facts_on(log_node)
	log_node.entry_added.emit({"text": "Warriors: all models already in base contact — no pile-in needed (GF v3.5.1 p.9)"})
	assert_int(facts.snapshot().counters.get("log:pile_in", 0)).is_equal(1)


func test_other_melee_lines_do_not_mark_pile_in() -> void:
	var log_node: FakeLog = auto_free(FakeLog.new())
	add_child(log_node)
	var facts := _facts_on(log_node)
	log_node.entry_added.emit({"text": "Raiders charges into base contact (+1.5\") — the unit follows in coherency (GF/AoF v3.5.1 p.8)"})
	log_node.entry_added.emit({"text": "Raiders strikes with Hand Weapon at Warriors — 3 hits"})
	log_node.entry_added.emit({"text": "Shaken: Warriors strikes back counting as fatigued (6+)"})
	assert_int(facts.snapshot().counters.get("log:pile_in", 0)).is_equal(0)
