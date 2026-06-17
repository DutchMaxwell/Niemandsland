extends GdUnitTestSuite
## Pure grid/zone math in map_layout.gd (the 2.8k-line map editor). MapLayout extends
## Control with @onready node refs, so the instance is created WITHOUT add_child() —
## _ready() never runs and these helpers read only plain member vars. The paint /
## draw / screen-pos / file-IO paths need a laid-out, rendered Control and stay manual.

const MapLayoutScript := preload("res://scripts/map_layout.gd")


func _layout() -> Control:
	# No add_child: avoids the @onready crash; pure functions don't need the tree.
	return auto_free(MapLayoutScript.new())


# ===== _calculate_grid_dimensions: table diagonal / 3" cells, rounded up to even =====

func test_grid_dimensions_known_tables() -> void:
	var ml := _layout()
	ml.table_size_feet = Vector2(6, 4)
	assert_int(ml._calculate_grid_dimensions().x).is_equal(30)
	ml.table_size_feet = Vector2(4, 4)
	assert_int(ml._calculate_grid_dimensions().x).is_equal(24)
	ml.table_size_feet = Vector2(8, 4)
	assert_int(ml._calculate_grid_dimensions().x).is_equal(36)


func test_grid_dimensions_always_even_and_square() -> void:
	var ml := _layout()
	for size in [Vector2(6, 4), Vector2(4, 4), Vector2(8, 4), Vector2(6, 6)]:
		ml.table_size_feet = size
		var dims: Vector2i = ml._calculate_grid_dimensions()
		assert_int(dims.x).is_equal(dims.y)      # square grid (covers any rotation)
		assert_int(dims.x % 2).is_equal(0)        # even -> a true centre line exists


# ===== _is_valid_cell: 3" cell within grid bounds =====

func test_is_valid_cell_bounds() -> void:
	var ml := _layout()
	ml.table_size_feet = Vector2(6, 4)  # -> 30x30 grid
	assert_bool(ml._is_valid_cell(Vector2i(0, 0))).is_true()
	assert_bool(ml._is_valid_cell(Vector2i(29, 29))).is_true()
	assert_bool(ml._is_valid_cell(Vector2i(30, 0))).is_false()
	assert_bool(ml._is_valid_cell(Vector2i(0, 30))).is_false()
	assert_bool(ml._is_valid_cell(Vector2i(-1, 5))).is_false()


# ===== _template_to_prefab: terrain-type + footprint -> prefab key + rotation =====

func test_template_to_prefab_mapping() -> void:
	var ml := _layout()
	var T = MapLayoutScript.TerrainType
	var ruins_big: Dictionary = ml._template_to_prefab(T.RUINS, Vector2i(3, 3))
	assert_str(ruins_big["key"]).is_equal("ruine_9x9")
	assert_int(int(ruins_big["rotation"])).is_equal(0)
	assert_str(ml._template_to_prefab(T.RUINS, Vector2i(3, 2))["key"]).is_equal("ruine_9x6")
	assert_str(ml._template_to_prefab(T.FOREST, Vector2i(3, 3))["key"]).is_equal("wald_9x9")
	assert_str(ml._template_to_prefab(T.CONTAINER, Vector2i(2, 1))["key"]).is_equal("blocker_6x3")


func test_template_to_prefab_dangerous_rotation() -> void:
	var ml := _layout()
	var T = MapLayoutScript.TerrainType
	# The 2x3 template is the 3x2 dangerous prefab rotated 90 degrees.
	var rotated: Dictionary = ml._template_to_prefab(T.DANGEROUS, Vector2i(2, 3))
	assert_str(rotated["key"]).is_equal("dangerous_9x6")
	assert_int(int(rotated["rotation"])).is_equal(90)
	var upright: Dictionary = ml._template_to_prefab(T.DANGEROUS, Vector2i(3, 2))
	assert_int(int(upright["rotation"])).is_equal(0)


# ===== _find_objective_near_position: tolerance-based hit test =====

func test_find_objective_near_position() -> void:
	var ml := _layout()
	ml.mission_objectives.assign([Vector2(10.0, 10.0)])
	assert_int(ml._find_objective_near_position(Vector2(10.5, 10.0))).is_equal(0)   # within tolerance
	assert_int(ml._find_objective_near_position(Vector2(12.0, 10.0))).is_equal(-1)  # too far
	ml.mission_objectives.assign([])
	assert_int(ml._find_objective_near_position(Vector2.ZERO)).is_equal(-1)         # none placed
