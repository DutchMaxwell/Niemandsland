extends GdUnitTestSuite
## melee95: the melee shadow's table-side filter drops the tray's DICE lines only. A rule line with an arrow in it stays (the core says it too).
## RED with the old `contains(" → ")` filter: the Blast line was dropped from the table's side and read as a core-only difference.


func test_only_the_dice_lines_are_roll_lines() -> void:
	assert_bool(CoreShadow.is_roll_line("COMBAT|AI (Wardens): 6 4 → 2 hits (4+)")).is_true()
	assert_bool(CoreShadow.is_roll_line("COMBAT|AI (Steam-Suits) defends: 6 5 3 → 1 block (3+)")).is_true()
	assert_bool(CoreShadow.is_roll_line("COMBAT|Blast(3): 1 hit ×3 → 3 hits")).override_failure_message("a Blast line is a rule line").is_false()
	assert_bool(CoreShadow.is_roll_line("COMBAT|Wardens strikes with Thunder Mace at Steam-Suits — 3 hits")).is_false()
	assert_bool(CoreShadow.is_roll_line("COMBAT|Warding: no 6+ ignore, X was charged from within 6in")).is_false()
