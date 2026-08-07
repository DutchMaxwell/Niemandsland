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
func _state() -> Dictionary:
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
		func(_i: int) -> int: return 0, 1, 4)


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
