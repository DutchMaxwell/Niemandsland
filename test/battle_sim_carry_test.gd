extends GdUnitTestSuite
## NML-1010 wave C, step C1: escort / extract / role verdicts and the capture fog views
## (Relic Hunt, Capture & Hold). The pickup, carried-marker ownership, contested pickup,
## drop and attacker-only halves are the core's: core/nml-core/tests/mission.rs. Fixtures
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


## D14.5d (Rescue): an `attacker_only` relic is picked up only by the ATTACKER's units — the roles
## stamp `attacker` on the captured state; the defender's unit on the marker leaves it where it lies.
func test_an_attacker_only_relic_is_not_carried_by_the_defender() -> void:
	var infos := [{"unit_id": "H", "name": "H", "player": 1, "pos": Vector3(1.0 * IN2M, 0, 0), "models": [Vector3(1.0 * IN2M, 0, 0)], "radii": [0.016]}]
	SoloController.mission_roles = {"attacker": 2, "defender": 1}
	var live_markers := [{"carry": true, "carried_by": "", "attacker_only": true}]
	SoloController.carry_step(infos, [Vector3.ZERO], [1], live_markers)
	assert_str(String(live_markers[0]["carried_by"])).override_failure_message("live step: the defender may not carry").is_equal("")
	SoloController.mission_reset("end", {})
