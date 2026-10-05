extends GdUnitTestSuite
## Worn paths are a table-level setting (lead D14 = a): TablePaths draws one dirt decal per path segment, and the
## paths are saved with the table and come back on load; a save without paths clears the paths of the previous table.
## Points are inches from the table centre (x, z), the frame the theme pieces use.

const PATH := [[[0.0, 0.0], [6.0, 0.0], [6.0, 8.0]]]   # one path, two segments


class StubTable extends Node3D:
	var table_size := Vector2(6, 4)
	var biome := "temperate_grassland"

	func setup_table(size_feet: Vector2) -> void:
		table_size = size_feet

	func set_biome(b: String) -> void:
		biome = b


func _table() -> StubTable:
	var t: StubTable = auto_free(StubTable.new())
	add_child(t)
	return t


func test_paths_draw_one_decal_per_segment() -> void:
	var paths := TablePaths.of(_table())
	paths.set_paths(PATH)
	var decals := paths.find_children("*", "Decal", false, false)
	assert_int(decals.size()).is_equal(2)
	if decals.size() == 2:
		var first := decals[0] as Decal
		assert_vector(first.position).is_equal_approx(Vector3(3.0, 0.0, 0.0) * 0.0254, Vector3.ONE * 0.0001)
		assert_float(first.size.x).is_equal_approx((6.0 + 1.5) * 0.0254, 0.0001)   # the segment + soft ends
	paths.set_paths([])
	assert_int(paths.find_children("*", "Decal", false, false).size()).is_equal(0)


func test_paths_survive_a_save_and_a_pathless_save_clears_them() -> void:
	var sm: SaveManager = auto_free(SaveManager.new())
	sm.table = _table()
	TablePaths.of(sm.table).set_paths(PATH)
	var data: Dictionary = JSON.parse_string(JSON.stringify(sm._serialize_table()))   # as written to the .nml file
	var loaded := _table()
	sm.table = loaded
	sm._deserialize_table(data)
	assert_array(TablePaths.of(loaded).paths).is_equal(PATH)
	assert_int(TablePaths.of(loaded).find_children("*", "Decal", false, false).size()).is_equal(2)
	data.erase("paths")   # an older save
	sm._deserialize_table(data)
	assert_int(TablePaths.of(loaded).paths.size()).is_equal(0)
