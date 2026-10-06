extends GdUnitTestSuite

func test_surface_mask_tracks_authored_paths_and_clears() -> void:
	var paths: TablePaths = auto_free(TablePaths.new())
	assert_bool(paths.has_method("surface_segments")).is_true()
	if not paths.has_method("surface_segments"):
		return
	paths.paths = [[[0,0],[10,0],[10,10]], [[2,2],[2,2]]]
	var segments: PackedVector4Array = paths.call("surface_segments")
	assert_int(segments.size()).is_equal(2)
	assert_float(paths.call("surface_amount", Vector2(0.127,0), segments)).is_equal_approx(1.0,0.001)
	assert_float(paths.call("surface_amount", Vector2(0.127,0.1), segments)).is_zero()
	paths.paths = []
	assert_int((paths.call("surface_segments") as PackedVector4Array).size()).is_zero()

func test_surface_work_is_bounded_on_large_user_layouts() -> void:
	var paths: TablePaths = auto_free(TablePaths.new())
	if not paths.has_method("surface_segments"):
		return
	var line := []
	for i in 100:
		line.append([i,0])
	paths.paths = [line]
	assert_int((paths.call("surface_segments") as PackedVector4Array).size()).is_equal(64)
