extends GdUnitTestSuite
## BattleSim.capture — phase-1 planner substrate, step 1. The snapshot must
## (a) map the dynamic game state faithfully (alive models only, wounds, flags,
## objective owners) and (b) be a COPY: editing it never touches the scene, and
## later scene changes never leak into an already-taken snapshot.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
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


func test_capture_maps_units_flags_and_objectives() -> void:
	var grunts := _unit(2, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Grunts")
	grunts.models[1].is_alive = false          # dead models never enter the snapshot
	grunts.models[2].wounds_current = 3
	grunts.is_shaken = true
	grunts.is_activated = true
	var tank := _unit(1, [Vector3(10.0 * IN2M, 0, 0)], "Tank")
	tank.casts_current = 2
	var objs := [Vector3(5.0 * IN2M, 0, 0), Vector3(15.0 * IN2M, 0, 0)]
	var owners := [0, 1]
	var state := BattleSim.capture(_army([grunts, tank]),
		func() -> Array: return objs, func(i: int) -> int: return owners[i], 2, 4)
	assert_int(state["round"]).is_equal(2)
	var g: Dictionary = state["units"]["Grunts"]
	assert_int(g["alive"]).is_equal(2)
	assert_that(g["positions"][1]).is_equal(Vector3(2.0 * IN2M, 0, 0))
	assert_int(g["wounds"][1]).is_equal(3)
	assert_bool(g["shaken"]).is_true()
	assert_bool(g["activated"]).is_true()
	assert_object(g["unit"]).is_same(grunts)
	var t: Dictionary = state["units"]["Tank"]
	assert_int(t["player"]).is_equal(1)
	assert_int(t["casts"]).is_equal(2)
	assert_that((state["objectives"][1] as Dictionary)["owner"]).is_equal(1)


func test_snapshot_is_a_copy_in_both_directions() -> void:
	var grunts := _unit(2, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0)], "Grunts")
	var army := _army([grunts])
	var state := BattleSim.capture(army)
	var g: Dictionary = state["units"]["Grunts"]
	g["positions"][0] = Vector3(99, 0, 0)      # rollout edits...
	g["wounds"][0] = 7
	assert_that(grunts.models[0].node.global_position).is_equal(Vector3.ZERO)
	assert_int(grunts.models[0].wounds_current).is_equal(1)
	grunts.models[1].is_alive = false          # ...and later scene changes
	assert_int(int((BattleSim.capture(army)["units"]["Grunts"] as Dictionary)["alive"])).is_equal(1)
	assert_int(g["alive"]).is_equal(2)
