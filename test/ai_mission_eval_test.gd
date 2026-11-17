extends GdUnitTestSuite
## What is left of the AiMissionEval suite (P4.D-96): the feature vector (AiMissionEval.features) that feeds the arena's position rows
## and the retraining pipeline. The mission currency itself (AiMissionEval.score and its roles, VP arm, fitted blend, net / linear /
## encoder overrides) is the core's: score.rs, fitted.rs, tests/mission.rs, the python test_fitted.py / test_parity.py and the
## gate A corpus (parity.rs gate_a_every_node_scores_within_1e_9). The v8 / linear / 1-hidden-layer net formats and the embedding
## cache are retired (only the Erlkoenig encoder net ships).

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


func _state(units: Array, objectives: Array, owners: Array,
		round_no := 1, rounds_total := 4) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return objectives,
		func(i: int) -> int: return owners[i], round_no, rounds_total)


## Hand-computed on a two-unit state (marker at the enemy Gunner): my Squad
## (4x1W, 12" rush) sits 20" out — beyond control ring + rush, so tail_mine
## stays 0 and its presence carries a 2-move discount; the enemy Gunner (3x1W)
## holds the ring: tail_theirs 1, full presence 3. Ownership: marker owned by
## the enemy counts once. The incoming map lands in my_incoming and thins my
## presence.
func test_features_hand_computed_two_unit_state() -> void:
	var gunner := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Gunner")
	var squad_pos: Array = []
	for i in range(4):
		squad_pos.append(Vector3((20.0 + i) * IN2M, 0, 0))
	var squad := _unit(2, squad_pos, "Squad")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 1, 2, 4)
	var f := AiMissionEval.features(state, 2, {"Squad": 1.0})
	assert_float(float(f.get("round_frac", -999.0))).is_equal_approx(0.5, 0.001)
	assert_float(float(f.get("my_wounds", -999.0))).is_equal_approx(4.0, 0.001)
	assert_float(float(f.get("their_wounds", -999.0))).is_equal_approx(3.0, 0.001)
	assert_float(float(f.get("my_units", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("their_unactivated", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("my_incoming", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("tail_mine", -999.0))).is_equal_approx(0.0, 0.001)
	assert_float(float(f.get("tail_theirs", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("obj_owned_theirs", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("obj_owned_mine", -999.0))).is_equal_approx(0.0, 0.001)
	# presence: squad 20" out, ring 3", rush 12 -> needed 2 -> (4-1)*0.25
	assert_float(float(f.get("presence_mine", -999.0))).is_equal_approx(0.75, 0.001)
	assert_float(float(f.get("presence_theirs", -999.0))).is_equal_approx(3.0, 0.001)


# === E4: fitted eval (NML-995) ===

## Charge exposure uses the R8 geometry (rush 12 + 1 contact, nearest model):
## a squad 10" from the enemy counts exposed, at 20" it does not; cover flags
## count per unit; the focus load is the largest single incoming entry.
func test_e5_features_exposure_cover_and_focus() -> void:
	var brute := _unit(1, [Vector3.ZERO], "Brute")
	var near := _unit(2, [Vector3(10.0 * IN2M, 0, 0)], "Near")
	var far := _unit(2, [Vector3(20.0 * IN2M, 0, 0)], "Far")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brute": brute, "Near": near, "Far": far}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 1, 4)
	(state["units"]["Near"] as Dictionary)["in_cover"] = true
	var f := AiMissionEval.features(state, 2, {"Near": 1.5, "Far": 0.5})
	assert_float(float(f.get("my_charge_exposed", -1.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("their_charge_exposed", -1.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("cover_mine", -1.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("cover_theirs", -1.0))).is_equal_approx(0.0, 0.001)
	assert_float(float(f.get("my_incoming_max", -1.0))).is_equal_approx(1.5, 0.001)
	assert_float(float(f.get("my_incoming", -1.0))).is_equal_approx(2.0, 0.001)


## Feature wave (net stage): the mirror threat, state counters and reserve
## stamp — each asserted in both directions so the check can fail.
func test_feature_wave_mirror_counts_and_reserves() -> void:
	var mine := _unit(1, [Vector3.ZERO], "Mine")
	var mopr := OPRApiClient.OPRUnit.new()
	var mw := OPRApiClient.OPRWeapon.new()
	mw.name = "Rifle"
	mw.range_value = 24
	mw.attacks = 2
	mine.source_type = "opr"
	mine.source_data = mopr
	mopr.weapons.append(mw)
	var theirs := _unit(2, [Vector3(14.0 * IN2M, 0, 0)], "Theirs")
	var state := _state([mine, theirs], [Vector3.ZERO], [0])
	(state["units"]["Theirs"] as Dictionary)["shaken"] = true
	(state["units"]["Mine"] as Dictionary)["fatigued"] = true
	state["reserves"] = {1: 2, 2: 0}
	var f := AiMissionEval.features(state, 1, {}, true)
	assert_float(float(f["their_incoming"])).is_greater(0.0)   # my rifle projects onto them
	assert_float(float(f["their_shaken"])).is_equal(1.0)
	assert_float(float(f["my_shaken"])).is_equal(0.0)
	assert_float(float(f["my_fatigued"])).is_equal(1.0)
	assert_float(float(f["my_reserve"])).is_equal(2.0)
	assert_float(float(f["their_reserve"])).is_equal(0.0)
	# Counter-probe: seen from side 2 the mirror threat is MY rifle's absence.
	var f2 := AiMissionEval.features(state, 2, {}, true)
	assert_float(float(f2["their_incoming"])).is_equal(0.0)   # side 2 has no ranged weapon
	assert_float(float(f2["my_reserve"])).is_equal(0.0)


## Melee magnitude: an armed charger in reach raises my_melee_in; out of
## reach it contributes nothing (and the binary exposure flag matches).
func test_melee_magnitude_tracks_the_worst_charger() -> void:
	var brute := _unit(2, [Vector3(8.0 * IN2M, 0, 0)], "Brute")
	var bopr := OPRApiClient.OPRUnit.new()
	var bw := OPRApiClient.OPRWeapon.new()
	bw.name = "Claws"
	bw.range_value = 0
	bw.attacks = 6
	brute.source_type = "opr"
	brute.source_data = bopr
	bopr.weapons.append(bw)
	var target := _unit(1, [Vector3.ZERO], "Target")
	var near := _state([target, brute], [Vector3.ZERO], [0])
	var fn := AiMissionEval.features(near, 1, {}, true)
	assert_float(float(fn["my_charge_exposed"])).is_equal(1.0)
	assert_float(float(fn["my_melee_in"])).is_greater(0.0)
	for m in brute.models:
		(m as ModelInstance).node.global_position = Vector3(40.0 * IN2M, 0, 0)
	var far := _state([target, brute], [Vector3.ZERO], [0])
	var ff := AiMissionEval.features(far, 1, {}, true)
	assert_float(float(ff["my_charge_exposed"])).is_equal(0.0)
	assert_float(float(ff["my_melee_in"])).is_equal(0.0)


## Morale proximity: just above half strength counts as near-half; full
## strength does not.
func test_near_half_counts_the_cliff_edge() -> void:
	var squad := _unit(1, [Vector3.ZERO, Vector3(IN2M, 0, 0)], "Squad")
	for m in squad.models:
		(m as ModelInstance).wounds_max = 5
	var state := _state([squad], [Vector3.ZERO], [0])
	(state["units"]["Squad"] as Dictionary)["wounds"] = [5, 1]   # 6 of 10 = 60%
	var f := AiMissionEval.features(state, 1, {})
	assert_float(float(f["my_near_half"])).is_equal(1.0)
	(state["units"]["Squad"] as Dictionary)["wounds"] = [5, 5]   # full strength
	var f2 := AiMissionEval.features(state, 1, {})
	assert_float(float(f2["my_near_half"])).is_equal(0.0)


## HEAD_QUEUE #13: the tail counter is a MARKER forecast — "this unit can still
## reach the ring this round". So it has to use the referee's eligibility set,
## not a hand-copied pair of checks. An Aircraft never holds, and a unit that
## landed from Ambush THIS round may act but may not seize (v3.5.1 p.13); both
## used to be counted as tail runners, which paid the planner for a hold that
## the round end would never book. Rows 1 and 4 are the counter-probe, so a
## gate that is simply always shut cannot pass as a fix.
func test_tail_uses_the_referees_eligibility_set() -> void:
	var state := _state([_unit(1, [Vector3(4.0 * IN2M, 0, 0)], "Runner")],
		[Vector3.ZERO], [0], 2)
	var su: Dictionary = state["units"]["Runner"]
	var tail := func() -> float:
		return float(AiMissionEval.features(state, 1).get("tail_mine", -999.0))
	assert_float(tail.call()).is_equal_approx(1.0, 0.001)       # 4" out, 12" rush
	su["aircraft"] = true
	assert_float(tail.call()).is_equal_approx(0.0, 0.001)
	su["aircraft"] = false
	su["ambush_arrived_round"] = 2                              # landed this round
	assert_float(tail.call()).is_equal_approx(0.0, 0.001)
	su["ambush_arrived_round"] = 1                              # landed last round
	assert_float(tail.call()).is_equal_approx(1.0, 0.001)


func after_test() -> void:
	AiMissionEval.eval_variant = 0
