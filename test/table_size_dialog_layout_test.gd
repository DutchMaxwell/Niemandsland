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
		.override_failure_message("Custom needs scrolling").is_less_equal(dialog._scroll.size.y)
	var card: Control = dialog._biome_buttons.values()[0]
	assert_float(card.size.x / card.size.y).is_between(2.0, 2.8)


func test_1280x720_never_shrinks_below_one_to_one_pixels_and_fits() -> void:
	var height := await _assert_layout(Vector2i(1280, 720))
	assert_float(height).is_equal_approx(720.0, 1.0)
