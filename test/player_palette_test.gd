extends GdUnitTestSuite
## PlayerPalette is the single source of per-player colour, shared by presence (avatars/cursors) and army
## bases so a player's head/cursor always matches their army — including at slot >= 5, where the old army
## table returned grey while presence wrapped (bus 036).


func test_slot_one_is_host_colour() -> void:
	assert_object(PlayerPalette.color_for_slot(1)).is_equal(PlayerPalette.PALETTE[0])


func test_wraps_past_palette_length() -> void:
	# Slots never recycle and climb monotonically across reconnects, so the palette must wrap.
	var n: int = PlayerPalette.PALETTE.size()
	assert_object(PlayerPalette.color_for_slot(n + 1)).is_equal(PlayerPalette.color_for_slot(1))
	assert_object(PlayerPalette.color_for_slot(n + 2)).is_equal(PlayerPalette.color_for_slot(2))


func test_unassigned_slot_resolves_to_one() -> void:
	assert_object(PlayerPalette.color_for_slot(0)).is_equal(PlayerPalette.color_for_slot(1))
	assert_object(PlayerPalette.color_for_slot(-3)).is_equal(PlayerPalette.color_for_slot(1))


func test_army_base_matches_presence_at_every_slot() -> void:
	# The core bug: at slot >= 5 the army fell back to grey while the avatar/cursor wrapped.
	for slot in range(1, 9):
		assert_object(OPRArmyManager.army_color(slot)).is_equal(PlayerPalette.color_for_slot(slot))


func test_army_colour_is_neutral_for_unowned() -> void:
	# player_id 0 (unowned) keeps the caller's neutral, NOT a wrapped slot-1 colour.
	assert_object(OPRArmyManager.army_color(0, Color.GRAY)).is_equal(Color.GRAY)
