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
