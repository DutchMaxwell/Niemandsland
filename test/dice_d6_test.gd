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
