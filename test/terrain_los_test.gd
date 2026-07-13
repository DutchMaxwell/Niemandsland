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
	# Ruins are AREA terrain (GF/AoF v3.5.1 p.12, applied per maintainer correction to field-test round-4):
	# you see into/out of them but not through — so they ARE a Height-5 sight blocker, like a forest.
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.RUINS)).is_true()
	assert_int(o.terrain_height_category(OverlayScript.TerrainType.RUINS)).is_equal(5)
	assert_int(o.terrain_height_category(OverlayScript.TerrainType.DANGEROUS)).is_equal(0)


func test_area_terrain_predicate() -> void:
	# Forests + Ruins are AREA terrain (see in/out, not through); solid Containers are NOT (hard-block).
	var o := _overlay()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.RUINS)).is_true()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.CONTAINER)).is_false()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.DANGEROUS)).is_false()


func test_ruins_between_blocks_infantry() -> void:
	# A ruin straddling the line between two open-ground models blocks the through-sight (see in/out, NOT
	# through) — the maintainer correction: ruins are area terrain, not fully see-through.
	var o := _overlay()
	_fill(o, A, B, 0.4, 0.6, OverlayScript.TerrainType.RUINS)  # middle only, neither endpoint inside
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_false()


func test_shot_into_ruins_target_just_inside_is_visible() -> void:
	# Shooter on open ground, target standing just inside a ruin (the ruin fills the target half of the line).
	# The target endpoint's own zone covers every crossed ruin cell -> "see INTO it" -> visible.
	var o := _overlay()
	_fill(o, A, B, 0.55, 1.0, OverlayScript.TerrainType.RUINS)
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_true()


func test_shot_out_of_ruins_shooter_inside_is_visible() -> void:
	# Shooter inside a ruin firing out at an open-ground target -> "see OUT of it" -> visible.
	var o := _overlay()
	_fill(o, A, B, 0.0, 0.45, OverlayScript.TerrainType.RUINS)
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_true()


func test_deep_forest_target_inside_visible_no_depth_cap() -> void:
	# A deep forest filling the whole target half (~9 cells): a target anywhere INSIDE — even near the far
	# edge — is visible. There is NO depth cap in GF/AoF v3.5.1; the boundary is the zone perimeter, not "X".
	var o := _overlay()
	_fill(o, A, B, 0.4, 1.0, OverlayScript.TerrainType.FOREST)  # B (t=1.0) sits deep inside
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_true()


func test_forest_target_just_beyond_far_edge_is_blocked() -> void:
	# Same deep forest, but the target sits one step BEYOND the far edge (open ground): the line now passes
	# all the way THROUGH the forest to a far-side target -> blocked. This is the boundary complement of
	# test_deep_forest_target_inside_visible_no_depth_cap (inside = see-in; beyond = through).
	var o := _overlay()
	_fill(o, A, B, 0.4, 0.8, OverlayScript.TerrainType.FOREST)  # forest ends before B; B is in the open
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_false()


func test_container_hard_blocks_even_when_endpoints_share_the_zone() -> void:
	# A solid Container is NOT area terrain: the see-in/out zone exception does NOT apply. Even with the whole
	# line inside one container zone (contrast test_own_zone_does_not_block for a forest), it still hard-blocks.
	var o := _overlay()
	_fill(o, A, B, 0.0, 1.0, OverlayScript.TerrainType.CONTAINER)
	assert_bool(o.has_line_of_sight(A, B, 2, 2)).is_false()


func test_effect_labels_per_type() -> void:
	var o := _overlay()
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.FOREST)).contains("Difficult")
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.FOREST)).contains("Cover")
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.DANGEROUS)).contains("Dangerous")
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.NONE)).is_empty()
	# Ruins now read as an area LOS blocker with cover — no longer "(see-through)".
	var ruins_label: String = o._terrain_effect_label(OverlayScript.TerrainType.RUINS)
	assert_str(ruins_label).contains("Cover")
	assert_str(ruins_label).contains("Blocks LoS")
	assert_str(ruins_label).not_contains("see-through")
