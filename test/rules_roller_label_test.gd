extends GdUnitTestSuite
## Rules plan 2.5 "Names, not You": the deterministic core of the roller label. An AI unit is named
## by its unit; a human is "You" only while an AI slot is designated (solo vs NACHTMAHR); on a table
## with no designated AI slot (hotseat) or online, the unit is named by its player/slot instead.

const MainScript := preload("res://scripts/main.gd")


func test_ai_unit_keeps_the_ai_label() -> void:
	assert_str(MainScript.roller_label_for("Alpha Squad", true, false, false, false, "", "P1 (Alpha)")) \
		.is_equal("AI (Alpha Squad)")


func test_solo_human_is_you() -> void:
	# AI slot designated (solo vs NACHTMAHR): the human side stays "You" — byte-identical.
	assert_str(MainScript.roller_label_for("Alpha Squad", false, true, true, false, "", "P1 (Alpha)")) \
		.is_equal("You")


func test_hotseat_p1_names_the_player() -> void:
	# No AI slot designated, no session: both players share this machine, so name the slot.
	assert_str(MainScript.roller_label_for("Alpha Squad", false, false, true, false, "", "P1 (Alpha)")) \
		.is_equal("P1 (Alpha)")


func test_hotseat_p2_names_the_player() -> void:
	assert_str(MainScript.roller_label_for("Bravo Squad", false, false, true, false, "", "P2 (Bravo)")) \
		.is_equal("P2 (Bravo)")


func test_online_remote_unit_uses_the_peer_display_name() -> void:
	assert_str(MainScript.roller_label_for("Bravo Squad", false, false, false, true, "Bob", "P2 (Bravo)")) \
		.is_equal("Bob")


func test_online_without_a_name_falls_back_to_the_slot() -> void:
	assert_str(MainScript.roller_label_for("Bravo Squad", false, false, false, true, "", "P2 (Bravo)")) \
		.is_equal("P2 (Bravo)")