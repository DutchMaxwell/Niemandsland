extends GdUnitTestSuite
## The round-advance texts must NAME the round they move onto (community request,
## GitHub #161): "Next Round → 3" while Round 2 is played — the old "(current)"
## suffix read as the target round. A solo match's final round ends the game
## instead, and the same control must say so.

const MainScript := preload("res://scripts/main.gd")


func test_button_label_names_the_target_round() -> void:
	assert_str(MainScript.next_round_button_label(1, false)).is_equal("Next Round → 2")
	assert_str(MainScript.next_round_button_label(3, false)).is_equal("Next Round → 4")


func test_final_solo_round_announces_the_game_end() -> void:
	assert_str(MainScript.next_round_button_label(4, true)).is_equal("End Round 4")
	assert_str(MainScript.next_round_confirm_body(4, true)).contains("the game ends")


func test_confirm_body_names_the_target_round() -> void:
	assert_str(MainScript.next_round_confirm_body(2, false)).contains("Round 3")
	assert_str(MainScript.next_round_confirm_body(2, false)).not_contains("Round 2?")
