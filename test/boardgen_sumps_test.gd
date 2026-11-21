extends GdUnitTestSuite
## The toxic sumps of a boardgen layout (BoardgenSumps): a low kerb round each pool of Hazard cells and one green glow per pool. The kerb stays
## inside the pool's own outer rim (the open floor round it is standing room), it is as low as a flat prop, nothing here is physical, and one
## layout always builds the same sumps. Synthetic 8 x 8 layouts, so the suite stands on its own.

const NX := 8
const NZ := 8
const CELL_IN := 3.0


## An 8 x 8 board of open level-0 floor; `sump` cells are Hazard, `tier` cells are level 1.
func _layout(sump: Array, tier: Array = []) -> Dictionary:
	var cells: Array[Dictionary] = []
	for z in NZ:
		for x in NX:
			var c := Vector2i(x, z)
			cells.append({"x": x, "z": z, "level": 1 if tier.has(c) else 0, "lot_kind": "Hazard" if sump.has(c) else "Street", "lot_id": 0, "street": false})
	return {"seed": 5, "nx": NX, "nz": NZ, "cell_in": CELL_IN, "board_in": [NX * CELL_IN, NZ * CELL_IN], "cells": cells, "level_in": [0, 3, 6, 9], "connectors": []}


func _two_by_two(at: Vector2i) -> Array:
	return [at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)]


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL_IN + NX * 0.5), floori(p.y / CELL_IN + NZ * 0.5))


func test_a_board_without_a_hazard_has_no_kerb_no_pool_and_no_light() -> void:
	var layout := _layout([])
	assert_array(BoardgenSumps.kerbs(layout)).is_empty()
	assert_array(BoardgenSumps.pools(layout)).is_empty()
	var sumps: BoardgenSumps = auto_free(BoardgenSumps.new())
	sumps.build(layout)
	assert_int(sumps.get_child_count()).is_equal(0)


func test_a_two_by_two_pool_gets_eight_kerb_edges_and_one_pool_with_its_centre() -> void:
	var layout := _layout(_two_by_two(Vector2i(3, 3)))
	assert_int(BoardgenSumps.kerbs(layout).size()).is_equal(8)   # 4 cells x 2 outer edges
	var pools := BoardgenSumps.pools(layout)
	assert_int(pools.size()).is_equal(1)
	assert_int(pools[0]["cells"].size()).is_equal(4)
	assert_vector(Vector2(pools[0]["centre"])).is_equal(Vector2.ZERO)   # cells 3..4 of 8: the board centre


func test_the_kerb_stays_inside_its_own_sump_cell_on_an_edge_that_meets_open_floor() -> void:
	var layout := _layout(_two_by_two(Vector2i(2, 2)) + [Vector2i(6, 5)])
	for k in BoardgenSumps.kerbs(layout):
		var lo := Vector2(k["lo"].x, k["lo"].z)
		var hi := Vector2(k["hi"].x, k["hi"].z)
		var inside := _cell_of(lo + Vector2(0.001, 0.001))
		assert_bool(inside == _cell_of(hi - Vector2(0.001, 0.001))).override_failure_message("a kerb box crosses a cell edge: %s" % str(k)).is_true()
		assert_bool(BoardgenSumps.is_sump(layout, inside.x, inside.y)).override_failure_message("a kerb stands on open floor: %s" % str(inside)).is_true()
		assert_float(minf(hi.x - lo.x, hi.y - lo.y)).is_less_equal(0.3)   # a thin rim, never a wall
		assert_float(k["hi"].y - BoardgenSumps.SKIN_IN).is_less_equal(0.12 + 0.0001)   # as low as a flat prop
		assert_bool(k["solid"]).is_false()
		assert_str(k["kind"]).is_equal("kerb")


func test_an_edge_against_a_tier_wall_or_the_board_rim_gets_no_kerb() -> void:
	var walled := _layout([Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)])
	assert_array(BoardgenSumps.kerbs(walled)).is_empty()   # a wall on the open sides, the board rim on the others
	var pair := _layout([Vector2i(0, 3), Vector2i(1, 3)])
	assert_int(BoardgenSumps.kerbs(pair).size()).is_equal(5)   # 2 cells: top and bottom each, the right end; the left end is the rim


func test_separate_sumps_are_separate_pools_with_one_shadowless_light_each_and_nothing_physical() -> void:
	var layout := _layout(_two_by_two(Vector2i(1, 1)) + [Vector2i(6, 6)])
	assert_int(BoardgenSumps.pools(layout).size()).is_equal(2)
	var sumps: BoardgenSumps = auto_free(BoardgenSumps.new())
	sumps.build(layout)
	assert_int(sumps.get_child_count()).is_equal(2)
	for n in sumps.get_children():
		assert_bool(n is OmniLight3D and not (n as OmniLight3D).shadow_enabled).is_true()
		assert_bool(n is CollisionObject3D).is_false()
	assert_int(sumps.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)


func test_one_layout_plans_the_same_sumps_and_a_moved_pool_moves_the_kerb() -> void:
	var a := _layout(_two_by_two(Vector2i(2, 2)))
	randomize()   # the global generator must not matter
	assert_array(BoardgenSumps.kerbs(a)).is_equal(BoardgenSumps.kerbs(_layout(_two_by_two(Vector2i(2, 2)))))
	assert_array(BoardgenSumps.pools(a)).is_equal(BoardgenSumps.pools(_layout(_two_by_two(Vector2i(2, 2)))))
	assert_bool(BoardgenSumps.kerbs(a) == BoardgenSumps.kerbs(_layout(_two_by_two(Vector2i(4, 4))))).is_false()


func test_the_board_draws_the_kerb_in_its_one_multimesh_with_no_extra_collider_and_a_sumps_node() -> void:
	var layout := _layout(_two_by_two(Vector2i(3, 3)))
	var boxes := BoardgenGreybox.plan(layout)
	var kerbs := boxes.filter(func(b: Dictionary) -> bool: return b["kind"] == "kerb")
	assert_int(kerbs.size()).is_equal(8)
	assert_bool(BoardgenGreybox.KINDS.has("kerb")).is_true()
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	var surfaces := node.find_child("Surfaces", false, false) as MultiMeshInstance3D
	assert_int(surfaces.multimesh.instance_count).is_equal(boxes.size())
	assert_int((node.find_child("Colliders", false, false) as StaticBody3D).get_child_count()).is_equal(0)   # no tier on this board: the kerb is not solid
	assert_int((node.find_child("Sumps", false, false) as Node3D).get_child_count()).is_equal(1)
