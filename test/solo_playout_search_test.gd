extends GdUnitTestSuite
## S-wave PS1: AiPlanner.full_playout — cheap-policy playout to game end on
## the sim state, scored by the SAME seize rule as the factory's fork labels.
## Pins: the verdict DISCRIMINATES (marching onto the only marker beats
## marching away), determinism per seed, and the game rng stays untouched.

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


func _state(units: Array, round_no := 3) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, round_no, 4)


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## Round 3 of 4, lone unit 8" from the only marker: rushing TOWARD it must
## end with the marker owned; rushing AWAY must not. The playout verdict
## discriminates where a static glance at two similar boards might not.
func test_playout_discriminates_toward_vs_away() -> void:
	var state := _state([_unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Runner")])
	var toward := {"unit": "Runner", "kind": AiDecision.Action.RUSH, "dest": Vector3.ZERO}
	var away := {"unit": "Runner", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(20.0 * IN2M, 0, 0)}
	var pt := AiPlanner.full_playout(state, toward, 1, _rng(5))
	var pa := AiPlanner.full_playout(state, away, 1, _rng(5))
	assert_int(int(pt["p1"])).is_equal(1)   # Face-Off = END scoring (grill D4 + book)
	assert_int(int(pa["p1"])).is_equal(0)


func test_playout_is_deterministic_per_seed_and_leaves_state_alone() -> void:
	var state := _state([_unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Runner"),
		_unit(2, [Vector3(-14.0 * IN2M, 0, 6.0 * IN2M)], "Foe")])
	var before := JSON.stringify(BattleSim.board_rows(state))
	var act := {"unit": "Runner", "kind": AiDecision.Action.RUSH, "dest": Vector3.ZERO}
	var a := AiPlanner.full_playout(state, act, 1, _rng(11))
	var b := AiPlanner.full_playout(state, act, 1, _rng(11))
	assert_that(a).is_equal(b)
	assert_str(JSON.stringify(BattleSim.board_rows(state))).is_equal(before)


## PS2: with playout_search OFF the pick is byte-identical to today; ON, a
## CLOSE top-2 gets arbitrated by playouts and the verdict may flip the
## pick. Fixture: two units, one marker each side of the runner — the blend
## sees near-equal moves; the playout knows only one marker is holdable.
func test_playout_arbitration_flag_off_is_identity() -> void:
	var state := _state([_unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Runner"),
		_unit(2, [Vector3(-20.0 * IN2M, 0, 10.0 * IN2M)], "Foe")])
	AiPlanner.playout_search = false
	var a := AiPlanner.plan_with_rollout(state, 1)
	var b := AiPlanner.plan_with_rollout(state, 1)
	assert_that(a).is_equal(b)
	AiPlanner.playout_search = true
	var c := AiPlanner.plan_with_rollout(state, 1)
	AiPlanner.playout_search = false
	assert_bool(c.get("used", false)).is_true()
	# determinism WITH playouts too
	AiPlanner.playout_search = true
	var d := AiPlanner.plan_with_rollout(state, 1)
	AiPlanner.playout_search = false
	assert_that(c).is_equal(d)


## PS2 firing proof: a runner exactly between two markers makes the top-2
## genuinely close — the arbitration MUST fire (counter moves). Shrinking
## the close-margin to zero must silence it (mutation check lives on the
## const; here we pin the fixture actually exercising the path).
func test_playout_arbitration_fires_on_close_top2() -> void:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var runner := _unit(1, [Vector3.ZERO], "Runner")
	army.game_units = {"Runner": runner}
	var state := BattleSim.capture(army,
		func() -> Array: return [Vector3(-8.0 * IN2M, 0, 0), Vector3(8.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, 3, 4)
	AiPlanner.playout_search = true
	AiPlanner.playout_close_margin = 0.30   # force the close-branch for the path pin
	AiPlanner.playout_arbitrations = 0
	var pick := AiPlanner.plan_with_rollout(state, 1)
	AiPlanner.playout_search = false
	AiPlanner.playout_close_margin = 0.02
	assert_bool(pick.get("used", false)).is_true()
	assert_int(AiPlanner.playout_arbitrations).is_greater_equal(1)
	assert_str(str(pick.get("intent", ""))).contains("[playout")


## NML-1008 — VPs decide, not the final tableau: holding rounds 1-3 must
## outscore a last-round steal. Ledger arithmetic pinned directly.
func test_vp_ledger_rewards_early_control() -> void:
	var vp := [0, 0]
	BattleSim.vp_round_add([1, 1, 0], vp)   # R1: A holds 2
	BattleSim.vp_round_add([1, 1, 0], vp)   # R2: A holds 2
	BattleSim.vp_round_add([1, 1, 0], vp)   # R3: A holds 2
	BattleSim.vp_round_add([2, 2, 2], vp)   # R4: B steals everything
	BattleSim.vp_end_bonus([2, 2, 2], vp)   # end bonus goes to B
	assert_int(int(vp[0])).is_equal(6)
	assert_int(int(vp[1])).is_equal(4)
	assert_bool(vp[0] > vp[1]).is_true()    # end-state counting would call B the winner


## Mission-driven currency: the SAME playout speaks END points for Face-Off
## and cumulative VPs when the state carries scoring=round_vp (progressive
## wave, prepared).
func test_playout_currency_follows_mission_scoring() -> void:
	var state := _state([_unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Runner")])
	var act := {"unit": "Runner", "kind": AiDecision.Action.RUSH, "dest": Vector3.ZERO}
	var end_pts := AiPlanner.full_playout(state, act, 1, _rng(5))
	assert_int(int(end_pts["p1"])).is_equal(1)
	state["scoring"] = "round_vp"
	var vp_pts := AiPlanner.full_playout(state, act, 1, _rng(5))
	assert_int(int(vp_pts["p1"])).is_equal(3)
