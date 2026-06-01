extends GdUnitTestSuite
## Tests the DieFaceIcon pip layout and face clamping.


func test_pip_count_matches_face_value() -> void:
	# A standard d6 shows exactly N pips for face N.
	for face: int in range(1, 7):
		assert_int(DieFaceIcon.PIP_LAYOUT[face].size()).is_equal(face)


func test_every_face_has_a_layout() -> void:
	for face: int in range(1, 7):
		assert_bool(DieFaceIcon.PIP_LAYOUT.has(face)).is_true()


func test_face_is_clamped_to_valid_range() -> void:
	var icon: DieFaceIcon = DieFaceIcon.new()
	auto_free(icon)
	icon.face = 9
	assert_int(icon.face).is_equal(6)
	icon.face = 0
	assert_int(icon.face).is_equal(1)
	icon.face = 4
	assert_int(icon.face).is_equal(4)
