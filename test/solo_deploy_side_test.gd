extends GdUnitTestSuite
## #315 — the roll-off side pick is RELATIVE to what the table is drawing. The
## flip state persists across games in a session; the old absolute mapping
## (swap == ai_neg_z) sent the player into the exact zone he clicked away from
## whenever the previous game left the colours flipped. Truth table, all four
## combinations: the AI always ends on the opposite edge of the human's CHOICE,
## and the drawn-colour flip always agrees (flipped == human on +Z).


func test_first_game_default_keep_and_swap() -> void:
	# Human drawn on -Z (fresh overlay): keep -> AI on +Z, colours unflipped.
	var keep: Dictionary = SoloController.deploy_side_resolve(true, false)
	assert_bool(bool(keep["ai_neg_z"])).is_false()
	assert_bool(bool(keep["flipped"])).is_false()
	# Swap -> human crosses to +Z, AI takes -Z, colours flip.
	var swap: Dictionary = SoloController.deploy_side_resolve(true, true)
	assert_bool(bool(swap["ai_neg_z"])).is_true()
	assert_bool(bool(swap["flipped"])).is_true()


func test_persisted_flip_second_game_keep_and_swap() -> void:
	# Previous game left the colours flipped: human is DRAWN on +Z now.
	# Keep must leave him there -> AI on -Z (the old absolute code sent the AI
	# into the drawn human band here).
	var keep: Dictionary = SoloController.deploy_side_resolve(false, false)
	assert_bool(bool(keep["ai_neg_z"])).is_true()
	assert_bool(bool(keep["flipped"])).is_true()
	# Swap must bring him back to -Z -> AI on +Z, colours unflip.
	var swap: Dictionary = SoloController.deploy_side_resolve(false, true)
	assert_bool(bool(swap["ai_neg_z"])).is_false()
	assert_bool(bool(swap["flipped"])).is_false()
