extends GdUnitTestSuite
## The start view over a generated board (texture plan step 10, decision D-TEX3): 0.70 x the table diagonal instead of 0.95 while the board is on the table - when it arrives
## and after every reset of the view - and the table's 0.95 again once it leaves. Without a board nothing changes.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const PIVOT := preload("res://scripts/camera_controller.gd")
const DIAGONAL_M := 1.2192 * 1.41421356   # a 4 x 4 ft table


class StubTable extends Node3D:
	var table_size := Vector2(4, 4)


func _main() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar camera_pivot\n"
	script.reload()
	var main: Node = auto_free(Node.new())
	main.set_script(script)
	var pivot: Node3D = PIVOT.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 60.0   # as scenes/main.tscn
	pivot.add_child(cam)
	main.add_child(pivot)
	main.set("camera_pivot", pivot)
	var table := StubTable.new()
	table.name = "Table"
	main.add_child(table)
	add_child(main)
	return main


func _reset(pivot: Node3D) -> void:   # what main.gd's _adjust_camera_for_table_size does
	pivot.reset_view()
	pivot.adjust_for_table_size(Vector2(4, 4))


func _eye(pivot: Node3D) -> float:   # the camera's distance from the board centre
	pivot._apply_camera_transform()
	return (pivot.get_node("Camera3D") as Camera3D).global_position.length()


## The free share of the picture height above the highest top and below the near rim's foot (box top edges, the rim 15 mm outside the 4 ft table), from the
## camera's real transform and fov (unproject_position is not usable headless).
func _margins(pivot: Node3D, layout: Dictionary) -> Vector2:
	pivot._apply_camera_transform()
	var cam := pivot.get_node("Camera3D") as Camera3D
	var to_cam := cam.global_transform.affine_inverse()
	var ndc := func(p: Vector3) -> float: return (to_cam * p).y / (-(to_cam * p).z * tan(deg_to_rad(cam.fov * 0.5)))
	var rim := 0.6096 + 0.015
	var top: float = maxf(ndc.call(Vector3(0, 0.05, -rim)), ndc.call(Vector3(0, 0.05, rim)))
	for b: Dictionary in BoardgenGreybox.plan(layout):
		for z: float in [b["lo"].z, b["hi"].z]:
			top = maxf(top, ndc.call(Vector3(0, b["hi"].y, z) * 0.0254))
	return Vector2(1.0 - top, 1.0 + minf(ndc.call(Vector3(0, 0, rim)), ndc.call(Vector3(0, 0, -rim))))


func test_without_a_board_the_start_view_is_the_tables() -> void:
	var pivot: Node3D = _main().get("camera_pivot")
	_reset(pivot)
	assert_float(pivot.get_zoom()).is_equal_approx(DIAGONAL_M * 0.95, 0.0005)
	pivot.adjust_for_table_size(Vector2(4, 4), 0.5)   # the explicit factor wins
	assert_float(pivot.get_zoom()).is_equal_approx(DIAGONAL_M * 0.5, 0.0005)


func test_a_board_brings_the_start_view_closer_until_it_leaves() -> void:
	var main := _main()
	var pivot: Node3D = main.get("camera_pivot")
	_reset(pivot)
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	var board := BoardgenGreybox.attach(main.get_node("Table"), layout)
	assert_float(_eye(pivot)).override_failure_message("the board arrived and the view stayed at 0.95").is_equal_approx(DIAGONAL_M * 0.70, 0.0005)
	_reset(pivot)
	assert_float(_eye(pivot)).override_failure_message("a reset of the view lost the board's start view").is_equal_approx(DIAGONAL_M * 0.70, 0.0005)
	for yaw: float in [0.0, 180.0]:   # centred (the maintainer's bar 22.11.): the margins below the near rim and above the highest top within 10 %, at both sides
		pivot._yaw = yaw
		var m := _margins(pivot, layout)
		assert_bool(m.x > 0.0 and m.y > 0.0 and absf(m.x - m.y) <= 0.1 * maxf(m.x, m.y)).override_failure_message("start view not centred at yaw %d: free %s of the half height above / below" % [yaw, m]).is_true()
	pivot._mark_dirty()   # the first move: the camera stays put, the pivot is lifted onto the table
	assert_float(pivot._target_position.y).is_equal_approx(0.0, 0.0001)
	assert_float(_eye(pivot)).is_equal_approx(DIAGONAL_M * 0.70, 0.0005)
	main.get_node("Table").remove_child(board)
	board.free()
	_reset(pivot)
	assert_float(_eye(pivot)).override_failure_message("the board left and its start view stayed").is_equal_approx(DIAGONAL_M * 0.95, 0.0005)
