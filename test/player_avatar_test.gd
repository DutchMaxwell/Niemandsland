extends GdUnitTestSuite
## PlayerAvatar default resting position: a remote head rests at its player's table edge
## (by slot) so it is never stranded in the dead centre when camera-position packets are
## missing/delayed (e.g. after a reconnect). Pure geometry on a throwaway avatar.

const AvatarScript := preload("res://scripts/player_avatar.gd")


func _avatar() -> Node3D:
	var a: Node3D = auto_free(AvatarScript.new())
	add_child(a)
	return a


func test_edge_position_is_on_the_correct_side() -> void:
	var a := _avatar()
	var size := Vector2(6, 4)  # 6x4 ft table
	# slot 1 = left (-X), 2 = right (+X), 3 = front (-Z), 4 = back (+Z)
	assert_float(a._default_edge_position(1, size).x).is_less(0.0)
	assert_float(a._default_edge_position(2, size).x).is_greater(0.0)
	assert_float(a._default_edge_position(3, size).z).is_less(0.0)
	assert_float(a._default_edge_position(4, size).z).is_greater(0.0)


func test_edge_position_is_never_the_dead_centre() -> void:
	var a := _avatar()
	var size := Vector2(6, 4)
	for slot in [1, 2, 3, 4, 0, 7]:  # incl. slot 0 (pending) and a high monotonic slot
		var p: Vector3 = a._default_edge_position(slot, size)
		assert_bool(Vector2(p.x, p.z).length() > 0.5).is_true()  # well off centre
		assert_float(p.y).is_greater(0.0)  # floats above the table


func test_edge_position_scales_with_table_size() -> void:
	var a := _avatar()
	# A bigger table pushes the left-edge head further out on -X.
	var small: float = a._default_edge_position(1, Vector2(4, 4)).x
	var big: float = a._default_edge_position(1, Vector2(8, 4)).x
	assert_float(big).is_less(small)  # more negative = further left
