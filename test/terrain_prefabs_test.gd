extends GdUnitTestSuite
## Tests for TerrainPrefabs — the canonical OPR tournament terrain pieces that expand
## into grid_cells footprints, auto-suggested ruin walls, and decoration objects.


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	return rng


func test_palette_has_all_canonical_pieces() -> void:
	var keys := TerrainPrefabs.keys()
	assert_int(keys.size()).is_equal(5)
	for key in ["ruine_9x9", "ruine_9x6", "wald_9x9", "blocker_6x3", "dangerous_9x6"]:
		assert_bool(TerrainPrefabs.has_prefab(key)).is_true()


func test_terrain_types_match_enum() -> void:
	assert_int(TerrainPrefabs.terrain_type("ruine_9x9")).is_equal(TerrainPrefabs.TYPE_RUINS)
	assert_int(TerrainPrefabs.terrain_type("wald_9x9")).is_equal(TerrainPrefabs.TYPE_FOREST)
	assert_int(TerrainPrefabs.terrain_type("blocker_6x3")).is_equal(TerrainPrefabs.TYPE_CONTAINER)
	assert_int(TerrainPrefabs.terrain_type("dangerous_9x6")).is_equal(TerrainPrefabs.TYPE_DANGEROUS)


func test_footprint_cell_counts() -> void:
	assert_int(TerrainPrefabs.footprint_cells("ruine_9x9", Vector2i.ZERO).size()).is_equal(9)
	assert_int(TerrainPrefabs.footprint_cells("ruine_9x6", Vector2i.ZERO).size()).is_equal(6)
	assert_int(TerrainPrefabs.footprint_cells("wald_9x9", Vector2i.ZERO).size()).is_equal(9)
	assert_int(TerrainPrefabs.footprint_cells("blocker_6x3", Vector2i.ZERO).size()).is_equal(2)
	assert_int(TerrainPrefabs.footprint_cells("dangerous_9x6", Vector2i.ZERO).size()).is_equal(6)


func test_footprint_is_offset_by_origin() -> void:
	# 3x2 ruin at origin (2,3) spans (2,3)..(4,4)
	var cells := TerrainPrefabs.footprint_cells("ruine_9x6", Vector2i(2, 3))
	assert_array(cells).contains([Vector2i(2, 3), Vector2i(4, 4)])
	assert_array(cells).not_contains([Vector2i(5, 3)])


func test_unknown_prefab_returns_empty() -> void:
	assert_int(TerrainPrefabs.footprint_cells("does_not_exist", Vector2i.ZERO).size()).is_equal(0)
	assert_int(TerrainPrefabs.wall_segments_for("does_not_exist", Vector2i.ZERO).size()).is_equal(0)


func test_ruin_walls_two_opposite_corners() -> void:
	# 3x3 ruin -> two point-symmetric L-corners: (2 north + 2 west) + (2 south + 2 east) = 8
	var segments := TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i.ZERO)
	assert_int(segments.size()).is_equal(8)

	var sides := {}
	var proc_keyed := true
	for seg in segments:
		sides[seg["edge_side"]] = true
		if seg["wall_key"] != TerrainPrefabs.PROC_WALL_KEY:
			proc_keyed = false
	# all four edges are represented (two opposite L-corners)
	assert_bool(sides.has(TerrainPrefabs.EDGE_NORTH) and sides.has(TerrainPrefabs.EDGE_WEST) \
		and sides.has(TerrainPrefabs.EDGE_SOUTH) and sides.has(TerrainPrefabs.EDGE_EAST)).is_true()
	assert_bool(proc_keyed).is_true()


func test_ruin_walls_share_the_origin_corner() -> void:
	# The L pivots on the origin cell: it carries both a north and a west edge.
	var segments := TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i.ZERO)
	assert_int(segments.size()).is_equal(6)  # NW: 2 north + 1 west; SE: 2 south + 1 east
	var has_north_at_origin := false
	var has_west_at_origin := false
	for seg in segments:
		if seg["edge_cell"] == Vector2i.ZERO and seg["edge_side"] == TerrainPrefabs.EDGE_NORTH:
			has_north_at_origin = true
		if seg["edge_cell"] == Vector2i.ZERO and seg["edge_side"] == TerrainPrefabs.EDGE_WEST:
			has_west_at_origin = true
	assert_bool(has_north_at_origin).is_true()
	assert_bool(has_west_at_origin).is_true()


func test_wall_roles_full_at_corner_crumble_to_ends() -> void:
	# 3x3 arms are 2 cells each: the corner cell stays "full", the free-end cell
	# crumbles. With four arms that is 4 "full" + 4 "crumble_steep".
	var roles := {}
	for seg in TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i.ZERO):
		var role: String = seg["role"]
		roles[role] = int(roles.get(role, 0)) + 1
	assert_int(int(roles.get("full", 0))).is_equal(4)
	assert_int(int(roles.get("crumble_steep", 0))).is_equal(4)


func test_non_ruin_has_no_walls() -> void:
	assert_int(TerrainPrefabs.wall_segments_for("wald_9x9", Vector2i.ZERO).size()).is_equal(0)
	assert_int(TerrainPrefabs.wall_segments_for("dangerous_9x6", Vector2i.ZERO).size()).is_equal(0)


func test_ruins_have_no_decoration() -> void:
	assert_int(TerrainPrefabs.decoration_for("ruine_9x9", Vector2i.ZERO, _seeded_rng()).size()).is_equal(0)


func test_forest_decoration_places_trees() -> void:
	# 9 cells * 0.6 trees/cell -> ceil(5.4) = 6 trees
	var objects := TerrainPrefabs.decoration_for("wald_9x9", Vector2i.ZERO, _seeded_rng())
	assert_int(objects.size()).is_equal(6)
	for obj in objects:
		assert_str(obj["object_type"]).is_equal("tree")


func test_forest_trees_keep_margin_from_area_boundary() -> void:
	# Trees stay TREE_EDGE_MARGIN_INCHES (in cell units: margin/3") away from the
	# forest footprint outline, across many seeds and a shifted origin.
	var origin := Vector2i(4, 7)
	var margin := TerrainPrefabs.TREE_EDGE_MARGIN_INCHES / TerrainPrefabs.CELL_SIZE_INCHES
	var size := 3.0  # wald_9x9 = 3x3 cells
	for seed_value in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed_value
		for obj in TerrainPrefabs.decoration_for("wald_9x9", origin, rng):
			var cell: Vector2i = obj["cell"]
			var offset: Vector2 = obj["offset"]
			var pos := Vector2(cell - origin) + offset  # in cell units within the footprint
			assert_float(pos.x).is_greater_equal(margin)
			assert_float(pos.x).is_less_equal(size - margin)
			assert_float(pos.y).is_greater_equal(margin)
			assert_float(pos.y).is_less_equal(size - margin)


func test_forest_trees_keep_minimum_spacing() -> void:
	# Trees must not interpenetrate: pairwise spacing >= TREE_MIN_SPACING_INCHES.
	for seed_value in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2000 + seed_value
		var objects := TerrainPrefabs.decoration_for("wald_9x9", Vector2i.ZERO, rng)
		for i in objects.size():
			for j in range(i + 1, objects.size()):
				var cell_a: Vector2i = objects[i]["cell"]
				var offset_a: Vector2 = objects[i]["offset"]
				var cell_b: Vector2i = objects[j]["cell"]
				var offset_b: Vector2 = objects[j]["offset"]
				var a := (Vector2(cell_a) + offset_a) * TerrainPrefabs.CELL_SIZE_INCHES
				var b := (Vector2(cell_b) + offset_b) * TerrainPrefabs.CELL_SIZE_INCHES
				assert_float(a.distance_to(b)).is_greater_equal(TerrainPrefabs.TREE_MIN_SPACING_INCHES)


func test_blocker_decoration_is_single_centered_container() -> void:
	var objects := TerrainPrefabs.decoration_for("blocker_6x3", Vector2i.ZERO, _seeded_rng())
	assert_int(objects.size()).is_equal(1)
	assert_str(objects[0]["object_type"]).is_equal("container")
	assert_that(objects[0]["offset"]).is_equal(Vector2(1.0, 0.5))


func test_dangerous_decoration_is_a_minefield() -> void:
	# 6 cells * 2.5 mines/cell -> 15 anti-tank mines, plus 2 warning signs at the
	# opposite corners of the field.
	var objects := TerrainPrefabs.decoration_for("dangerous_9x6", Vector2i.ZERO, _seeded_rng())
	var mines: Array[Dictionary] = []
	var signs: Array[Dictionary] = []
	for obj in objects:
		if obj["object_type"] == "mine":
			mines.append(obj)
		elif obj["object_type"] == "warning_sign":
			signs.append(obj)
	assert_int(mines.size()).is_equal(15)
	assert_int(signs.size()).is_equal(2)
	assert_int(objects.size()).is_equal(17)
	# Signs sit on the NW and SE corner cells of the 3x2 footprint.
	assert_that(signs[0]["cell"]).is_equal(Vector2i(0, 0))
	assert_that(signs[1]["cell"]).is_equal(Vector2i(2, 1))


func test_minefield_mines_keep_minimum_spacing() -> void:
	for seed_value in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = 3000 + seed_value
		var objects := TerrainPrefabs.decoration_for("dangerous_9x6", Vector2i.ZERO, rng)
		var mines: Array[Vector2] = []
		for obj in objects:
			if obj["object_type"] == "mine":
				var cell: Vector2i = obj["cell"]
				var offset: Vector2 = obj["offset"]
				mines.append((Vector2(cell) + offset) * TerrainPrefabs.CELL_SIZE_INCHES)
		for i in mines.size():
			for j in range(i + 1, mines.size()):
				assert_float(mines[i].distance_to(mines[j])).is_greater_equal(TerrainPrefabs.MINE_MIN_SPACING_INCHES)


# --- Orientation (rotation / flip) ---

func test_footprint_size_swaps_on_rotation() -> void:
	assert_that(TerrainPrefabs.footprint_size("ruine_9x6", 0)).is_equal(Vector2i(3, 2))
	assert_that(TerrainPrefabs.footprint_size("ruine_9x6", 90)).is_equal(Vector2i(2, 3))
	assert_that(TerrainPrefabs.footprint_size("ruine_9x6", 180)).is_equal(Vector2i(3, 2))
	assert_that(TerrainPrefabs.footprint_size("ruine_9x6", 270)).is_equal(Vector2i(2, 3))


func test_rotated_footprint_bounding_box() -> void:
	# 3×2 rotated 90° -> 2 wide × 3 tall, anchored at origin (0,0)
	var cells := TerrainPrefabs.footprint_cells("ruine_9x6", Vector2i.ZERO, 90)
	assert_int(cells.size()).is_equal(6)
	var min_x := 9999
	var min_y := 9999
	var max_x := -9999
	var max_y := -9999
	for c in cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)
	assert_int(min_x).is_equal(0)
	assert_int(min_y).is_equal(0)
	assert_int(max_x - min_x + 1).is_equal(2)
	assert_int(max_y - min_y + 1).is_equal(3)


func test_wall_sides_rotate() -> void:
	# The two opposite L-corners always cover all four edges; rotation maps each edge
	# (N->E->S->W) but the segments must stay within the rotated bounding box, which
	# catches a no-op / broken cell transform on the non-square 3x2 piece.
	for rot in [0, 90, 180, 270]:
		var fsize := TerrainPrefabs.footprint_size("ruine_9x6", rot)
		var segments := TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i.ZERO, rot)
		assert_int(segments.size()).is_equal(6)
		var sides := {}
		for s in segments:
			sides[s["edge_side"]] = true
			var c: Vector2i = s["edge_cell"]
			assert_bool(c.x >= 0 and c.x < fsize.x and c.y >= 0 and c.y < fsize.y).is_true()
		assert_int(sides.size()).is_equal(4)


func test_wall_taper_dir_points_to_free_ends() -> void:
	# Unrotated: the NW corner's arms taper E (north arm) / S (west arm); the SE corner's
	# arms taper W (south arm) / N (east arm) — each toward the arm's open end.
	var expected := {
		TerrainPrefabs.EDGE_NORTH: TerrainPrefabs.EDGE_EAST,
		TerrainPrefabs.EDGE_WEST: TerrainPrefabs.EDGE_SOUTH,
		TerrainPrefabs.EDGE_SOUTH: TerrainPrefabs.EDGE_WEST,
		TerrainPrefabs.EDGE_EAST: TerrainPrefabs.EDGE_NORTH,
	}
	var segments := TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i.ZERO)
	assert_int(segments.size()).is_equal(8)
	for seg in segments:
		assert_int(int(seg["taper_dir"])).is_equal(int(expected[seg["edge_side"]]))


func test_wall_taper_dir_rotates_with_the_piece() -> void:
	# 90° CW maps side and taper together (N->E->S->W each), so (N side, E taper)
	# becomes (E side, S taper) etc. — the taper keeps pointing at the rotated free end.
	var expected := {
		TerrainPrefabs.EDGE_EAST: TerrainPrefabs.EDGE_SOUTH,
		TerrainPrefabs.EDGE_NORTH: TerrainPrefabs.EDGE_WEST,
		TerrainPrefabs.EDGE_WEST: TerrainPrefabs.EDGE_NORTH,
		TerrainPrefabs.EDGE_SOUTH: TerrainPrefabs.EDGE_EAST,
	}
	for seg in TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i.ZERO, 90):
		assert_int(int(seg["taper_dir"])).is_equal(int(expected[seg["edge_side"]]))


func test_wall_taper_dir_mirrors_on_flip() -> void:
	# Mirror X swaps E<->W for both the side and the taper: (N,E)->(N,W), (W,S)->(E,S)...
	var expected := {
		TerrainPrefabs.EDGE_NORTH: TerrainPrefabs.EDGE_WEST,
		TerrainPrefabs.EDGE_EAST: TerrainPrefabs.EDGE_SOUTH,
		TerrainPrefabs.EDGE_SOUTH: TerrainPrefabs.EDGE_EAST,
		TerrainPrefabs.EDGE_WEST: TerrainPrefabs.EDGE_NORTH,
	}
	for seg in TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i.ZERO, 0, true):
		assert_int(int(seg["taper_dir"])).is_equal(int(expected[seg["edge_side"]]))


func test_flip_changes_wall_layout() -> void:
	var sig := func(flip: bool) -> Array:
		var out := []
		for s in TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i.ZERO, 0, flip):
			out.append([s["edge_cell"], s["edge_side"]])
		return out
	assert_bool(sig.call(false) == sig.call(true)).is_false()
	assert_int(TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i.ZERO, 0, true).size()).is_equal(8)


func test_container_decoration_records_rotation() -> void:
	var objs0 := TerrainPrefabs.decoration_for("blocker_6x3", Vector2i.ZERO, _seeded_rng(), 0, false)
	assert_int(int(objs0[0].get("angle_deg", -1))).is_equal(0)
	var objs90 := TerrainPrefabs.decoration_for("blocker_6x3", Vector2i.ZERO, _seeded_rng(), 90, false)
	assert_int(int(objs90[0].get("angle_deg", -1))).is_equal(90)
