extends GdUnitTestSuite
## R1 (round-rollout search): AiPlanner.rollout plays the rest of the round
## out under the cheap policy, alternating sides like the real rule. The tempo
## discriminator is the whole point: committing the valuable unit FIRST hands
## the un-activated enemy its reply; opening with the cheap unit makes the
## enemy commit before the valuable move, so the end-of-round rich leaf must
## prefer the cheap opener.

const IN2M := 0.0254


func _armed(pid: int, positions: Array, uid: String, weapons: Array) -> GameUnit:
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
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## Marker at 30" from a long-rifle gunline (range 36", 12 attacks = 3 expected
## wounds). My Striker starts 12" behind the marker — OUT of range until it
## rushes on. My Screamer is a worthless far-away single model (the cheap
## opener). Round 1 of 4.
func _state(round_no := 1, rounds_total := 4) -> Dictionary:
	var gunner := _armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)],
		"Gunner", [{"name": "LongRifle", "range": 36, "attacks": 12}])
	var striker := _armed(2, [Vector3(42.0 * IN2M, 0, 0), Vector3(43.0 * IN2M, 0, 0),
		Vector3(44.0 * IN2M, 0, 0), Vector3(45.0 * IN2M, 0, 0)],
		"Striker", [{"name": "CCW", "range": 0}])
	var screamer := _armed(2, [Vector3(60.0 * IN2M, 0, 30.0 * IN2M)], "Screamer",
		[{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Striker": striker, "Screamer": screamer}
	return BattleSim.capture(army, func() -> Array: return [Vector3(30.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, round_no, rounds_total)


func _leaf(state: Dictionary, me: int) -> float:
	return AiMissionEval.score(state, me, BattleSim.reply_threat(state, me))


func test_rollout_prefers_the_cheap_opener() -> void:
	var state := _state()
	var commit := {"unit": "Striker", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(30.0 * IN2M, 0, 0)}
	var bait := {"unit": "Screamer", "kind": AiDecision.Action.HOLD}
	var end_commit := AiPlanner.rollout(state, commit, 2)
	var end_bait := AiPlanner.rollout(state, bait, 2)
	# committing first: the un-activated gunline replies into the striker
	assert_int(int((end_commit["units"]["Striker"] as Dictionary)["alive"])).is_equal(1)
	# baiting first: the gunline must commit before the striker enters range
	assert_int(int((end_bait["units"]["Striker"] as Dictionary)["alive"])).is_equal(4)
	assert_float(_leaf(end_bait, 2)).is_greater(_leaf(end_commit, 2))


func test_rollout_activates_everyone_and_leaves_input_untouched() -> void:
	var state := _state()
	var end := AiPlanner.rollout(state,
		{"unit": "Screamer", "kind": AiDecision.Action.HOLD}, 2)
	for k in end["units"]:
		assert_bool((end["units"][k] as Dictionary)["activated"]) \
			.override_failure_message("%s must have activated by round end" % k).is_true()
	for k in state["units"]:
		assert_bool((state["units"][k] as Dictionary)["activated"]).is_false()


## R2, the pick-level discriminator ON THE LAST ROUND (endgame commit timing):
## the 1-ply plan() rushes the striker straight onto the marker into the
## waiting gunline; plan_with_rollout opens with the bait so the striker
## commits AFTER the gunline spent its activation.
func test_plan_with_rollout_baits_before_committing() -> void:
	var greedy := AiPlanner.plan(_state(4, 4), 2)
	assert_str(str(greedy["unit_key"])).is_equal("Striker")
	assert_int(int((greedy["action"] as Dictionary)["kind"])).is_equal(AiDecision.Action.RUSH)
	var pick := AiPlanner.plan_with_rollout(_state(4, 4), 2)
	assert_str(str(pick["unit_key"])).is_equal("Screamer")
	assert_int(int(pick["waits"])).is_equal(1)   # the striker is deliberately kept back
	# coverage guarantee: even the tiny budget finds the same bait line now
	assert_float(float((pick["expectation"] as Dictionary)["after"])) \
		.is_equal_approx(float((AiPlanner.plan_with_rollout(_state(4, 4), 2, 1)["expectation"] as Dictionary)["after"]), 0.0001)


## top_k <= 0 is the safety valve: byte-identical degrade to plan().
func test_top_k_zero_degrades_to_plain_plan() -> void:
	assert_that(AiPlanner.plan_with_rollout(_state(), 2, 0)).is_equal(AiPlanner.plan(_state(), 2))


## Diagnosis 07.08.: the mental game must be able to PUNISH commitment. A
## squad rushing the marker lands inside the brute's charge reach — in the
## rollout the brute counter-charges and the squad bleeds. Without charges in
## the policy the commit would look free (that bug drove real round-1 losses).
func test_rollout_opponent_counter_charges_commitment() -> void:
	var brute := _armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)],
		"Brute", [{"name": "Claws", "range": 0, "attacks": 12}])
	var squad := _armed(2, [Vector3(22.0 * IN2M, 0, 0), Vector3(23.0 * IN2M, 0, 0),
		Vector3(24.0 * IN2M, 0, 0), Vector3(25.0 * IN2M, 0, 0)],
		"Squad", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brute": brute, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3(10.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, 1, 4)
	var end := AiPlanner.rollout(state,
		{"unit": "Squad", "kind": AiDecision.Action.RUSH, "dest": Vector3(10.0 * IN2M, 0, 0)}, 2)
	assert_int(int((end["units"]["Squad"] as Dictionary)["alive"])) 		.override_failure_message("the brute must counter-charge the committed squad in the rollout") 		.is_less(4)


## Coverage guarantee: every un-activated unit gets a rollout even when the
## global TOP_K budget is 1 — bait moves rank low 1-ply and must never be
## prefiltered out of the tempo search.
func test_every_unit_is_rolled_out_even_with_tiny_top_k() -> void:
	var pick := AiPlanner.plan_with_rollout(_state(4, 4), 2, 1)
	var rolled: Array = pick["rolled_units"]
	rolled.sort()
	assert_that(rolled).is_equal(["Screamer", "Striker"])
	assert_str(str(pick["unit_key"])).is_equal("Screamer")   # the bait wins despite top_k=1
