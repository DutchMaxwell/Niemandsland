extends GdUnitTestSuite
## Regiment save/load core: Regiment.to_dict captures frontage + tray transform, and
## RegimentTray.adopt_existing reparents loaded nodes keeping their world transform
## (so the exact saved block is reproduced). Full game round-trip is verified live.

const APPROX := Vector3(0.0001, 0.0001, 0.0001)


func _tray() -> RegimentTray:
	var t := RegimentTray.new()
	add_child(t)
	return auto_free(t)


func _node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	return auto_free(n)


func test_regiment_to_dict_captures_frontage_and_tray_transform() -> void:
	var tray := _tray()
	tray.global_position = Vector3(1.5, 0.0, -2.0)
	tray.rotation.y = 0.75
	var reg := Regiment.new(null, tray, 5)
	var d := reg.to_dict()
	assert_int(d["frontage"]).is_equal(5)
	assert_array(d["tray_pos"]).is_equal([1.5, 0.0, -2.0])
	assert_float(d["tray_rot_y"]).is_equal_approx(0.75, 0.0001)


func test_adopt_existing_reparents_keeping_world_transform() -> void:
	var tray := _tray()
	tray.global_position = Vector3(1.0, 0.0, 1.0)
	tray.rotation.y = PI / 2.0
	var n := _node(Vector3(2.0, 0.0, 3.0))
	var world_before: Vector3 = n.global_position

	tray.adopt_existing([n])

	assert_object(n.get_parent()).is_equal(tray)
	assert_object(n.get_meta("regiment_tray")).is_equal(tray)
	# World transform preserved despite the reparent.
	assert_vector(n.global_position).is_equal_approx(world_before, APPROX)
