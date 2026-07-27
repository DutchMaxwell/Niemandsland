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


## === Base-aware zone membership (_zone_for_base): a model is IN terrain its BASE overlaps (GF v3.5.1),
##     via base-perimeter sampling. Cell = 3" = 0.0762 m; on a 6x4 table grid_size = 30, so cell (cx) left
##     edge x = (cx-15)*0.0762. Forest cells cx<=15 fill x < 0.0762. ===

func _forest_wall_left(o: Node3D) -> void:
	# Forest block covering cx in [10..15] (x < 0.0762 m), cz in [12..18] — a wall on the -x side.
	for cx in range(10, 16):
		for cz in range(12, 19):
			o.grid_cells[Vector2i(cx, cz)] = OverlayScript.TerrainType.FOREST


func test_base_edge_overlapping_forest_counts_as_inside() -> void:
	# Centre at x=0.09 m sits in cell 16 (open), but a ~1" base (r=0.025 m) reaches to x=0.065 m -> cell 15
	# (forest). The base OVERLAPS the forest, so the model counts as INSIDE the forest zone (sees in/out).
	var o := _overlay()
	_forest_wall_left(o)
	assert_bool(o._zone_for_base(Vector3(0.09, 0, 0), 0.025).is_empty()).is_false()


func test_base_just_short_of_forest_is_not_inside() -> void:
	# Centre at x=0.13 m: the same ~1" base reaches only to x=0.105 m -> cell 16 (open). The base does NOT
	# reach the forest -> NOT inside (the precise test that stops the earlier coarse over-grant).
	var o := _overlay()
	_forest_wall_left(o)
	assert_bool(o._zone_for_base(Vector3(0.13, 0, 0), 0.025).is_empty()).is_true()


func test_base_on_dangerous_ground_at_forest_edge_is_inside_forest() -> void:
	# Centre in a DANGEROUS cell (16,15) right beside the forest wall: dangerous is not AREA terrain, so the
	# perimeter scan must still run — the base (r=0.025 m) overlaps forest cell (15,15) -> inside the forest
	# zone (see in/out). Regression guard for the "centre in non-area terrain skips the scan" edge.
	var o := _overlay()
	_forest_wall_left(o)
	o.grid_cells[Vector2i(16, 15)] = OverlayScript.TerrainType.DANGEROUS
	assert_bool(o._zone_for_base(Vector3(0.09, 0, 0), 0.025).has(Vector2i(15, 15))).is_true()


func test_radius_zero_is_exact_centre_cell() -> void:
	# radius 0 (the coarse callers / all pre-existing tests) keeps exact centre-cell behaviour.
	var o := _overlay()
	_forest_wall_left(o)
	assert_bool(o._zone_for_base(Vector3(0.09, 0, 0), 0.0).is_empty()).is_true()   # centre in open cell 16


func test_forest_between_still_blocks_with_a_small_base() -> void:
	# REGRESSION GUARD (my reverted coarse fix over-granted here): two open-ground models with a forest
	# strictly BETWEEN them still can't see through, even with a realistic ~1" base — neither base reaches
	# the middle forest, so it stays a blocker.
	var o := _overlay()
	_fill(o, A, B, 0.4, 0.6, OverlayScript.TerrainType.FOREST)   # middle only, endpoints on open ground
	assert_bool(o.has_line_of_sight(A, B, 2, 2, 0.025, 0.025)).is_false()


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
