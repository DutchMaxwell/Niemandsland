extends GdUnitTestSuite
## S8.3 (maintainer 06.10.: the terrain should match the biome): the wall-foot scatter and dressing take the table's
## biome instead of showing on grassland only (D12). Desert: sand under the walls; tundra: cold blue-grey stones;
## volcanic ash: dark cinders and no grass; grassland: today's colours; a biome without a palette: nothing.


class StubTable extends Node3D:
	signal biome_changed(biome_name: String)
	var biome := "arid_desert"


var _table: StubTable
var _preset_was: int


func before_test() -> void:
	_table = auto_free(StubTable.new())
	_table.add_to_group("table")
	add_child(_table)
	_preset_was = get_node("/root/GraphicsSettings").current_preset
	get_node("/root/GraphicsSettings").current_preset = 2   # MEDIUM: a preset that dresses the table (headless runs lower)


func after_test() -> void:
	get_node("/root/GraphicsSettings").current_preset = _preset_was


## The stone colours (sRGB) the scatter wrote. Read from the node, not the MultiMesh: headless, the dummy renderer
## hands back black for every instance colour, so a check on it could never fail (measured 06.10.).
func _stones(scatter: Node3D) -> Array:
	var written: Variant = scatter.get("colours")
	return (written as Dictionary).get("stone", []) if written is Dictionary else []


func test_the_wall_feet_follow_the_table_biome() -> void:
	var solid: SandboxSolidProp = auto_free(SandboxSolidProp.new())
	solid.configure("blocker_6x3", 3, Vector2(6, 3))
	add_child(solid)
	var scatter: Node3D = solid.find_children("FootScatter", "Node3D", false, false)[0]
	var dressing: Decal = solid.find_children("FootDressing", "Decal", false, false)[0]
	assert_bool(scatter.visible and dressing.visible).override_failure_message("hidden on the desert table").is_true()
	assert_int(_stones(scatter).size()).override_failure_message("no stone colours").is_equal(22)   # a solid's ring
	var img := dressing.texture_albedo.get_image()
	assert_float(img.get_pixel(img.get_width() / 2, img.get_height() / 2).r).override_failure_message(
		"no sand under the walls").is_greater(0.4)
	_table.biome_changed.emit("frozen_tundra")
	assert_bool(_stones(scatter).all(func(c: Color) -> bool: return c.b > c.r)).override_failure_message(
		"tundra stones not cold").is_true()
	_table.biome_changed.emit("volcanic_ash")
	assert_bool((scatter.get_child(1) as Node3D).visible).override_failure_message("grass on ash").is_false()
	assert_bool(_stones(scatter).all(func(c: Color) -> bool: return maxf(c.r, maxf(c.g, c.b)) < 0.45)) \
		.override_failure_message("cinders not dark").is_true()
	_table.biome_changed.emit("temperate_grassland")
	assert_bool(scatter.visible and (scatter.get_child(1) as Node3D).visible).is_true()
	assert_bool(_stones(scatter).all(func(c: Color) -> bool: return c.r > c.b)).override_failure_message(
		"grassland stones changed").is_true()
	_table.biome_changed.emit("no_such_biome")
	assert_bool(scatter.visible or dressing.visible).override_failure_message("shown without a palette").is_false()
