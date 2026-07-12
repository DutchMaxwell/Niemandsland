extends GdUnitTestSuite
## Battle Log collector: event in → formatted entry, ring-buffer cap, and the category/AI filter.


func test_log_event_records_round_prefixed_entry_and_emits() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.current_round = 2
	var captured: Array = []
	log_node.entry_added.connect(func(entry: Dictionary) -> void: captured.append(entry))
	var e := log_node.log_event(BattleLog.Category.MOVEMENT, "Skeletons advance 6\"")
	assert_int(int(e["round"])).is_equal(2)
	assert_int(int(e["category"])).is_equal(BattleLog.Category.MOVEMENT)
	assert_str(BattleLog.format_entry(e)).is_equal("R2  Skeletons advance 6\"")
	assert_int(captured.size()).is_equal(1)   # entry_added fired for the panel


func test_dice_roll_without_success_target_still_logs() -> void:
	# Most casual rolls carry no success target; they were silently dropped and the log looked empty.
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.on_dice_rolled(6, 0, 0)
	assert_int(log_node.size()).is_equal(1)
	assert_str(str(log_node.entries()[0]["text"])).is_equal("6 dice rolled")
	log_node.on_dice_rolled(6, 3, 3)
	assert_str(str(log_node.entries()[1]["text"])).is_equal("6 dice → 3 hits (3+)")


func test_dice_roll_logs_who_and_face_results() -> void:
	# The log carries WHO rolled + the actual faces (high→low), not just a count (maintainer).
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.on_dice_rolled(4, 2, 4, "You", [2, 6, 1, 5])
	assert_str(str(log_node.entries()[0]["text"])).is_equal("You: 6 5 2 1 → 2 hits (4+)")
	log_node.on_dice_rolled(3, 0, 0, "Alice", [3, 1, 5])
	assert_str(str(log_node.entries()[1]["text"])).is_equal("Alice: 5 3 1")
	# Faces without a player still show the results.
	log_node.on_dice_rolled(2, 0, 0, "", [4, 2])
	assert_str(str(log_node.entries()[2]["text"])).is_equal("2 dice: 4 2")


func test_ring_buffer_caps_and_drops_oldest() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	for i in range(BattleLog.CAP + 50):
		log_node.log_event(BattleLog.Category.GENERAL, "e%d" % i)
	assert_int(log_node.size()).is_equal(BattleLog.CAP)
	# The oldest 50 dropped → the first surviving entry is e50.
	assert_str(str(log_node.entries()[0]["text"])).is_equal("e50")


func test_filter_by_category_and_ai() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.log_event(BattleLog.Category.COMBAT, "6 dice → 3 hits (4+)")
	log_node.log_event(BattleLog.Category.MOVEMENT, "Knights move 5\"")
	log_node.log_event(BattleLog.Category.MOVEMENT, "Ghouls advance 6\"", true)   # AI move
	log_node.log_event(BattleLog.Category.GENERAL, "— Round 2 —")
	assert_int(log_node.entries(BattleLog.Filter.ALL).size()).is_equal(4)
	assert_int(log_node.entries(BattleLog.Filter.COMBAT).size()).is_equal(1)
	assert_int(log_node.entries(BattleLog.Filter.MOVEMENT).size()).is_equal(2)
	# AI filter surfaces the AI-tagged entry regardless of its (movement) category.
	var ai_only := log_node.entries(BattleLog.Filter.AI)
	assert_int(ai_only.size()).is_equal(1)
	assert_str(str(ai_only[0]["text"])).is_equal("Ghouls advance 6\"")


func test_event_seams_produce_expected_entries() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.on_round_advanced(3)
	assert_int(log_node.current_round).is_equal(3)
	assert_str(str(log_node.entries()[-1]["text"])).is_equal("— Round 3 —")

	log_node.on_unit_moved("Skeletons", 6.0, true)
	var mv: Dictionary = log_node.entries()[-1]
	assert_int(int(mv["category"])).is_equal(BattleLog.Category.MOVEMENT)
	assert_bool(bool(mv["ai"])).is_true()
	assert_str(str(mv["text"])).is_equal("Skeletons advances 6\"")

	log_node.on_dice_rolled(6, 1, 4)
	assert_str(str(log_node.entries()[-1]["text"])).is_equal("6 dice → 1 hit (4+)")   # singular "hit"

	log_node.on_wounds("Knights", 2, 3, 5)
	assert_str(str(log_node.entries()[-1]["text"])).is_equal("Knights takes 2 wounds (3/5)")
	assert_int(int(log_node.entries()[-1]["category"])).is_equal(BattleLog.Category.COMBAT)


# === Export (finding 3): entries → shareable text, with the dev AI decision records when supplied ===

func test_export_text_formats_entries_and_decision_records() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.current_round = 1
	log_node.log_event(BattleLog.Category.MOVEMENT, "Skeletons advance 6\"")
	log_node.current_round = 2
	log_node.log_event(BattleLog.Category.COMBAT, "Skeletons fire — 3 hits", true)
	var text := BattleLog.export_text(log_node.entries(), ["AI [move] Skeletons — chose Advance"])
	assert_str(text).contains("R1  Skeletons advance 6\"")
	assert_str(text).contains("R2  Skeletons fire — 3 hits")
	assert_str(text).contains("--- AI decision records ---")
	assert_str(text).contains("AI [move] Skeletons — chose Advance")


func test_export_text_without_records_omits_that_section() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.log_event(BattleLog.Category.GENERAL, "Battle started")
	var text := BattleLog.export_text(log_node.entries())
	assert_str(text).contains("Battle started")
	assert_bool(text.contains("AI decision records")).is_false()


func test_export_to_file_writes_and_returns_absolute_path() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.log_event(BattleLog.Category.GENERAL, "Battle started")
	var path := log_node.export_to_file()
	assert_str(path).is_not_empty()
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(FileAccess.get_file_as_string(path)).contains("Battle started")
	DirAccess.remove_absolute(path)   # clean up the temp export
