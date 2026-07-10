extends GdUnitTestSuite
## Softlock guard for the tutorial coach mark: the input mask that absorbs clicks OUTSIDE the
## spotlight must NEVER engage when the target rect is degenerate (empty / zero-size / off-screen).
## Otherwise the whole screen is masked with no reachable hole and the player is trapped — the
## exact class of bug behind the W5 "unit-card dock collapsed at the left edge" field report.
## A usable, on-screen target still masks as before (hole falls through, outside is absorbed).

const CoachMark := preload("res://scripts/tutorial_coach_mark.gd")


## A coach overlay live in the tree (so _ready built the dim layer + card) and one frame settled.
func _new_coach() -> TutorialCoachMark:
	var coach := auto_free(CoachMark.new()) as TutorialCoachMark
	add_child(coach)
	await get_tree().process_frame
	return coach


func _viewport_size(coach: TutorialCoachMark) -> Vector2:
	return coach._dim.get_viewport_rect().size


## ===== Degenerate targets must NOT mask =====

func test_empty_rect_target_disables_the_mask() -> void:
	var coach := await _new_coach()
	coach.show_step("do a thing", Rect2(), true)
	assert_bool(coach._target_usable).is_false()
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# The dim layer absorbs nothing anywhere -> every click falls through to the game.
	assert_bool(coach._dim._has_point(Vector2(10, 10))).is_false()
	assert_bool(coach._dim._has_point(_viewport_size(coach) * 0.5)).is_false()
	# Overlay still up: instruction + the always-visible escape hatches remain live.
	assert_bool(coach.visible).is_true()
	assert_bool(coach._skip_lesson_btn.visible).is_true()
	assert_bool(coach._end_btn.visible).is_true()


func test_zero_size_target_disables_the_mask() -> void:
	var coach := await _new_coach()
	# A zero-size raw rect would pad up to ~28 px; usability is judged on the RAW rect, so it is
	# still degenerate and must not mask.
	coach.show_step("do a thing", Rect2(200, 200, 0, 0), true)
	assert_bool(coach._target_usable).is_false()
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_offscreen_target_disables_the_mask() -> void:
	var coach := await _new_coach()
	coach.show_step("do a thing", Rect2(-10000, -10000, 120, 120), true)
	assert_bool(coach._target_usable).is_false()
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


## ===== A real, on-screen target masks exactly as before =====

func test_usable_target_masks_outside_and_falls_through_inside() -> void:
	var coach := await _new_coach()
	var rect := Rect2(60, 60, 300, 200)   # comfortably inside the default headless viewport
	coach.show_step("click here", rect, true)
	assert_bool(coach._target_usable).is_true()
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# Inside the (padded) hole: not absorbed -> click reaches the game beneath.
	assert_bool(coach._dim._has_point(rect.get_center())).is_false()
	# Far outside the hole but on-screen: absorbed -> the soft mask does its job.
	assert_bool(coach._dim._has_point(Vector2(rect.end.x + 120.0, rect.end.y + 120.0))).is_true()


func test_usable_target_with_mask_false_never_masks() -> void:
	var coach := await _new_coach()
	coach.show_step("watch this", Rect2(60, 60, 300, 200), false)
	assert_bool(coach._target_usable).is_true()
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


## ===== A target that goes degenerate while active drops the mask (resize / relayout) =====

func test_target_becoming_degenerate_drops_the_mask() -> void:
	var coach := await _new_coach()
	coach.show_step("click here", Rect2(60, 60, 300, 200), true)
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# The director re-feeds the rect every frame; if the target collapses (e.g. dock relaid-out
	# off-screen), the mask must release rather than strand the player.
	coach.set_target_rect(Rect2(-9000, -9000, 4, 4))
	assert_bool(coach._target_usable).is_false()
	assert_int(coach._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
