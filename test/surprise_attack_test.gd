extends GdUnitTestSuite
## Surprise Attack burst (audit D 2026-09-08, the table arm of #810's core read): "The first time
## this unit is activated, pick one enemy unit within 6" in line of sight, and roll X dice. For
## each 2+ it takes one hit with AP(1)." The table had NO burst at all (audit D: GAP) — only the
## #761 Infiltrate-equivalent reserve claim. This suite tests the pick seam the burst uses: the
## core's port takes the Storm Attack descending pick (unit.rs:2762 — biggest living target among
## the in-range candidates). The pick is static on main.gd (the #1040 precedent) so it is testable
## without a board; the range/LOS filtering stays at the board-side call site.

const MainScript := preload("res://scripts/main.gd")


func _unit(models: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_%d" % models
	u.unit_properties = {"player_id": 1, "name": "U%d" % models, "quality": 4, "defense": 4}
	for i in range(models):
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(0, 0, 0.5)
		m.node = n
		u.models.append(m)
	return u


func test_pick_from_an_empty_candidate_list_is_nothing() -> void:
	assert_object(MainScript.surprise_attack_pick([])).is_null()


func test_pick_takes_the_biggest_living_target() -> void:
	var small := _unit(2)
	var big := _unit(7)
	var mid := _unit(4)
	assert_object(MainScript.surprise_attack_pick([small, big, mid])).is_equal(big)


func test_pick_order_does_not_matter() -> void:
	var big := _unit(7)
	var small := _unit(2)
	assert_object(MainScript.surprise_attack_pick([small, big])).is_equal(big)


func test_pick_skips_a_dead_candidate() -> void:
	var dead := _unit(0)
	var alive := _unit(1)
	assert_object(MainScript.surprise_attack_pick([dead, alive])).is_equal(alive)
