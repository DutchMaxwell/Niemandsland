extends GdUnitTestSuite
## The greybox 3D of a seeded boardgen layout: every cell shows up exactly once, the tiers have their heights, every
## connector is drawn, one layout always builds the same board, the nodes mirror the plan, and the dev flag is off unless
## NML_BOARDGEN_SEED is set. The layouts are a recorded one (seed 42, so this suite stands on its own) plus, when this
## NmlCore has the boardgen_layout binding, live ones for more seeds.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const LIVE_SEEDS := [1, 7]
const CELLS := 256
const CELL_IN := 3.0


func _core() -> Object:
	var core: Object = ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null
	return core if core != null and core.has_method("boardgen_layout") else null


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


func _layouts() -> Array[Dictionary]:
	var out: Array[Dictionary] = [_fixture()]
	var core := _core()
	if core != null:
		for board_seed in LIVE_SEEDS:
			out.append(core.boardgen_layout(board_seed))
	return out


func _of_kind(boxes: Array[Dictionary], kinds: Array) -> Array[Dictionary]:
	return boxes.filter(func(b: Dictionary) -> bool: return kinds.has(b["kind"]))


func _area_in(b: Dictionary) -> float:
	return (b["hi"].x - b["lo"].x) * (b["hi"].z - b["lo"].z)


func test_the_recorded_layout_is_a_whole_board() -> void:
	var layout := _fixture()
	assert_int(layout["cells"].size()).is_equal(CELLS)
	assert_array(layout["level_in"]).is_equal([0, 3, 6])
	assert_array(layout["problems"]).is_empty()
	var core := _core()
	if core != null:   # the recording still is what the core makes (this check wakes up once the binding is merged)
		assert_dict(core.boardgen_layout(42)).is_equal(layout)


func test_the_blocks_tile_the_board_once_and_count_the_cells_of_each_tier() -> void:
	for layout in _layouts():
		var blocks := _of_kind(BoardgenGreybox.plan(layout), ["street", "ground", "hazard", "tier1", "tier2"])
		var area := 0.0
		for b in blocks:
			area += _area_in(b)
		assert_float(area).is_equal(CELLS * CELL_IN * CELL_IN)
		for level in [1, 2]:
			var want: int = layout["cells"].filter(func(c: Dictionary) -> bool: return c["level"] == level).size()
			var got := 0.0
			for b in _of_kind(blocks, ["tier%d" % level]):
				got += _area_in(b)
			assert_float(got / (CELL_IN * CELL_IN)).override_failure_message("seed %s tier %d" % [layout["seed"], level]).is_equal(float(want))


func test_a_tier_block_is_as_high_as_its_level_in_inches() -> void:
	for layout in _layouts():
		var level_in: Array = layout["level_in"]
		var seen := {}
		for b in BoardgenGreybox.plan(layout):
			for level in [1, 2]:
				if b["kind"] == "tier%d" % level:
					seen[level] = true
					assert_float(b["hi"].y).is_equal(float(level_in[level]))
					assert_float(b["lo"].y).is_equal(0.0)
		assert_int(seen.size()).is_equal(2)   # the board has both tiers


func test_every_connector_is_drawn_as_steps_or_as_rails_and_rungs() -> void:
	for layout in _layouts():
		var stairs: int = layout["connectors"].filter(func(c: Dictionary) -> bool: return c["kind"] == "Stair").size()
		var ladders: int = layout["connectors"].size() - stairs
		var boxes := BoardgenGreybox.plan(layout)
		assert_int(_of_kind(boxes, ["stair"]).size()).is_equal(stairs * BoardgenGreybox.STAIR_STEPS)
		# Two rails and five rungs per 3 in ladder.
		assert_int(_of_kind(boxes, ["ladder"]).size()).is_equal(ladders * 7)
	var fixed := _fixture()
	assert_bool(fixed["connectors"].any(func(c: Dictionary) -> bool: return c["kind"] == "Stair")).is_true()
	assert_bool(fixed["connectors"].any(func(c: Dictionary) -> bool: return c["kind"] == "Ladder")).is_true()


func test_one_layout_builds_the_same_board_and_another_layout_a_different_one() -> void:
	var layouts := _layouts()
	assert_array(BoardgenGreybox.plan(layouts[0])).is_equal(BoardgenGreybox.plan(_fixture()))
	for i in range(1, layouts.size()):
		assert_bool(BoardgenGreybox.plan(layouts[0]) == BoardgenGreybox.plan(layouts[i])).is_false()


func _built(layout: Dictionary) -> BoardgenGreybox:
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	return node


func test_build_draws_the_whole_board_in_one_multimesh_and_a_ground_layer_collider_per_solid_box() -> void:
	var layout := _fixture()
	var node := _built(layout)
	var boxes := BoardgenGreybox.plan(layout)
	var surfaces := node.find_child("Surfaces", false, false) as MultiMeshInstance3D
	assert_int(surfaces.multimesh.instance_count).is_equal(boxes.size())
	assert_int(node.find_children("*", "MeshInstance3D", false, false).size()).is_equal(0)   # one draw call, not one node per box
	var body := node.find_child("Colliders", false, false) as StaticBody3D
	assert_int(body.get_child_count()).is_equal(boxes.filter(func(b: Dictionary) -> bool: return b["solid"]).size())
	assert_int(body.collision_layer).is_equal(BoardgenGreybox.GROUND_COLLISION_LAYER)
	# Visual only for the rules: the board is none of the shelf pieces the sight and terrain rules read.
	assert_bool(node.is_in_group("sandbox_terrain") or node.is_in_group("terrain")).is_false()


func test_the_board_shader_gets_a_height_texel_per_cell_and_knows_every_surface_kind() -> void:
	var layout := _fixture()
	var surfaces := _built(layout).find_child("Surfaces", false, false) as MultiMeshInstance3D
	var mat := surfaces.material_override as ShaderMaterial
	var cells: Image = (mat.get_shader_parameter("cells") as ImageTexture).get_image()
	assert_int(cells.get_width() * cells.get_height()).is_equal(CELLS)
	for c: Dictionary in layout["cells"]:
		assert_int(cells.get_pixel(c["x"], c["z"]).r8).is_equal(int(layout["level_in"][c["level"]]))
	for b in BoardgenGreybox.plan(layout):   # (the per-instance kind itself is not readable back on the headless renderer)
		assert_int(BoardgenGreybox.KINDS.find(b["kind"])).override_failure_message("the board shader has no kind '%s'" % b["kind"]).is_greater_equal(0)


func test_the_dev_flag_is_off_unless_the_env_var_is_set() -> void:
	var table: Node3D = auto_free(Node3D.new())
	add_child(table)
	OS.set_environment(BoardgenGreybox.ENV_SEED, "")
	assert_object(BoardgenGreybox.attach_from_env(table)).is_null()
	OS.set_environment(BoardgenGreybox.ENV_SEED, "7")
	var node := BoardgenGreybox.attach_from_env(table)
	OS.set_environment(BoardgenGreybox.ENV_SEED, "")
	if OS.is_debug_build() and _core() != null:
		assert_object(node).is_not_null()
		assert_int(node.layout_seed).is_equal(7)
		assert_object(node.get_parent()).is_same(table)
		assert_bool(node.is_in_group("table_overlay")).is_true()   # survives Table.setup_table's child sweep
	else:
		assert_object(node).is_null()
