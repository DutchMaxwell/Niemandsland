extends GdUnitTestSuite
## The table chooser scales with the window like the rest of the UI and keeps the 1080p layout's
## proportions. On a 3440x1440 ultrawide it used to stay at 1:1 pixels and stretch across the full
## width: biome cards became 4.4:1 strips, the preview a 4.6:1 band, the lower half of the screen empty.

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
	return area.y


func test_ultrawide_3440x1440_scales_up_and_keeps_the_proportions() -> void:
	var height := await _assert_layout(Vector2i(3440, 1440))
	assert_float(height).override_failure_message("the chooser did not grow with the window").is_equal_approx(1080.0, 1.0)


func test_2560x1440_scales_up_and_keeps_the_proportions() -> void:
	var height := await _assert_layout(Vector2i(2560, 1440))
	assert_float(height).override_failure_message("the chooser did not grow with the window").is_equal_approx(1080.0, 1.0)


func test_1920x1080_is_the_reference_layout() -> void:
	await _assert_layout(Vector2i(1920, 1080))


func test_1280x720_never_shrinks_below_one_to_one_pixels_and_fits() -> void:
	var height := await _assert_layout(Vector2i(1280, 720))
	assert_float(height).is_equal_approx(720.0, 1.0)
