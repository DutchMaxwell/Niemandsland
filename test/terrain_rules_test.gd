extends GdUnitTestSuite
## TerrainRules is the pure, shared terrain model (grid of typed 3" cells) that the sim uses now and
## terrain_overlay.gd delegates to at integration. These prove its classification, line-of-sight (copied
## from terrain_overlay), cover majority and path checks — the geometry the sim's terrain rules ride on.

const T := TerrainRules.TerrainType


func test_type_predicates_match_the_rulebook() -> void:
	# Ruins: Cover + Blocks LoS. Forest: + Difficult. Container: Impassable + Blocks LoS. Dangerous: only.
	assert_bool(TerrainRules.blocks_los(T.RUINS)).is_true()
	assert_bool(TerrainRules.gives_cover(T.RUINS)).is_true()
	assert_bool(TerrainRules.is_difficult(T.RUINS)).is_false()
	assert_bool(TerrainRules.is_difficult(T.FOREST)).is_true()
	assert_bool(TerrainRules.gives_cover(T.FOREST)).is_true()
	assert_bool(TerrainRules.is_impassable(T.CONTAINER)).is_true()
	assert_bool(TerrainRules.blocks_los(T.CONTAINER)).is_true()
	assert_bool(TerrainRules.gives_cover(T.CONTAINER)).is_false()
	assert_bool(TerrainRules.is_dangerous(T.DANGEROUS)).is_true()
	assert_bool(TerrainRules.blocks_los(T.DANGEROUS)).is_false()
	# Open ground triggers nothing.
	assert_bool(TerrainRules.blocks_los(T.NONE)).is_false()
	assert_bool(TerrainRules.gives_cover(T.NONE)).is_false()


func test_cell_and_terrain_at_map_inches_to_cells() -> void:
	# 3" cells: inches in [15,18) land in cell 5.
	assert_vector(TerrainRules.cell_of(Vector2(16.5, 16.5))).is_equal(Vector2i(5, 5))
	var grid := {Vector2i(5, 5): T.FOREST}
	assert_int(TerrainRules.terrain_at(grid, Vector2(16.5, 16.5))).is_equal(int(T.FOREST))
	assert_int(TerrainRules.terrain_at(grid, Vector2(1.0, 1.0))).is_equal(int(T.NONE))


func test_open_field_never_blocks_los() -> void:
	assert_bool(TerrainRules.has_line_of_sight({}, Vector2(5, 5), Vector2(40, 40), 1, 1)).is_true()


func test_container_between_two_points_blocks_los() -> void:
	# A container at cell (5,5) sits on the horizontal line y=16.5 between x=10 and x=25.
	var grid := {Vector2i(5, 5): T.CONTAINER}
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(10, 16.5), Vector2(25, 16.5), 1, 1)).is_false()


func test_you_see_out_of_your_own_forest_zone() -> void:
	# Endpoint standing INSIDE the forest zone can still see out of it (own-zone exception).
	var grid := {Vector2i(5, 5): T.FOREST}
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(16.5, 16.5), Vector2(25, 16.5), 1, 1)).is_true()


func test_area_terrain_predicate() -> void:
	# Forests + Ruins are AREA terrain (see in/out, not through); solid Containers are NOT (hard-block).
	assert_bool(TerrainRules.is_area_terrain(T.RUINS)).is_true()
	assert_bool(TerrainRules.is_area_terrain(T.FOREST)).is_true()
	assert_bool(TerrainRules.is_area_terrain(T.CONTAINER)).is_false()
	assert_bool(TerrainRules.is_area_terrain(T.DANGEROUS)).is_false()


func test_ruins_between_two_points_block_los() -> void:
	# Ruins are area terrain (GF/AoF v3.5.1 p.12, applied to ruins per maintainer correction to round-4): a
	# line drawn straight THROUGH a ruin to a far-side target on open ground is blocked (see in/out, NOT through).
	var grid := {Vector2i(5, 5): T.RUINS}
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(10, 16.5), Vector2(25, 16.5), 1, 1)).is_false()


func test_you_see_into_and_out_of_your_own_ruin_zone() -> void:
	# A shooter/target standing INSIDE a ruin sees in and out of it (own-zone exception, like a forest).
	var grid := {Vector2i(5, 5): T.RUINS}
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(16.5, 16.5), Vector2(25, 16.5), 1, 1)).is_true()
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(25, 16.5), Vector2(16.5, 16.5), 1, 1)).is_true()


func test_deep_area_zone_target_inside_visible_but_beyond_blocked() -> void:
	# Depth boundary: a 3-cell-deep ruin (cells 5,6,7 on row 5 = x in [15,24)). A target INSIDE the far cell
	# (x=22, cell 7) is visible (see-in, no depth cap), but a target just BEYOND the zone (x=28, open) is
	# blocked (the line passed all the way through). The boundary is the zone perimeter, not an inch depth.
	var grid := {Vector2i(5, 5): T.RUINS, Vector2i(6, 5): T.RUINS, Vector2i(7, 5): T.RUINS}
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(6, 16.5), Vector2(22, 16.5), 1, 1)).is_true()
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(6, 16.5), Vector2(28, 16.5), 1, 1)).is_false()


func test_container_hard_blocks_even_when_endpoints_share_the_zone() -> void:
	# Solid Containers are NOT area terrain: the see-in/out zone exception does not apply. Even with both
	# endpoints on the container's own cell, it still hard-blocks (contrast the forest own-zone exception).
	var grid := {Vector2i(5, 5): T.CONTAINER, Vector2i(6, 5): T.CONTAINER, Vector2i(7, 5): T.CONTAINER}
	assert_bool(TerrainRules.has_line_of_sight(grid, Vector2(16.5, 16.5), Vector2(22, 16.5), 1, 1)).is_false()


func test_majority_in_cover_needs_a_strict_majority() -> void:
	var grid := {Vector2i(5, 5): T.FOREST}
	var three_in := [Vector2(16, 16), Vector2(16.5, 16.5), Vector2(17, 17), Vector2(30, 30), Vector2(31, 31)]
	var two_in := [Vector2(16, 16), Vector2(16.5, 16.5), Vector2(30, 30), Vector2(31, 31), Vector2(32, 32)]
	assert_bool(TerrainRules.majority_in_cover(three_in, grid)).is_true()
	assert_bool(TerrainRules.majority_in_cover(two_in, grid)).is_false()
	assert_bool(TerrainRules.majority_in_cover(three_in, {})).is_false()   # open field: no cover


func test_path_crosses_difficult_and_dangerous() -> void:
	var forest := {Vector2i(5, 5): T.FOREST}
	var danger := {Vector2i(5, 5): T.DANGEROUS}
	# A move from (10,16.5) to (25,16.5) passes through cell (5,5).
	assert_bool(TerrainRules.path_crosses(forest, Vector2(10, 16.5), Vector2(25, 16.5), TerrainRules.PathCheck.DIFFICULT)).is_true()
	assert_bool(TerrainRules.path_crosses(danger, Vector2(10, 16.5), Vector2(25, 16.5), TerrainRules.PathCheck.DANGEROUS)).is_true()
	# A move that stays clear of the cell crosses nothing.
	assert_bool(TerrainRules.path_crosses(forest, Vector2(0, 0), Vector2(5, 0), TerrainRules.PathCheck.DIFFICULT)).is_false()


# === Base-in-terrain containment: partial overlap = in (GF/AoF v3.5.1; field-test round 6, finding 6) ===

func test_base_in_terrain_triggers_on_any_partial_overlap() -> void:
	# A model counts as IN a piece of terrain if ANY part of its base overlaps it (not centre-in, not
	# majority). The forest occupies x >= 1.0; the base has radius 0.3. THE single containment predicate every
	# terrain-effect / no-rest check routes through.
	var sampler := func(p) -> int:
		var x: float = (p as Vector3).x if p is Vector3 else (p as Vector2).x
		return int(T.FOREST) if x >= 1.0 else int(T.NONE)
	# Base centred at x=0.8 with radius 0.3 → its edge reaches x=1.1, INSIDE the forest (~33% overlap) → in.
	assert_bool(TerrainRules.base_in_terrain(Vector3(0.8, 0.0, 0.0), 0.3, sampler, TerrainRules.is_difficult)).is_true()
	# Base whose edge just barely enters (x=0.75 + 0.3 = 1.05 >= 1.0) → still in the forest.
	assert_bool(TerrainRules.base_in_terrain(Vector3(0.75, 0.0, 0.0), 0.3, sampler, TerrainRules.is_difficult)).is_true()
	# Base clear by a margin (x=0.6 + 0.3 = 0.9 < 1.0) → NOT in the forest.
	assert_bool(TerrainRules.base_in_terrain(Vector3(0.6, 0.0, 0.0), 0.3, sampler, TerrainRules.is_difficult)).is_false()
	# Centre INSIDE the forest is trivially in, regardless of radius.
	assert_bool(TerrainRules.base_in_terrain(Vector3(1.5, 0.0, 0.0), 0.0, sampler, TerrainRules.is_difficult)).is_true()
	# The predicate is class-selectable and works in the Vector2 frame too (forbidden-rest here).
	var danger := func(p) -> int:
		return int(T.DANGEROUS) if (p as Vector2).x >= 1.0 else int(T.NONE)
	assert_bool(TerrainRules.base_in_terrain(Vector2(0.8, 0.0), 0.3, danger, TerrainRules.is_forbidden_rest)).is_true()
	assert_bool(TerrainRules.base_in_terrain(Vector2(0.6, 0.0), 0.3, danger, TerrainRules.is_forbidden_rest)).is_false()
