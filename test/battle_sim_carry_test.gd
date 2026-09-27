extends GdUnitTestSuite
## NML-1010 wave C, step C1: BattleSim.apply_carry_step / drop_carried / the
## carried branch of playout_seize (Relic Hunt, Capture & Hold). Fixtures
## follow ai_mission_eval_test.gd's style (real GameUnit + BattleSim.capture).

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _state(units: Array, objectives: Array, owners: Array, round_no := 1) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return objectives,
		func(i: int) -> int: return owners[i], round_no, 4)


## The seizing side's NEAREST eligible unit becomes the carrier, and the
## marker's position moves onto it.
func test_pickup_by_the_nearest() -> void:
	var near := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "Near")
	var far := _unit(1, [Vector3(2.9 * IN2M, 0, 0)], "Far")
	var state := _state([near, far], [Vector3.ZERO], [1])
	var markers := [{"carry": true, "carried_by": ""}]
	var owners := [1]
	BattleSim.apply_carry_step(state, markers, owners)
	assert_str(String(markers[0]["carried_by"])).is_equal("Near")
	assert_vector(state["objectives"][0]["pos"]).is_equal_approx(
		Vector3(1.0 * IN2M, 0, 0), Vector3(0.001, 0.001, 0.001))


## Equal gap: the tie goes to whichever unit `state["units"]` iterates FIRST
## (capture order). RED: swapping the `<` for `<=` in apply_carry_step's scan
## makes the LAST equal-gap unit win instead, and this test dies.
func test_pickup_tie_goes_to_capture_order() -> void:
	var first := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "First")
	var second := _unit(1, [Vector3(-1.0 * IN2M, 0, 0)], "Second")
	var state := _state([first, second], [Vector3.ZERO], [1])
	var markers := [{"carry": true, "carried_by": ""}]
	BattleSim.apply_carry_step(state, markers, [1])
	assert_str(String(markers[0]["carried_by"])).is_equal("First")


## Once carried, playout_seize hands the marker to the carrier's side no
## matter the ring — the carrier can stand 20" away from the marker's own
## recorded position and still own it, as long as it is alive and unshaken.
func test_carried_marker_is_owned_regardless_of_ring() -> void:
	var carrier := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], "Carrier")
	var state := _state([carrier], [Vector3.ZERO], [0])
	state["markers_meta"] = [{"carry": true, "carried_by": "Carrier"}]
	var owners := [0]
	BattleSim.playout_seize(state, owners)
	assert_int(owners[0]).is_equal(1)


## A shaken carrier no longer holds the marker — playout_seize falls back to
## the ordinary ring test, which finds nobody near.
func test_shaken_carrier_stops_owning_it() -> void:
	var carrier := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], "Carrier")
	var state := _state([carrier], [Vector3.ZERO], [0])
	(state["units"]["Carrier"] as Dictionary)["shaken"] = true
	state["markers_meta"] = [{"carry": true, "carried_by": "Carrier"}]
	var owners := [0]
	BattleSim.playout_seize(state, owners)
	assert_int(owners[0]).is_equal(0)


## A marker BOTH sides contest this round (owners[i] == 0, neutral) is never
## picked up, even though a `carry` flag is set — the book's seize must
## resolve to one side first.
func test_no_pickup_while_contested() -> void:
	var p1 := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "P1")
	var p2 := _unit(2, [Vector3(-1.0 * IN2M, 0, 0)], "P2")
	var state := _state([p1, p2], [Vector3.ZERO], [0])
	var markers := [{"carry": true, "carried_by": ""}]
	BattleSim.apply_carry_step(state, markers, [0])
	assert_str(String(markers[0]["carried_by"])).is_equal("")


## drop_carried clears carried_by and moves the marker's position to the
## drop point; a marker carried by a DIFFERENT unit is untouched.
func test_drop_carried_moves_the_marker_and_clears_the_flag() -> void:
	var objectives := [{"pos": Vector3(1.0 * IN2M, 0, 0)}, {"pos": Vector3(5.0 * IN2M, 0, 0)}]
	var markers := [{"carry": true, "carried_by": "Carrier"}, {"carry": true, "carried_by": "Other"}]
	BattleSim.drop_carried(markers, objectives, "Carrier", Vector3(9.0 * IN2M, 0, 0))
	assert_str(String(markers[0]["carried_by"])).is_equal("")
	assert_vector(objectives[0]["pos"]).is_equal_approx(
		Vector3(9.0 * IN2M, 0, 0), Vector3(0.001, 0.001, 0.001))
	assert_str(String(markers[1]["carried_by"])).is_equal("Other")
