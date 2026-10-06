extends GdUnitTestSuite
## Lead 06.10.: worn tracks and wall-foot stains must read on sand and ash (they were nearly invisible there). Measured
## against the ground the presenter lays (means of the reference textures, s1/biomes/ref_albedo.py, 06.10.): a track
## or stain blended at its own alpha must stand out: on the desert at least 35 % darker than sand and 20 % darker
## than the cracked earth beside it (a stain at 26 % still vanished in the render); on ash at least 25 % lighter than
## fine ash and clearly lighter than cooled lava (pale compacted ash, since dark lava patches hide a dark track).

const SAND := Color(0.811, 0.737, 0.624)   # desert/sand.webp
const CRACKED_EARTH := Color(0.563, 0.527, 0.493)   # desert/cracked-earth.webp
const FINE_ASH := Color(0.42, 0.401, 0.374)   # volcanic/fine-ash.webp
const COOLED_LAVA := Color(0.19, 0.193, 0.196)   # volcanic/cooled-lava.webp


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
	get_node("/root/GraphicsSettings").current_preset = 2   # MEDIUM: a preset that dresses the table


func after_test() -> void:
	get_node("/root/GraphicsSettings").current_preset = _preset_was


func _lum(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


## Brightness of the ground with the decal pixel blended over it at the pixel's own alpha.
func _over(ground: Color, px: Color) -> float:
	return lerpf(_lum(ground), _lum(px), px.a)


## Mean of a 5x5 patch of the decal texture around (x, y).
func _patch(img: Image, x: int, y: int) -> Color:
	var sum := Color(0, 0, 0, 0)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			sum += img.get_pixel(x + dx, y + dy)
	return sum / 25.0


func _check(what: String, px: Color) -> void:
	if _table.biome == "arid_desert":
		assert_float((_lum(SAND) - _over(SAND, px)) / _lum(SAND)).override_failure_message(
			"%s on sand: too close to the sand" % what).is_greater_equal(0.35)
		assert_float((_lum(CRACKED_EARTH) - _over(CRACKED_EARTH, px)) / _lum(CRACKED_EARTH)).override_failure_message(
			"%s on cracked earth: too close" % what).is_greater_equal(0.2)
	else:
		assert_float((_over(FINE_ASH, px) - _lum(FINE_ASH)) / _lum(FINE_ASH)).override_failure_message(
			"%s on fine ash: not lighter" % what).is_greater_equal(0.25)
		assert_float(_over(COOLED_LAVA, px) - _lum(COOLED_LAVA)).override_failure_message(
			"%s on cooled lava: not lighter" % what).is_greater_equal(0.15)


func test_tracks_and_stains_read_on_sand_and_ash() -> void:
	var paths := TablePaths.of(_table)
	paths.set_paths([[[0.0, 0.0], [10.0, 0.0]]])
	var solid: SandboxSolidProp = auto_free(SandboxSolidProp.new())
	solid.configure("blocker_6x3", 3, Vector2(6, 3))
	add_child(solid)
	var dressing: Decal = solid.find_children("FootDressing", "Decal", false, false)[0]
	for biome: String in ["arid_desert", "volcanic_ash"]:
		_table.biome = biome
		_table.biome_changed.emit(biome)
		var strip := (paths.get_child(0) as Decal).texture_albedo.get_image()
		_check("track", _patch(strip, 32, 8))   # the middle of the strip
		var img := dressing.texture_albedo.get_image()
		# 0.3" outside the footprint's long edge, in the middle row (8 px per inch; the texture is footprint + 3" a side)
		_check("stain", _patch(img, int((12.0 * 0.5 + 6.0 * 0.5 + 0.3) * 8.0), int(9.0 * 0.5 * 8.0)))
