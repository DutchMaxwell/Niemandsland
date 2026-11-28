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
	var hero_min: float = TableSizeDialog.RAIL_HERO_ASPECT if dialog._rail_body.visible else 2.2   # the rail card: sheet 03's 1.6
	assert_float(hero_aspect).override_failure_message("%s: preview %.2f:1" % [window, hero_aspect]).is_between(hero_min - 0.01, 2.9)
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


## Step 84 (sheet 03): from 900 px the header carries the breadcrumb and a bordered "Back to main menu" with Esc, the
## title block reads "NEW TABLE" / "Prepare your table." at 44 px and stands with step 01 in the left column, so the rail
## card starts level with it. At 1280x720 the header and title stay as they were (red before: none of it).
func test_from_900_px_the_header_and_title_are_the_sheets() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	var texts: Array = dialog.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).is_visible_in_tree()).map(func(l: Node) -> String: return (l as Label).text.strip_edges())
	assert_array(texts).contains(["MAIN MENU  /  PREPARE YOUR TABLE", "NEW TABLE", "Esc"])
	var wide := dialog.find_child("BackWide", true, false) as Button
	assert_bool(wide != null and wide.is_visible_in_tree()).override_failure_message("no bordered way back").is_true()
	assert_bool(dialog._back.is_visible_in_tree()).is_false()
	var title := dialog.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text == "Prepare your table.")[0] as Label
	assert_int(title.get_theme_font_size("font_size")).is_equal(44)
	assert_bool(dialog._left.is_ancestor_of(title)).override_failure_message("the title is not in the left column").is_true()
	var card := dialog.find_child("RailCard", true, false) as Control
	assert_float(absf(card.get_global_rect().position.y - title.get_global_rect().position.y)).is_less(60.0)
	var small := await _open(Vector2i(1280, 720))
	assert_bool(small._back.is_visible_in_tree()).is_true()
	var small_title := small.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text == "Prepare your table.")[0] as Label
	assert_bool(small._left.is_ancestor_of(small_title)).is_false()


## The inner pages (who, layout) keep the title block over them at 1080p although state one carries it in its left
## column (step 84).
func test_the_inner_pages_keep_the_title_at_1080p() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	var dialog: TableSizeDialog = auto_free(TableSizeDialog.new())
	dialog.layout_step = true
	add_child(dialog)
	for _i in 3:
		await get_tree().process_frame
	dialog._show_state("who")
	await get_tree().process_frame
	assert_bool(dialog._intro.is_visible_in_tree()).override_failure_message("the who page lost the title").is_true()
	# ...under the header and at the top, not pushed to the foot of the page (the 28.11. capture, red before)
	assert_int(dialog._intro.get_index()).is_greater(dialog._header.get_index())
	assert_float(dialog._intro.get_global_rect().position.y).is_less(200.0)
	dialog._show_state("")
	await get_tree().process_frame
	assert_bool(dialog._left.is_ancestor_of(dialog._intro)).is_true()


## Step 84 (type, sheet 03): from 900 px each step heading is 22 px with its number in mono and its hint at the right in
## 15 px; the size cards read caption 14 px mono upper case, value 20 px, sub-line 15 px. At 720 the hints stay hidden
## (red before: 17 px headings, the hints as lines under the cards).
func test_from_900_px_the_step_headings_carry_their_hints() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	var shown := func(d: Node, text: String) -> Array: return d.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text == text and (l as Label).is_visible_in_tree())
	for hint: String in ["The biome defines the visual style. Terrain stays yours to place.", "Table size is fixed once you create it."]:
		assert_int(shown.call(dialog, hint).size()).override_failure_message(hint).is_equal(1)
	var name_label: Array = shown.call(dialog, "Choose a biome")
	assert_int(name_label.size()).is_equal(1)
	if name_label.size() == 1:
		assert_int((name_label[0] as Label).get_theme_font_size("font_size")).is_equal(22)
	var caption: Array = shown.call(dialog, "STANDARD")
	assert_int(caption.size()).override_failure_message("no size caption in upper case").is_equal(1)
	var small := await _open(Vector2i(1280, 720))
	assert_int(shown.call(small, "The biome defines the visual style. Terrain stays yours to place.").size()).is_equal(0)


## Step 84 (system cards, sheet 03): from 900 px a system card is 136 px with the family eyebrow, the name in two lines
## at 20 px, a BATTLE / SKIRMISH chip with the board in mono and a gold tick on the chosen one. At 720 the cards stay
## one line each (red before: a one-line strip card at every size).
func test_from_900_px_the_system_cards_are_the_sheets() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	var card := dialog._system_buttons[dialog.selected_system] as Control
	assert_float(card.size.y).is_greater_equal(130.0)
	var texts: Array = card.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).is_visible_in_tree()).map(func(l: Node) -> String: return (l as Label).text)
	assert_array(texts).contains(["GRIMDARK", "BATTLE", "6 × 4 FT"])
	var ticks: Array = card.find_children("*", "TextureRect", true, false).filter(
		func(t: Node) -> bool: return (t as Control).is_visible_in_tree())
	assert_int(ticks.size()).override_failure_message("no tick on the chosen card").is_equal(1)
	var other := dialog._system_buttons["aof"] as Control
	assert_int(other.find_children("*", "TextureRect", true, false).filter(
		func(t: Node) -> bool: return (t as Control).is_visible_in_tree()).size()).is_equal(0)
	var small := await _open(Vector2i(1280, 720))
	var small_texts: Array = (small._system_buttons["gf"] as Node).find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).is_visible_in_tree()).map(func(l: Node) -> String: return (l as Label).text)
	assert_array(small_texts).not_contains(["GRIMDARK"])


## Sheets 03/03b: in the rail card "Create table" is 18 px semibold at the left with its Enter cap (red before: 14 px
## regular, centred, an arrow glyph).
func test_the_rail_cards_create_table_reads_as_drawn() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	assert_str(dialog._create.text).is_equal("Create table")
	assert_int(dialog._create.get_theme_font_size("font_size")).is_equal(18)
	var cap := dialog._create.get_node_or_null("EnterCap") as Control
	assert_bool(cap != null and cap.visible).override_failure_message("no Enter cap").is_true()
	var small := await _open(Vector2i(1280, 720))
	assert_bool((small._create.get_node("EnterCap") as Control).visible).is_false()



## At 1280x720 the who page keeps the setup's title on top as well (the 28.11. capture: it stood over the key legend).
func test_the_who_page_keeps_the_title_on_top_at_720p() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var dialog: TableSizeDialog = auto_free(TableSizeDialog.new())
	dialog.layout_step = true
	add_child(dialog)
	for _i in 3:
		await get_tree().process_frame
	dialog._show_state("who")
	for _i in 3:
		await get_tree().process_frame
	assert_float(dialog._intro.get_global_rect().position.y).is_less(160.0)


## Gap review 28.11. (sheets 02-04): every Enter cap sits beside its word, centred on the button - one placement in
## HouseStyle - not low in the corner (red before: the cap's top at the button's middle, about 12 px low).
func test_the_enter_cap_is_centred_on_its_button() -> void:
	var dialog := await _open(Vector2i(1920, 1080))
	await get_tree().process_frame
	var cap := dialog._create.get_node_or_null("EnterCap") as Control
	assert_object(cap).is_not_null()
	if cap == null:
		return
	var low := cap.get_global_rect().get_center().y - dialog._create.get_global_rect().get_center().y
	assert_float(absf(low)).override_failure_message("the cap stands %d px off the button's middle" % int(low)).is_less_equal(1.0)
