extends GdUnitTestSuite
## Tests the scatter decorations: rubble placement at ruin wall bases (deterministic,
## correct taper band, densest at the wall) and the grassland grass field (biome- and
## quality-gated MultiMesh).

const OverlayScript = preload("res://scripts/terrain_overlay.gd")


func _segment() -> Dictionary:
	return {"edge_cell": Vector2i(4, 7), "edge_side": 2, "length_inches": 3.0}


func test_rubble_is_deterministic() -> void:
	var a := OverlayScript.rubble_placements_for(_segment(), 60)
	var b := OverlayScript.rubble_placements_for(_segment(), 60)
	assert_int(a.size()).is_equal(60)
	for i in a.size():
		assert_bool(a[i].is_equal_approx(b[i])).is_true()


func test_rubble_stays_in_the_taper_band() -> void:
	var half_wall: float = OverlayScript.RUIN_SHELL_THICKNESS_INCHES * 0.0254 / 2.0
	for placement in OverlayScript.rubble_placements_for(_segment(), 200):
		var dist := absf(placement.origin.z) - half_wall
		assert_float(dist).is_greater_equal(0.0)
		assert_float(dist).is_less_equal(OverlayScript.RUBBLE_MAX_DIST_M)
		# Along the wall: within the 3" segment; embedded but above ground.
		assert_float(absf(placement.origin.x)).is_less_equal(1.5 * 0.0254)
		assert_float(placement.origin.y).is_greater(0.0)


func test_rubble_is_densest_at_the_wall() -> void:
	var half_wall: float = OverlayScript.RUIN_SHELL_THICKNESS_INCHES * 0.0254 / 2.0
	var near := 0
	var far := 0
	for placement in OverlayScript.rubble_placements_for(_segment(), 500):
		var dist := absf(placement.origin.z) - half_wall
		if dist < OverlayScript.RUBBLE_MAX_DIST_M / 2.0:
			near += 1
		else:
			far += 1
	# Quadratic falloff: the near half-band must hold clearly more than half.
	assert_int(near).is_greater(far * 2)


func test_rubble_count_zero_yields_no_placements() -> void:
	assert_int(OverlayScript.rubble_placements_for(_segment(), 0).size()).is_equal(0)


func test_grass_only_on_grassland() -> void:
	var grass := GrassField.new()
	add_child(auto_free(grass))
	grass.set_table_size(Vector2(1.0, 1.0))

	grass.set_biome("temperate_grassland")
	assert_object(grass.multimesh).is_not_null()
	assert_int(grass.multimesh.instance_count).is_greater(0)

	grass.set_biome("arid_desert")
	assert_object(grass.multimesh).is_null()


func test_grass_count_scales_with_table_area() -> void:
	var grass := GrassField.new()
	add_child(auto_free(grass))
	grass.set_biome("temperate_grassland")
	grass.set_table_size(Vector2(1.0, 1.0))
	var small: int = grass.multimesh.instance_count
	grass.set_table_size(Vector2(2.0, 1.0))
	var large: int = grass.multimesh.instance_count
	assert_int(large).is_equal(small * 2)


func test_grass_heights_stay_in_range() -> void:
	var grass := GrassField.new()
	add_child(auto_free(grass))
	grass.set_biome("temperate_grassland")
	grass.set_table_size(Vector2(0.5, 0.5))
	var ratio_min: float = GrassField.TUFT_HEIGHT_MIN_M / GrassField.TUFT_HEIGHT_MAX_M
	for i in mini(grass.multimesh.instance_count, 300):
		var y_scale: float = grass.multimesh.get_instance_transform(i).basis.get_scale().y
		assert_float(y_scale).is_greater_equal(ratio_min - 0.001)
		assert_float(y_scale).is_less_equal(1.001)