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
	assert_int(int(pt["p1"])).is_equal(1)
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
