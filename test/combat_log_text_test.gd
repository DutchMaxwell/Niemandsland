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
	assert_str(MainScript.blast_log_text(3, 4, 4, 1)) \
		.is_equal("Blast(3): 4 hits ×1 (capped by 1 model in target) → 4 hits")
	assert_str(MainScript.blast_log_text(3, 2, 4, 2)) \
		.is_equal("Blast(3): 2 hits ×2 (capped by 2 models in target) → 4 hits")


func test_save_threshold_within_d6_keeps_the_old_format() -> void:
	assert_str(MainScript.save_threshold_text(4, 1)).is_equal("5+ (Def 4+, AP 1)")
	assert_str(MainScript.save_threshold_text(5, 0)).is_equal("5+")


func test_save_threshold_past_six_names_the_natural_six() -> void:
	assert_str(MainScript.save_threshold_text(6, 1)) \
		.is_equal("6 only (Def 6+, AP 1 — a natural 6 always saves)")
	assert_str(MainScript.save_threshold_text(6, 4)) \
		.is_equal("6 only (Def 6+, AP 4 — a natural 6 always saves)")
