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


## D9 (R11a): escort/extract verdicts — escort = the defender wins within 6" of
## the edge opposite the deploy edge, extract = the attacker wins within 6" of
## ANY edge; a carried marker is measured at the carrier's base edge. Twins of
## mission.rs escort_winner / extract_winner (same inches, same verdicts).
func _role_state(att: int, x_in: float, z_in: float) -> Dictionary:
	var u := _unit(2, [Vector3(100.0, 0, 100.0)], "Far")
	var state := _state([u], [Vector3(x_in * IN2M, 0, z_in * IN2M)], [0])
	state["attacker"] = att
	state["markers_meta"] = [{"carry": false, "carried_by": ""}]
	return state


func test_escort_winner_pins() -> void:
	assert_str(BattleSim.escort_winner(_role_state(1, 0.0, -18.0), 1, 48.0)).is_equal("p2")
	assert_str(BattleSim.escort_winner(_role_state(2, 0.0, -18.0), 1, 48.0)).is_equal("p1")
	assert_str(BattleSim.escort_winner(_role_state(1, 0.0, -17.0), 1, 48.0)).is_equal("p1")
	assert_str(BattleSim.escort_winner(_role_state(1, 0.0, 22.0), 1, 48.0)).is_equal("p1")


func test_escort_carried_marker_uses_the_carrier_base_edge() -> void:
	var carrier := _unit(1, [Vector3(0, 0, -17.5 * IN2M)], "Carrier")
	var state := _state([carrier], [Vector3.ZERO], [0])
	state["attacker"] = 1
	state["units"]["Carrier"]["radii"] = [1.0 * IN2M]
	state["markers_meta"] = [{"carry": true, "carried_by": "Carrier"}]
	assert_str(BattleSim.escort_winner(state, 1, 48.0)).is_equal("p2")
	state["units"]["Carrier"]["positions"] = [Vector3(0, 0, -16.5 * IN2M)]
	assert_str(BattleSim.escort_winner(state, 1, 48.0)).is_equal("p1")
	state["attacker"] = 0
	assert_str(BattleSim.escort_winner(state, 1, 48.0)).is_equal("draw")


func test_extract_winner_pins() -> void:
	assert_str(BattleSim.extract_winner(_role_state(1, 30.0, 0.0), 72.0, 48.0)).is_equal("p1")
	assert_str(BattleSim.extract_winner(_role_state(2, 0.0, 18.0), 72.0, 48.0)).is_equal("p2")
	assert_str(BattleSim.extract_winner(_role_state(1, 29.0, 0.0), 72.0, 48.0)).is_equal("p2")
	assert_str(BattleSim.extract_winner(_role_state(1, -30.0, -17.0), 72.0, 48.0)).is_equal("p1")


func test_role_winner_reads_the_scoring_id_and_skips_destroyed() -> void:
	var state := _role_state(1, 35.0, 0.0)
	assert_str(BattleSim.role_winner("extract", state, 0, 72.0, 48.0)).is_equal("p1")
	state["markers_meta"][0]["destroyed"] = true
	assert_str(BattleSim.role_winner("extract", state, 0, 72.0, 48.0)).is_equal("p2")
	assert_str(BattleSim.role_winner("end", state, 1, 72.0, 48.0)).is_equal("")


## D12c (R9a): the attacker's view of an unrevealed secret marker carries no `secret`, `carry` or
## `carried_by` (the relic's tell); the defender's view and a revealed marker keep them.
func _fog_state(viewer: int) -> Dictionary:
	var u := _unit(2, [Vector3(100.0, 0, 100.0)], "Far")
	SoloController.mission_markers = [
		{"secret": "relic", "revealed": false, "carry": true, "carried_by": ""},
		{"secret": "trap", "revealed": false},
		{"secret": "relic", "revealed": true, "carry": true, "carried_by": ""}]
	SoloController.mission_roles = {"attacker": 1, "defender": 2}
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Far": u}
	var pts := [Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)]
	return BattleSim.capture(army, func() -> Array: return pts, func(_i: int) -> int: return 0,
		1, 4, Callable(), Callable(), Callable(), viewer)


func test_the_attackers_capture_hides_unrevealed_secrets() -> void:
	var mm: Array = _fog_state(1)["markers_meta"]
	for i in range(2):
		for key in ["secret", "carry", "carried_by"]:
			assert_bool((mm[i] as Dictionary).has(key)).is_false()
		assert_bool(bool(mm[i]["revealed"])).is_false()
		assert_bool(bool(mm[i]["secret_hidden"])).is_true()
	assert_str(String(mm[2]["secret"])).is_equal("relic")
	SoloController.mission_reset("end", {})


func test_the_defenders_capture_and_the_unseated_capture_keep_the_secrets() -> void:
	for viewer in [2, 0]:
		var mm: Array = _fog_state(viewer)["markers_meta"]
		assert_str(String(mm[0]["secret"])).is_equal("relic")
		assert_bool(bool(mm[0]["carry"])).is_true()
		assert_str(String(mm[1]["secret"])).is_equal("trap")
	SoloController.mission_reset("end", {})
