extends GdUnitTestSuite
## Top-down, height-aware Asgard line-of-sight (terrain_overlay.has_line_of_sight)
## plus the terrain blocking / height / effect-label helpers.

const OverlayScript = preload("res://scripts/terrain_overlay.gd")

const A := Vector3(-0.6, 0, 0)
const B := Vector3(0.6, 0, 0)


func _overlay() -> Node3D:
	var o: Node3D = auto_free(OverlayScript.new())
	o.table_size_feet = Vector2(6, 4)
	o.grid_rotation_degrees = 0.0
	return o


## Paint terrain into the cells the segment A->B crosses for t in [t0, t1].
func _fill(o: Node3D, a: Vector3, b: Vector3, t0: float, t1: float, type: int) -> void:
	var steps := 40
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		if t < t0 or t > t1:
			continue
		o.grid_cells[o.world_to_cell(a.lerp(b, t))] = type


func test_clear_when_no_terrain() -> void:
	assert_bool(_overlay().has_line_of_sight(A, B, 2, 2)).is_true()


func test_forest_between_blocks_infantry() -> void:
	var o := _overlay()
	_fill(o, A, B, 0.4, 0.6, OverlayScript.TerrainType.FOREST)  # middle only
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_false()


func test_titan_sees_over_height5() -> void:
	var o := _overlay()
	_fill(o, A, B, 0.4, 0.6, OverlayScript.TerrainType.FOREST)
	# H6 titan vs H6: a Height-5 forest does not block (taller sees over).
	assert_bool(o.has_line_of_sight(A, B, 6, 6)).is_true()


func test_dangerous_never_blocks() -> void:
	var o := _overlay()
	_fill(o, A, B, 0.4, 0.6, OverlayScript.TerrainType.DANGEROUS)
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_true()


func test_own_zone_does_not_block() -> void:
	var o := _overlay()
	# One contiguous forest covering both endpoints -> same zone -> they see each other.
	_fill(o, A, B, 0.0, 1.0, OverlayScript.TerrainType.FOREST)
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_true()


func test_blocking_and_height_helpers() -> void:
	var o := _overlay()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.CONTAINER)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.DANGEROUS)).is_false()
	assert_int(o.terrain_height_category(OverlayScript.TerrainType.RUINS)).is_equal(5)
	assert_int(o.terrain_height_category(OverlayScript.TerrainType.DANGEROUS)).is_equal(0)


func test_effect_labels_per_type() -> void:
	var o := _overlay()
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.FOREST)).contains("Difficult")
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.FOREST)).contains("Cover")
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.DANGEROUS)).contains("Dangerous")
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.NONE)).is_empty()
