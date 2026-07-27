extends GdUnitTestSuite
## SightFan — the sight+range fan's ray semantics against the maintainer's sketch spec: rays from the BASE
## EDGE, walls stop exactly at the hit, CONTAINER blocks at entry, area terrain is see-INTO-not-THROUGH
## (one foreign zone), and an origin inside area terrain sees OUT of its own zone.

const T := TerrainRules.TerrainType


## terrain field helper: bands along +x — [ [x_from, x_to, type], ... ], NONE elsewhere.
func _bands(bands: Array) -> Callable:
	return func(p: Vector2) -> int:
		for b in bands:
			if p.x >= b[0] and p.x < b[1]:
				return int(b[2])
		return int(T.NONE)


## The fan vertex pointing along +x (ray k=0) — its distance from the ray start (= base edge).
func _reach_x(origin: Vector2, base_r: float, range_m: float, walls: Array, field: Callable) -> float:
	var poly := SightFan.fan_polygon(origin, base_r, range_m, walls, field, 8)
	return (poly[0] - (origin + Vector2(base_r, 0))).length()


func test_open_ground_reaches_full_range_from_base_edge() -> void:
	var reach := _reach_x(Vector2.ZERO, 0.016, 0.6, [], _bands([]))
	assert_float(reach).is_equal_approx(0.6, 0.001)


func test_wall_stops_the_ray_exactly_at_the_hit() -> void:
	var walls := [[Vector2(0.3, -1.0), Vector2(0.3, 1.0)]]
	var reach := _reach_x(Vector2.ZERO, 0.016, 0.6, walls, _bands([]))
	assert_float(reach).is_equal_approx(0.3 - 0.016, 0.001)   # from the base edge to the wall


func test_container_blocks_at_entry_no_see_into() -> void:
	var reach := _reach_x(Vector2.ZERO, 0.0, 0.6, [], _bands([[0.3, 0.5, T.CONTAINER]]))
	assert_float(reach).is_less(0.31)
	assert_float(reach).is_greater(0.2)


func test_forest_is_seen_into_but_not_through() -> void:
	# Forest band 0.2..0.4: visible INTO it (fan reaches past 0.25) but ends at its far edge (< 0.45),
	# never the full 0.8 range — "Ziele mit Deckung" inside, "nicht gesehen" beyond (the sketch).
	var reach := _reach_x(Vector2.ZERO, 0.0, 0.8, [], _bands([[0.2, 0.4, T.FOREST]]))
	assert_float(reach).is_greater(0.25)
	assert_float(reach).is_less(0.45)


func test_second_foreign_zone_is_not_entered() -> void:
	# Two forest bands with a gap: the ray sees into band 1, stops at its far edge — it must never reach
	# band 2 (that would be "through" the first zone to a spot before the second).
	var reach := _reach_x(Vector2.ZERO, 0.0, 1.2, [], _bands([[0.2, 0.4, T.FOREST], [0.6, 0.8, T.FOREST]]))
	assert_float(reach).is_less(0.45)


func test_origin_inside_forest_sees_out_and_into_one_more_zone() -> void:
	# Origin at x=0.1 INSIDE forest band 0.0..0.2 (see out of the own zone), open until 0.5, ruin band
	# 0.5..0.7 (see INTO it), stop at its far edge — not the full 1.2 range.
	var field := _bands([[0.0, 0.2, T.FOREST], [0.5, 0.7, T.RUINS]])
	var poly := SightFan.fan_polygon(Vector2(0.1, 0.0), 0.0, 1.2, [], field, 8)
	var reach := (poly[0] - Vector2(0.1, 0.0)).length()
	assert_float(reach).is_greater(0.45)   # sees out + across the open ground + into the ruin
	assert_float(reach).is_less(0.75)      # but never beyond the ruin's far edge


func test_dangerous_never_blocks_sight() -> void:
	var reach := _reach_x(Vector2.ZERO, 0.0, 0.6, [], _bands([[0.2, 0.4, T.DANGEROUS]]))
	assert_float(reach).is_equal_approx(0.6, 0.001)


func test_union_merges_overlapping_fans() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(0.5, 0), Vector2(1.5, 0), Vector2(1.5, 1), Vector2(0.5, 1)])
	var far := PackedVector2Array([Vector2(5, 5), Vector2(6, 5), Vector2(6, 6), Vector2(5, 6)])
	var merged := SightFan.union_fans([a, b, far])
	assert_int(merged.size()).is_equal(2)   # a+b merge into one outline; far stays separate
