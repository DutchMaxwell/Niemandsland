extends GdUnitTestSuite
## Tests DiceD6 up-face detection and face placement (no physics simulation needed).


func _die() -> DiceD6:
	var d := DiceD6.new()
	add_child(d)
	return auto_free(d)


func test_opposite_faces_sum_to_seven() -> void:
	for value: int in DiceD6.FACE_NORMALS:
		var normal: Vector3 = DiceD6.FACE_NORMALS[value]
		var opposite: int = -1
		for other: int in DiceD6.FACE_NORMALS:
			if DiceD6.FACE_NORMALS[other].is_equal_approx(-normal):
				opposite = other
		assert_int(value + opposite).is_equal(7)


func test_identity_orientation_shows_one() -> void:
	var d := _die()
	d.global_transform = Transform3D(Basis(), Vector3.ZERO)
	assert_int(d.top_face()).is_equal(1)


func test_flipped_orientation_shows_six() -> void:
	var d := _die()
	d.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)
	assert_int(d.top_face()).is_equal(6)


func test_set_top_face_round_trips_for_all_values() -> void:
	var d := _die()
	for value: int in range(1, 7):
		d.set_top_face(value)
		assert_int(d.top_face()).is_equal(value)


func test_settle_to_face_lands_value_up_and_freezes() -> void:
	var d := _die()
	# Arbitrary tilt + elevated position, as if mid-teeter.
	d.global_transform = Transform3D(Basis(Vector3(1, 1, 1).normalized(), 0.7), Vector3(2.0, 5.0, 3.0))
	d.settle_to_face(4)
	assert_int(d.top_face()).is_equal(4)
	assert_bool(d.freeze).is_true()
	assert_float(d.global_position.y).is_equal_approx(d.size * 0.5, 0.01)


func test_settle_to_face_handles_antiparallel_face_down() -> void:
	var d := _die()
	# Identity orientation: face 1 is up, so face 6 points straight DOWN — the
	# antiparallel degenerate case where cross(UP) is zero. Must still flip face 6 up.
	d.global_transform = Transform3D(Basis(), Vector3(0.0, 5.0, 0.0))
	d.settle_to_face(6)
	assert_int(d.top_face()).is_equal(6)
	assert_bool(d.freeze).is_true()
	assert_float(d.global_position.y).is_equal_approx(d.size * 0.5, 0.01)


func test_color_tag_starts_untagged() -> void:
	var d := _die()
	assert_int(d.color_tag).is_equal(DiceD6.DEFAULT_COLOR_TAG)


func test_cycle_color_tag_wraps_through_all_tags_and_back() -> void:
	var d := _die()
	# default -> 1 -> 2 -> 3 -> 4 -> default
	for expected: int in range(1, DiceD6.TAG_COLORS.size() + 1):
		d.cycle_color_tag()
		assert_int(d.color_tag).is_equal(expected)
	d.cycle_color_tag()
	assert_int(d.color_tag).is_equal(DiceD6.DEFAULT_COLOR_TAG)


func test_set_color_tag_clamps_out_of_range_to_default() -> void:
	var d := _die()
	d.set_color_tag(DiceD6.TAG_COLORS.size() + 5)
	assert_int(d.color_tag).is_equal(DiceD6.DEFAULT_COLOR_TAG)
	d.set_color_tag(-1)
	assert_int(d.color_tag).is_equal(DiceD6.DEFAULT_COLOR_TAG)


func test_clear_color_tag_restores_default() -> void:
	var d := _die()
	d.set_color_tag(2)
	d.clear_color_tag()
	assert_int(d.color_tag).is_equal(DiceD6.DEFAULT_COLOR_TAG)


func test_body_color_for_tag_maps_tags_to_palette() -> void:
	assert_object(DiceD6.body_color_for_tag(0)).is_equal(DiceD6.BODY_COLOR)
	for tag: int in range(1, DiceD6.TAG_COLORS.size() + 1):
		assert_object(DiceD6.body_color_for_tag(tag)).is_equal(DiceD6.TAG_COLORS[tag - 1])
	# Out-of-range falls back to the default body colour.
	assert_object(DiceD6.body_color_for_tag(99)).is_equal(DiceD6.BODY_COLOR)


# ===== DiceTray colour-tag sync surface =====
# The composition/tag accessors the MP mirror uses (broadcast on the local side, applied on
# the remote side). The tray spawns its dice in _ready (a SubViewport), so add_child + one
# frame is enough; no physics needed here.

func _tray(count: int) -> DiceTray:
	var t := DiceTray.new()
	t.dice_count = count
	add_child(t)
	return auto_free(t)


func test_tray_get_color_tags_defaults_untagged() -> void:
	var t := _tray(4)
	await get_tree().process_frame
	var tags := t.get_color_tags()
	assert_int(tags.size()).is_equal(4)
	for tag: int in tags:
		assert_int(tag).is_equal(DiceD6.DEFAULT_COLOR_TAG)


func test_tray_apply_color_tags_round_trips() -> void:
	var t := _tray(4)
	await get_tree().process_frame
	t.apply_color_tags([1, 0, 3, 2])
	assert_array(t.get_color_tags()).is_equal([1, 0, 3, 2])


func test_tray_apply_color_tags_tolerates_short_array() -> void:
	var t := _tray(4)
	await get_tree().process_frame
	t.apply_color_tags([2, 4])  # only the first two dice are coloured
	assert_array(t.get_color_tags()).is_equal([2, 4, 0, 0])


func test_tray_set_die_color_tag_addresses_one_die() -> void:
	var t := _tray(3)
	await get_tree().process_frame
	t.set_die_color_tag(1, 4)
	assert_array(t.get_color_tags()).is_equal([0, 4, 0])
	# Out-of-range index is a no-op (no crash, no change).
	t.set_die_color_tag(99, 2)
	assert_array(t.get_color_tags()).is_equal([0, 4, 0])


func test_tray_show_faces_applies_tags() -> void:
	var t := _tray(3)
	await get_tree().process_frame
	t.show_faces([5, 3, 1], [2, 0, 4])
	assert_array(t.get_color_tags()).is_equal([2, 0, 4])


func test_tray_roll_preserves_tags_through_the_toss() -> void:
	var t := _tray(3)
	await get_tree().process_frame
	t.apply_color_tags([1, 2, 3])
	t.roll()  # respawns the dice for the physics toss — tags must carry onto the new dice
	assert_array(t.get_color_tags()).is_equal([1, 2, 3])
