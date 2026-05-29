extends GdUnitTestSuite
## Tests ObjectManager._arrange_spacing: per-axis spacing capped for OPR 1in
## coherency, so oval bases and a large joined-Hero base do not break coherency.

const ObjectManagerScript = preload("res://scripts/object_manager.gd")


func _om():
	# Not added to the tree; _arrange_spacing/_base_footprint are pure helpers.
	return auto_free(ObjectManagerScript.new())


func _round_node(round_mm: int) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": round_mm}
	node.set_meta("game_unit", unit)
	return node


func _oval_node(width_mm: int, depth_mm: int) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	var unit := GameUnit.new()
	unit.unit_properties = {
		"base_is_oval": true,
		"base_width_mm": width_mm,
		"base_depth_mm": depth_mm,
		"base_size_round": maxi(width_mm, depth_mm),
	}
	node.set_meta("game_unit", unit)
	return node


func test_uniform_round_keeps_tight_gap() -> void:
	var spacing: Vector2 = _om()._arrange_spacing([_round_node(25), _round_node(25)])
	# 25mm base + 8mm gap on both axes.
	assert_float(spacing.x).is_equal_approx(0.033, 0.0005)
	assert_float(spacing.y).is_equal_approx(0.033, 0.0005)


func test_oval_spaces_each_axis_by_its_own_extent() -> void:
	# 25mm wide x 50mm deep cavalry oval - previously base_size_round (50, the long
	# axis) was used for BOTH axes, blowing the in-row gap past 1in.
	var spacing: Vector2 = _om()._arrange_spacing([_oval_node(25, 50), _oval_node(25, 50)])
	assert_float(spacing.x).is_equal_approx(0.033, 0.0005)  # width 25 + 8mm
	assert_float(spacing.y).is_equal_approx(0.058, 0.0005)  # depth 50 + 8mm
	# In-row edge gap on X stays within 1in (0.0254 m).
	assert_float(spacing.x - 0.025).is_less(0.0254)


func test_big_hero_keeps_troops_coherent() -> void:
	# 25mm troops + one 50mm hero base in the same selection.
	var spacing: Vector2 = _om()._arrange_spacing([_round_node(25), _round_node(25), _round_node(50)])
	var troop_gap: float = spacing.x - 0.025
	assert_float(troop_gap).is_less(0.0254)  # smallest base within 1in coherency
	assert_float(troop_gap).is_greater(0.0)   # but troops do not overlap
