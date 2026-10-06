extends GdUnitTestSuite
## S8.4 (maintainer 06.10.: the terrain should match the biome): the worn paths take the table's biome colour — a dark
## reddish packed-earth track on the desert and a pale compacted-ash track on volcanic ash (lead 06.10.: they must
## read there, sand_ash_readable_test), today's dusty earth on grassland — and follow a biome change.


class StubTable extends Node3D:
	signal biome_changed(biome_name: String)
	var biome := "arid_desert"


func _red(paths: TablePaths) -> float:
	var img := (paths.get_child(0) as Decal).texture_albedo.get_image()
	return img.get_pixel(32, 8).r   # the middle of the strip


func test_the_paths_take_the_table_biome_colour() -> void:
	var table: StubTable = auto_free(StubTable.new())
	add_child(table)
	var paths := TablePaths.of(table)
	paths.set_paths([[[0.0, 0.0], [10.0, 0.0]]])
	assert_float(_red(paths)).override_failure_message("no packed-earth track on the desert").is_between(0.3, 0.45)
	table.biome_changed.emit("volcanic_ash")
	assert_float(_red(paths)).override_failure_message("no pale track on ash").is_greater(0.55)
	table.biome_changed.emit("temperate_grassland")
	assert_float(_red(paths)).is_between(0.32, 0.41)   # today's dusty earth
