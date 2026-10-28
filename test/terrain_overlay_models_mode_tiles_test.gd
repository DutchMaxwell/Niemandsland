extends GdUnitTestSuite
## #1888: flat terrain tiles leaked back into MODELS mode after a layout rebuild. update_overlay()
## built every flat cell tile with `visible = true` and ignored the active overlay mode, while
## set_overlay_mode() only hid the tiles that existed at that instant. A rebuild (Auto-Generate,
## load, peer sync) therefore resurrected the pale 3-inch staircase under the standing props.
## The overlay is created WITHOUT add_child(), like terrain_overlay_test / los_volumes_test, so
## _ready() never runs and the R2 libraries stay null (every readiness helper is null-safe).

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const TABLE := Vector2(6, 4)   # feet


func _overlay() -> Node3D:
	return auto_free(OverlayScript.new())


## A 2x3 DANGEROUS block plus a 3x3 FOREST block on a 6x4 ft table (15 painted cells).
func _layout() -> Dictionary:
	var data := {}
	for x in range(10, 12):
		for y in range(10, 13):
			data[Vector2i(x, y)] = OverlayScript.TerrainType.DANGEROUS
	for x in range(15, 18):
		for y in range(10, 13):
			data[Vector2i(x, y)] = OverlayScript.TerrainType.FOREST
	return data


func _visible_tiles(o: Node3D) -> int:
	var n := 0
	for mesh in o.overlay_meshes:
		if is_instance_valid(mesh) and mesh.visible:
			n += 1
	return n


## CONTROL: the flat tiles are what FLAT and BOTH are FOR. This must pass with and without the
## fix - it guards the mode-gated path against an over-eager "hide everything in MODELS" change.
func test_control_flat_mode_shows_the_tiles() -> void:
	var o := _overlay()
	o.set_overlay_mode(OverlayScript.OverlayMode.FLAT)
	o.update_overlay(_layout(), TABLE, 0.0)
	assert_int(_visible_tiles(o)).override_failure_message(
		"FLAT must still paint the flat terrain tiles").is_equal(15)
	o.set_overlay_mode(OverlayScript.OverlayMode.BOTH)
	o.update_overlay(_layout(), TABLE, 0.0)
	assert_int(_visible_tiles(o)).override_failure_message(
		"BOTH must still paint the flat terrain tiles").is_equal(15)


## PROVING CASE: MODELS is active, then the layout is rebuilt - no flat tile may come back.
func test_models_mode_survives_a_rebuild() -> void:
	var o := _overlay()
	o.update_overlay(_layout(), TABLE, 0.0)
	o.set_overlay_mode(OverlayScript.OverlayMode.MODELS)
	assert_int(_visible_tiles(o)).override_failure_message(
		"MODELS must hide the tiles that already exist").is_equal(0)
	o.update_overlay(_layout(), TABLE, 0.0)
	assert_int(_visible_tiles(o)).override_failure_message(
		"MODELS rebuilt the flat tiles: the active mode was ignored at creation (#1888)").is_equal(0)
