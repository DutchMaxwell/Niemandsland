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
