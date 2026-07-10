extends GdUnitTestSuite
## Unit-card dock strip layout sanity. The W5 tutorial softlock traced to an EMPTY strip: a .nml
## board load never rebuilt the dock, so _layout_fan() early-returned and _strip_panel kept its
## PanelContainer auto-width (~0) pinned at x=0 — a sliver at the far-left edge that the coach
## spotlight then pointed at. These pin the invariant the fix restores: once the strip holds cards,
## _layout_fan sizes it to at least one card wide and CENTRES it horizontally inside the viewport —
## at 16:9, 16:9-QHD and a smaller windowed size (the maintainer runs windowed, not fullscreen).

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(1600, 900),
]


## A UnitDock live under a SubViewport of the given size (so get_viewport_rect() is deterministic),
## with `card_count` placeholder cards in the fan holder. army_manager stays null (guarded).
func _dock_in_viewport(size: Vector2i, card_count: int) -> UnitDock:
	var sub := auto_free(SubViewport.new()) as SubViewport
	sub.size = size
	add_child(sub)
	var dock := UnitDock.new()
	sub.add_child(dock)           # _ready builds the strip; freed together with the SubViewport
	await get_tree().process_frame
	for _i in card_count:
		dock._strip.add_child(Control.new())   # _layout_fan sizes the panel from child COUNT
	dock._layout_fan()
	return dock


func test_strip_is_centred_and_inside_viewport_at_common_sizes() -> void:
	for size in TEST_SIZES:
		var dock := await _dock_in_viewport(size, 4)
		var panel := dock._strip_panel
		var vp_w := float(size.x)
		# At least one full card wide — never the collapsed sliver.
		assert_float(panel.size.x).is_greater_equal(float(UnitDock.CARD_W))
		# Horizontally inside the viewport — never pinned to the left edge, never overflowing right.
		assert_float(panel.position.x).is_greater(0.0)
		assert_float(panel.position.x + panel.size.x).is_less_equal(vp_w + 1.0)
		# Centred on the screen mid-line.
		var center := panel.position.x + panel.size.x * 0.5
		assert_float(center).is_equal_approx(vp_w * 0.5, 1.0)


func test_many_cards_still_fit_inside_the_viewport() -> void:
	# The fan tightens its overlap as cards pile up; even a big army must not spill off-screen.
	for size in TEST_SIZES:
		var dock := await _dock_in_viewport(size, 16)
		var panel := dock._strip_panel
		var vp_w := float(size.x)
		assert_float(panel.position.x).is_greater_equal(0.0)
		assert_float(panel.position.x + panel.size.x).is_less_equal(vp_w + 1.0)


func test_strip_rect_reports_the_laid_out_geometry() -> void:
	# strip_rect() is the exact seam the tutorial coach spotlight reads — it must reflect the
	# centred, non-degenerate panel, not a zero-width rect at the origin.
	var dock := await _dock_in_viewport(Vector2i(1920, 1080), 4)
	var rect := dock.strip_rect()
	assert_float(rect.size.x).is_greater_equal(float(UnitDock.CARD_W))
	assert_float(rect.position.x).is_greater(0.0)
	assert_float(rect.position.x + rect.size.x).is_less_equal(1921.0)
