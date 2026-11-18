extends GdUnitTestSuite
## G8: BattleSim.capture resolves join_to_unit inside the army that owns the hero.
## A mirror match puts two lists of one faction on one board (same selectionIds);
## the join index must not let one army's hero land on the other army's host.

const IN2M := 0.0254


func _unit(pid: int, uid: String, sel: String, join_to: String, x: float) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	var opr := OPRApiClient.OPRUnit.new()
	opr.selection_id = sel
	opr.join_to_unit = join_to
	u.source_data = opr
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(x * IN2M, 0, 0)
	m.node = n
	u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return army


func test_a_hero_joins_only_its_own_armys_host() -> void:
	var a_host := _unit(1, "A_host", "h1", "", 0.0)
	var a_hero := _unit(1, "A_hero", "hero1", "h1", 1.0)
	var b_host := _unit(2, "B_host", "h1", "", 30.0)
	var b_hero := _unit(2, "B_hero", "hero1", "h1", 31.0)
	var units: Dictionary = BattleSim.capture(_army([a_host, a_hero, b_host, b_hero]))["units"]
	assert_str(str((units["A_hero"] as Dictionary)["attached_to"])).is_equal("A_host")
	assert_str(str((units["B_hero"] as Dictionary)["attached_to"])).is_equal("B_host")
	assert_array((units["A_host"] as Dictionary)["attached"]).contains_exactly(["A_hero"])
	assert_array((units["B_host"] as Dictionary)["attached"]).contains_exactly(["B_hero"])
