extends GdUnitTestSuite
## The table chooser scales with the window like the rest of the UI and keeps the 1080p layout's
## proportions. On a 3440x1440 ultrawide it used to stay at 1:1 pixels and stretch across the full
## width: biome cards became 4.4:1 strips, the preview a 4.6:1 band, the lower half of the screen empty.
## It also fills the window height at every aspect (16:10 used to end at ~55-70 % of the height).

var _original_size: Vector2i


func before() -> void:
	_original_size = get_tree().root.size


func after_test() -> void:
	get_tree().root.size = _original_size


func _open(window: Vector2i) -> TableSizeDialog:
	get_tree().root.size = window
	var dialog: TableSizeDialog = auto_free(TableSizeDialog.new())
	add_child(dialog)
	for _i in 3:
		await get_tree().process_frame
	return dialog


## Proportions, vertical fit and a centred page. Returns the chooser's layout height (its logical units).
func _assert_layout(window: Vector2i) -> float:
	var dialog := await _open(window)
	var area := dialog.get_visible_rect().size
	var card: Control = dialog._biome_buttons.values()[0]
	var card_aspect := card.size.x / card.size.y
	var hero_aspect := dialog._hero.size.x / dialog._hero.size.y
	if dialog._grid.columns == 6:   # one row of tall cards (step 83, sheet 03): the picture is at least 150 px high
		assert_float(dialog._cards[0].size.y).override_failure_message("%s: picture %d px" % [window, int(dialog._cards[0].size.y)]).is_greater_equal(150.0)
	else:
		assert_float(card_aspect).override_failure_message("%s: biome card %.2f:1" % [window, card_aspect]).is_between(2.0, 2.8)
	assert_float(hero_aspect).override_failure_message("%s: preview %.2f:1" % [window, hero_aspect]).is_between(2.2, 2.9)
	assert_float(dialog._page.get_combined_minimum_size().y) \
		.override_failure_message("%s: the page needs scrolling" % window).is_less_equal(dialog._scroll.size.y)
	assert_bool(Rect2(Vector2.ZERO, area).encloses(dialog._create.get_global_rect())) \
		.override_failure_message("%s: Create is outside the window" % window).is_true()
	var page := dialog._page.get_global_rect()
	assert_float(absf(page.position.x - (area.x - page.end.x))) \
		.override_failure_message("%s: the page is not centred" % window).is_less_equal(2.0)
	# The page fills the window height (maintainer 23.09.: "everything happens in the upper half")...
	var top := dialog._scroll.get_global_rect().position.y
	var usable := dialog._scroll.size.y
	var bottom := (dialog._create.get_global_rect().end.y - top) / usable
	assert_float(bottom).override_failure_message("%s: the page ends at %d %% of the height" % [window, int(bottom * 100.0)]) \
		.is_greater_equal(0.9)
	# ...with the height in the content, not in one empty band between two sections.
	var prev := top
	for child in dialog._page.get_children():
		if child is Control and child.visible:
			var gap: float = (child as Control).get_global_rect().position.y - prev
			assert_float(gap).override_failure_message("%s: a %d px gap on a %d px page" % [window, int(gap), int(usable)]) \
				.is_less_equal(usable * 0.08)
			prev = (child as Control).get_global_rect().end.y
	# ...and not in a hole inside the left column beside a grown preview.
	var hole := 0.0
	for air: Control in dialog._left_air:
		hole = maxf(hole, air.size.y if air.visible else 0.0)
	assert_float(hole).override_failure_message("%s: a %d px hole in the left column" % [window, int(hole)]) \
		.is_less_equal(usable * 0.08)
	return area.y


func test_ultrawide_3440x1440_scales_up_and_keeps_the_proportions() -> void:
	var height := await _assert_layout(Vector2i(3440, 1440))
	assert_float(height).override_failure_message("the chooser did not grow with the window").is_equal_approx(1080.0, 1.0)


func test_2560x1440_scales_up_and_keeps_the_proportions() -> void:
	var height := await _assert_layout(Vector2i(2560, 1440))
	assert_float(height).override_failure_message("the chooser did not grow with the window").is_equal_approx(1080.0, 1.0)


func test_2546x1583_the_maintainers_16_10_window_fills_the_height() -> void:
	await _assert_layout(Vector2i(2546, 1583))


func test_1920x1200_fills_the_height() -> void:
	await _assert_layout(Vector2i(1920, 1200))


func test_1920x1080_is_the_reference_layout() -> void:
	await _assert_layout(Vector2i(1920, 1080))


func test_1366x768_fills_the_height() -> void:
	await _assert_layout(Vector2i(1366, 768))


## The Custom inputs (two more fields) fit too: the cards make room instead of the page scrolling.
func test_custom_inputs_fit_at_1280x720() -> void:
	var dialog := await _open(Vector2i(1280, 720))
	dialog._select_size("custom")
	for _i in 3:
		await get_tree().process_frame
	assert_float(dialog._page.get_combined_minimum_size().y) \
		.override_failure_message("Custom needs scrolling: page needs %d px, the scroll gives %d px" % [int(dialog._page.get_combined_minimum_size().y), int(dialog._scroll.size.y)]) \
		.is_less_equal(dialog._scroll.size.y)
	var card: Control = dialog._biome_buttons.values()[0]
	assert_float(card.size.x / card.size.y).is_between(2.0, 2.8)


func test_1280x720_never_shrinks_below_one_to_one_pixels_and_fits() -> void:
	var height := await _assert_layout(Vector2i(1280, 720))
	assert_float(height).is_equal_approx(720.0, 1.0)


## Row 04 keeps its "Change" inside the row at 1280x720 (gap review 27.11.: it ran 16 px out of the row's right edge;
## the opponent's name now gives way, cut with an ellipsis).
func test_row_04_keeps_change_inside_at_1280x720() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var dialog: TableSizeDialog = auto_free(TableSizeDialog.new())
	dialog.layout_step = true   # the menu's setup: rows 04 and 05
	add_child(dialog)
	dialog.opponent.set_system("gf")   # the longest name the row shows: NACHTMAHR with a faction and points
	dialog.opponent.set_manifest({"alien_hives": {"name": "Alien Hives", "lists": [{"points": 3000, "file": "a.json"}]}})
	dialog.opponent.choose_who("solo")
	for _i in 3:
		await get_tree().process_frame
	var row := dialog.find_child("OpponentRow", true, false) as Control
	var change: Control = null
	for l: Node in row.find_children("*", "Label", true, false) if row != null else []:
		if (l as Label).text.strip_edges() == "Change":
			change = l as Control
	assert_object(change).override_failure_message("no Change label of row 04").is_not_null()
	if change == null:
		return
	assert_float(change.get_global_rect().end.x).override_failure_message("Change ends at %d, the row at %d" % [
		int(change.get_global_rect().end.x), int(row.get_global_rect().end.x)]).is_less_equal(row.get_global_rect().end.x)


## Step 82 (sheet 03): from 900 px of window height the right column is one framed rail card - picture, footprint, the
## summary as rows and Create table as its last row, the columns 1.9 : 1; the footer keeps the key legend only. At
## 1280x720 the compact form stays (red before: an unframed picture and a page-wide footer with summary and Create).
func test_from_900_px_the_right_column_is_the_rail_card() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	var card := dialog.find_child("RailCard", true, false) as PanelContainer
	assert_object(card).override_failure_message("no rail card").is_not_null()
	if card == null:
		return
	assert_bool(card.get_theme_stylebox("panel") is StyleBoxFlat).override_failure_message("the card has no frame").is_true()
	assert_bool(card.is_ancestor_of(dialog._create)).override_failure_message("Create table is not in the card").is_true()
	assert_bool(card.is_ancestor_of(dialog._summary.System)).override_failure_message("the summary is not in the card").is_true()
	assert_float(dialog._create.size.x).is_greater(card.size.x - 60.0)
	assert_float(dialog._summary.System.get_global_rect().position.y).is_less(dialog._summary.Biome.get_global_rect().position.y)
	var left: Control = dialog._left
	assert_float(left.size.x / card.size.x).is_between(1.7, 2.1)
	assert_object(dialog.find_child("KeyLegend", true, false)).is_not_null()
	var small := await _open(Vector2i(1280, 720))
	assert_bool(small.find_child("RailCard", true, false).is_ancestor_of(small._create)) \
		.override_failure_message("the 720 page lost its footer button").is_false()


## Step 83 (sheet 03): with the rail card's wide left column the six biomes stand in one row, each picture at least
## 150 px high over a 44 px name band in 16 px; the chosen card has a 2 px gold rim. 1280x720 keeps its grid (red
## before: a 3 x 2 grid of flat cards).
func test_the_six_biomes_stand_in_one_row_at_1080p() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	assert_int(dialog._grid.columns).is_equal(6)
	var tops: Array = dialog._biome_buttons.values().map(func(b: Control) -> int: return int(b.get_global_rect().position.y))
	assert_int(tops.max() - tops.min()).override_failure_message("the cards are not one row").is_less_equal(1)
	assert_float(dialog._cards[0].size.y).is_greater_equal(150.0)
	var chosen := dialog._biome_buttons[dialog.selected_biome] as Button
	assert_int((chosen.get_theme_stylebox("normal") as StyleBoxFlat).border_width_top).is_equal(2)
	var small := await _open(Vector2i(1280, 720))
	assert_int(small._grid.columns).is_less_equal(3)
