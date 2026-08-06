extends GdUnitTestSuite
## BattleSim.resolve, movement half (phase-1 step 2a). One activation resolved
## on a CLONE: the whole unit translates toward the goal, clamped by the
## official move band (advance 6" / rush+charge 12" for plain infantry); the
## input state stays untouched; the actor comes back activation-spent.

const IN2M := 0.0254


func _state_with_grunts() -> Dictionary:
	var u := GameUnit.new()
	u.unit_id = "Grunts"
	u.unit_properties = {"player_id": 2, "name": "Grunts", "quality": 4, "defense": 4,
		"special_rules": []}
	for x in [0.0, 1.0]:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(x * IN2M, 0, 0)
		m.node = n
		u.models.append(m)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Grunts": u}
	return BattleSim.capture(army)


func _centre(state: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	var ps: Array = (state["units"]["Grunts"] as Dictionary)["positions"]
	for p in ps:
		c += p as Vector3
	return c / ps.size()


func test_bands_clamp_toward_a_far_goal() -> void:
	var state := _state_with_grunts()
	var goal := Vector3(30.0 * IN2M, 0, 0.5 * IN2M)   # ~29.5" out — beyond every band
	var start := _centre(state)
	for pair in [[AiDecision.Action.ADVANCE, 6.0], [AiDecision.Action.RUSH, 12.0],
			[AiDecision.Action.CHARGE, 12.0]]:
		var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": pair[0], "dest": goal})
		var moved: float = (_centre(next) - start).length() / IN2M
		assert_float(moved).is_equal_approx(pair[1], 0.01)
	var hold := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.HOLD,
		"dest": goal})
	assert_that(_centre(hold)).is_equal(start)


func test_goal_within_band_is_reached_exactly_and_coherence_kept() -> void:
	var state := _state_with_grunts()
	var goal := Vector3(4.0 * IN2M, 0, 0)
	var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.ADVANCE,
		"dest": goal})
	assert_that(_centre(next)).is_equal(goal)
	var ps: Array = (next["units"]["Grunts"] as Dictionary)["positions"]
	var gap: float = ((ps[1] as Vector3) - (ps[0] as Vector3)).length() / IN2M
	assert_float(gap).is_equal_approx(1.0, 0.001)   # rigid translate keeps the formation


func _armed(pid: int, positions: Array, uid: String, weapons: Array,
		rules: Array = [], wounds_now: int = 1) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = wounds_now
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


func _capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)


## Hand-computed: 4 attacks, Q4+ (hit 0.5), Def4+ AP0 (unsaved 0.5) = 1.0
## expected wound -> exactly one 1W model dies. The SAME shot into cover
## (save 3+) = 0.67 -> floored to zero models.
func test_shoot_kills_by_expectation_and_cover_saves() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter", [{"name": "Rifle", "range": 24}])
	var targets: Array = []
	for i in range(4):
		targets.append(Vector3((12.0 + i) * IN2M, 0, 0))
	var squad := _armed(1, targets, "Squad", [{"name": "Rifle", "range": 24}])
	var state := _capture([shooter, squad])
	var action := {"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Squad"}
	assert_int(int((BattleSim.resolve(state, action)["units"]["Squad"] as Dictionary)["alive"])).is_equal(3)
	(state["units"]["Squad"] as Dictionary)["in_cover"] = true
	assert_int(int((BattleSim.resolve(state, action)["units"]["Squad"] as Dictionary)["alive"])).is_equal(4)


## Charge into Tough(3): 1.0 expected wound drains the pool (3 -> 2), no kill.
## The survivor strikes back with the same fists -> the 1W charger dies; the
## charge marks the actor fatigued on the clone.
func test_charge_drains_tough_pool_and_strike_back_answers() -> void:
	var grunts := _armed(2, [Vector3.ZERO], "Grunts", [{"name": "CCW", "range": 0}])
	var ogre := _armed(1, [Vector3(8.0 * IN2M, 0, 0)], "Ogre", [{"name": "Claws", "range": 0}],
		["Tough(3)"], 3)
	var state := _capture([grunts, ogre])
	var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(8.0 * IN2M, 0, 0), "charge": "Ogre"})
	var o: Dictionary = next["units"]["Ogre"]
	assert_int(int(o["alive"])).is_equal(1)
	assert_int(int(o["wounds"][0])).is_equal(2)
	var g: Dictionary = next["units"]["Grunts"]
	assert_int(int(g["alive"])).is_equal(0)
	assert_bool(g["fatigued"]).is_true()


func test_unreachable_charge_moves_but_never_fights() -> void:
	var grunts := _armed(2, [Vector3.ZERO], "Grunts", [{"name": "CCW", "range": 0}])
	var far := _armed(1, [Vector3(30.0 * IN2M, 0, 0)], "Far", [{"name": "CCW", "range": 0}])
	var next := BattleSim.resolve(_capture([grunts, far]),
		{"unit": "Grunts", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(30.0 * IN2M, 0, 0), "charge": "Far"})
	assert_int(int((next["units"]["Far"] as Dictionary)["alive"])).is_equal(1)
	var g: Dictionary = next["units"]["Grunts"]
	assert_bool(g["fatigued"]).is_false()
	assert_float(((g["positions"][0] as Vector3)).x / IN2M).is_equal_approx(12.0, 0.01)


func test_resolve_spends_activation_on_the_clone_only() -> void:
	var state := _state_with_grunts()
	var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.ADVANCE,
		"dest": Vector3(4.0 * IN2M, 0, 0)})
	assert_bool((next["units"]["Grunts"] as Dictionary)["activated"]).is_true()
	assert_bool((state["units"]["Grunts"] as Dictionary)["activated"]).is_false()
	assert_that(_centre(state)).is_equal(Vector3(0.5 * IN2M, 0, 0))
