extends GdUnitTestSuite
## The town's silhouette pieces (maintainer 21.11.: "still too blocky from above") on real town boards from the core: the look may break the outline, never the play space - every
## walkable top stays exact and free in its middle, no piece leaves its cell or strip, a ladder's top stays clear, the wall is drawn at most REACH_IN inside its collider.

const SEEDS := [3, 7, 11, 25, 41]
const EPS := 0.0005


func _towns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var core: Object = ClassDB.instantiate("NmlCore")
	for s: int in SEEDS:
		out.append(core.boardgen_layout_themed(s, "ruintown"))
	return out


func _origin(layout: Dictionary) -> Vector2:
	return Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * -0.5


func _cell_rect(layout: Dictionary, i: int) -> Rect2:
	var c := float(layout["cell_in"])
	return Rect2(_origin(layout) + Vector2(i % int(layout["nx"]), i / int(layout["nx"])) * c, Vector2(c, c))


## Index of the cell a board point (inches) lies in.
func _cell_at(layout: Dictionary, p: Vector2) -> int:
	var q := ((p - _origin(layout)) / float(layout["cell_in"])).floor()
	return int(q.y) * int(layout["nx"]) + int(q.x)


func test_the_core_gives_town_boards_here() -> void:
	assert_bool(ClassDB.class_exists("NmlCore")).is_true()
	for l in _towns():
		assert_str(str(l["theme"])).is_equal("RuinTown")


func test_a_wall_or_tower_cell_is_drawn_inside_its_cell_at_most_reach_in_thinner_and_its_walk_is_exact() -> void:
	for layout in _towns():
		var parts := BoardgenTownSilhouette.wall_parts(layout)
		var own := BoardgenTownSilhouette.drawn_cells(layout)
		assert_int(own.size()).is_greater(0)
		var caps := {}
		for b: Dictionary in parts:
			var r := _cell_rect(layout, b["cell"])
			var lo := Vector2(b["lo"].x, b["lo"].z)
			var hi := Vector2(b["hi"].x, b["hi"].z)
			assert_bool(lo.x >= r.position.x - EPS and lo.y >= r.position.y - EPS and hi.x <= r.end.x + EPS and hi.y <= r.end.y + EPS).override_failure_message("a wall piece leaves its cell").is_true()
			var gap := maxf(maxf(lo.x - r.position.x, lo.y - r.position.y), maxf(r.end.x - hi.x, r.end.y - hi.y))
			assert_float(gap).override_failure_message("a wall face %f in inside its collider" % gap).is_less_equal(BoardgenTownSilhouette.REACH_IN + EPS)
			var top: float = layout["level_in"][layout["cells"][b["cell"]]["level"]]
			if is_equal_approx(b["hi"].y, top):
				assert_float(gap).is_less(EPS)   # the walk: the whole cell, at its exact height
				caps[b["cell"]] = true
			assert_float(b["hi"].y).is_less_equal(top + EPS)
		assert_int(caps.size()).is_equal(own.size())


func test_the_greybox_keeps_the_collider_of_a_wall_cell_but_draws_it_no_more() -> void:
	for layout in _towns():
		var own := BoardgenTownSilhouette.drawn_cells(layout)
		var hidden := BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b.get("hidden", false))
		assert_int(hidden.size()).is_equal(own.size())
		for b: Dictionary in hidden:
			assert_bool(b["solid"]).is_true()
			assert_bool(BoardgenGreybox.draws_itself(b)).is_false()
			assert_float(b["hi"].x - b["lo"].x).is_equal_approx(float(layout["cell_in"]), EPS)   # one cell each, never merged into a run


func test_the_town_dressing_builds_the_silhouette_on_the_board_material() -> void:
	var layout: Dictionary = _towns()[0]
	var node: BoardgenTownDressing = auto_free(BoardgenTownDressing.new())
	var mat := ShaderMaterial.new()
	node.build(layout, mat)
	var mmi := node.get_node("Silhouette") as MultiMeshInstance3D
	assert_int(mmi.multimesh.instance_count).is_equal(BoardgenTownSilhouette.wall_parts(layout).size())
	assert_object(mmi.material_override).is_same(mat)
	assert_int(node.find_children("*", "CollisionShape3D", true, false).size()).is_equal(0)
