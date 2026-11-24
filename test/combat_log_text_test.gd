extends GdUnitTestSuite
## Community-visibility texts (issues #169 + #173): the Blast line is ALWAYS emitted and
## names the cap when it clamps the multiplier; an impossible-looking "7+" save threshold
## says that a natural 6 still saves. Uncapped/normal cases keep the old formats
## byte-identical (external log readers rely on them).

const MainScript := preload("res://scripts/main.gd")


func test_blast_line_uncapped_keeps_the_old_format() -> void:
	assert_str(MainScript.blast_log_text(3, 2, 6, 21)).is_equal("Blast(3): 2 hits ×3 → 6 hits")
	assert_str(MainScript.blast_log_text(3, 1, 3, 5)).is_equal("Blast(3): 1 hit ×3 → 3 hits")


func test_blast_line_names_the_cap_when_it_clamps() -> void:
	# 4 hits vs a single model: ×1 — the silent case that read as "full blast" (#169).
	assert_str(MainScript.blast_log_text(3, 4, 4, 1)).is_equal(
		"Blast(3): 4 hits ×1 (capped by 1 model in target) → 4 hits"
	)
	assert_str(MainScript.blast_log_text(3, 2, 4, 2)).is_equal(
		"Blast(3): 2 hits ×2 (capped by 2 models in target) → 4 hits"
	)


func test_save_threshold_within_d6_keeps_the_old_format() -> void:
	assert_str(MainScript.save_threshold_text(4, 1)).is_equal("5+ (Def 4+, AP 1)")
	assert_str(MainScript.save_threshold_text(5, 0)).is_equal("5+")


func test_save_threshold_past_six_names_the_natural_six() -> void:
	assert_str(MainScript.save_threshold_text(6, 1)).is_equal(
		"6 only (Def 6+, AP 1 — a natural 6 always saves)"
	)
	assert_str(MainScript.save_threshold_text(6, 4)).is_equal(
		"6 only (Def 6+, AP 4 — a natural 6 always saves)"
	)


## Live test 24.11.: "pick a enemy target" - the article follows the side word.
func test_cast_pick_prompt_takes_the_article_of_its_side() -> void:
	assert_str(MainScript.cast_pick_prompt("Great Sister", "enemy", "Mind Gash", 1)).is_equal(
		"Great Sister: pick an enemy target for Mind Gash (1 marked in range) — right-click cancels"
	)
	(
		assert_str(MainScript.cast_pick_prompt("Great Sister", "friendly", "Blessing", 2))
		. is_equal(
			"Great Sister: pick a friendly target for Blessing (2 marked in range) — right-click cancels"
		)
	)


## Live test 24.11.: "saves on 6 only (... a natural 6 always saves)" was followed by a dice line
## ending "(7+)" or "(9+)".
## The defense line shows the target the dice really need: 6+. Attack lines keep their raw target.
func test_save_dice_line_past_six_shows_six_plus() -> void:
	var log_node: BattleLog = auto_free(BattleLog.new())
	log_node.on_dice_rolled(4, 0, 7, "AI (Assault Grunts)", [5, 4, 2, 1], "defense")
	log_node.on_dice_rolled(1, 1, 9, "AI (Assault Grunts)", [6], "defense")
	log_node.on_dice_rolled(2, 0, 8, "AI (Assault Grunts)", [], "defense")
	log_node.on_dice_rolled(2, 1, 5, "AI (Assault Grunts)", [5, 1], "defense")
	assert_str(str(log_node.entries()[0]["text"])).is_equal(
		"AI (Assault Grunts) defends: 5 4 2 1 → 0 blocks (6+)"
	)
	assert_str(str(log_node.entries()[1]["text"])).is_equal(
		"AI (Assault Grunts) defends: 6 → 1 block (6+)"
	)
	assert_str(str(log_node.entries()[2]["text"])).is_equal(
		"AI (Assault Grunts) defends: 2 dice → 0 blocks (6+)"
	)
	assert_str(str(log_node.entries()[3]["text"])).is_equal(
		"AI (Assault Grunts) defends: 5 1 → 1 block (5+)"
	)
