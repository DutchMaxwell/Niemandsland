extends GdUnitTestSuite
## Phase-1 step 5a: AiPlanner.candidates — the tactical points the planner
## will roll out (plan D3). Hold always; hold+shoot only with a best-EV
## target; one rush per objective; charge only on a HURTABLE target (live
## futile-charge bar); one retreat point away from the nearest threat.

const IN2M := 0.0254


func _armed(pid: int, positions: Array, uid: String, weapons: Array,
		rules: Array = [], wounds_now := 1, quality := 4, defense := 4) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": quality,
		"defense": defense, "special_rules": rules}
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


func _state(units: Array, objectives: Array = []) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return objectives,
		func(_i: int) -> int: return 0)


func _of_kind(cands: Array, kind: int) -> Array:
	return cands.filter(func(c: Dictionary) -> bool: return int(c["kind"]) == kind)


func test_hold_plus_one_rush_per_objective_without_enemies() -> void:
	var objectives := [Vector3(10.0 * IN2M, 0, 0), Vector3(0, 0, 10.0 * IN2M)]
	var state := _state([_armed(2, [Vector3.ZERO], "Grunts",
		[{"name": "CCW", "range": 0}])], objectives)
	var cands := AiPlanner.candidates(state, "Grunts")
	assert_int(cands.size()).is_equal(4)   # no threat: no shoot/charge/retreat; +1 second-wave move-up (D23)
	assert_int(_of_kind(cands, AiDecision.Action.HOLD).size()).is_equal(1)
	var rushes := _of_kind(cands, AiDecision.Action.RUSH)
	assert_that(rushes.map(func(c: Dictionary) -> Vector3: return c["dest"])).is_equal(objectives)


func test_best_shoot_picks_the_softer_target() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter", [{"name": "Rifle", "range": 24}])
	var hard := _armed(1, [Vector3(12.0 * IN2M, 0, 0)], "Hard",
		[{"name": "CCW", "range": 0}], [], 1, 4, 2)
	var soft := _armed(1, [Vector3(0, 0, 12.0 * IN2M)], "Soft",
		[{"name": "CCW", "range": 0}], [], 1, 4, 5)
	var cands := AiPlanner.candidates(_state([shooter, hard, soft]), "Shooter")
	var shoots := cands.filter(func(c: Dictionary) -> bool: return c.has("shoot"))
	assert_int(shoots.size()).is_equal(1)
	assert_str(str((shoots[0] as Dictionary)["shoot"])).is_equal("Soft")


## T2: a blind target (captured LOS false) never becomes the shoot candidate —
## the pick falls to the seen one; both blind kills the shoot action entirely.
func test_best_shoot_skips_blind_targets() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter", [{"name": "Rifle", "range": 24}])
	var near := _armed(1, [Vector3(12.0 * IN2M, 0, 0)], "Near", [{"name": "CCW", "range": 0}])
	var far := _armed(1, [Vector3(0, 0, 18.0 * IN2M)], "Far", [{"name": "CCW", "range": 0}])
	var state := _state([shooter, near, far])
	(state["units"]["Shooter"] as Dictionary)["los"] = {"Near": false, "Far": true}
	var shoots := AiPlanner.candidates(state, "Shooter") \
		.filter(func(c: Dictionary) -> bool: return c.has("shoot"))
	assert_int(shoots.size()).is_equal(1)
	assert_str(str((shoots[0] as Dictionary)["shoot"])).is_equal("Far")
	(state["units"]["Shooter"] as Dictionary)["los"] = {"Near": false, "Far": false}
	assert_int(AiPlanner.candidates(state, "Shooter") \
		.filter(func(c: Dictionary) -> bool: return c.has("shoot")).size()).is_equal(0)


## Q6 fists vs a 2+ save: 4 * 1/6 * 1/6 = 0.11 expected wounds — under the
## live futile bar, so the tank must NEVER be a charge candidate. The 5+
## save ogre (0.44) is. Removing the ogre removes the charge entirely.
func test_charge_only_on_a_hurtable_target() -> void:
	var grunts := _armed(2, [Vector3.ZERO], "Grunts",
		[{"name": "Fists", "range": 0}], [], 1, 6, 4)
	var tank := _armed(1, [Vector3(6.0 * IN2M, 0, 0)], "Tank",
		[{"name": "CCW", "range": 0}], ["Tough(6)"], 6, 4, 2)
	var ogre := _armed(1, [Vector3(0, 0, 6.0 * IN2M)], "Ogre",
		[{"name": "CCW", "range": 0}], ["Tough(3)"], 3, 4, 5)
	var charges := _of_kind(AiPlanner.candidates(_state([grunts, tank, ogre]), "Grunts"),
		AiDecision.Action.CHARGE)
	assert_int(charges.size()).is_equal(1)
	assert_str(str((charges[0] as Dictionary)["charge"])).is_equal("Ogre")
	var without_ogre := AiPlanner.candidates(_state([grunts, tank]), "Grunts")
	assert_int(_of_kind(without_ogre, AiDecision.Action.CHARGE).size()).is_equal(0)


func test_retreat_points_away_from_the_nearest_threat() -> void:
	var grunts := _armed(2, [Vector3.ZERO], "Grunts", [{"name": "CCW", "range": 0}])
	var near := _armed(1, [Vector3(5.0 * IN2M, 0, 0)], "Near", [{"name": "CCW", "range": 0}])
	var far := _armed(1, [Vector3(-20.0 * IN2M, 0, 0)], "Far", [{"name": "CCW", "range": 0}])
	var advances := _of_kind(AiPlanner.candidates(_state([grunts, near, far]), "Grunts"),
		AiDecision.Action.ADVANCE)
	assert_int(advances.size()).is_equal(1)
	assert_float(((advances[0] as Dictionary)["dest"] as Vector3).x).is_less(0.0)


## D21/D23 — the second wave: a rear unit gets a follow-up candidate toward
## a CONTESTED marker (friend and enemy in the ring), stopping at support
## distance (next round's rush reaches it); with nothing contested and no
## battered friend, an idle rear unit still gets its move-up offer.
func test_second_wave_candidate_offers() -> void:
	var holder := _armed(1, [Vector3(1.0 * IN2M, 0, 0)], "Holder", [])
	var raider := _armed(2, [Vector3(2.0 * IN2M, 0, 0)], "Raider", [])
	var rear := _armed(1, [Vector3(-30.0 * IN2M, 0, 0)], "Rear", [])
	var state := _state([holder, raider, rear], [Vector3.ZERO])
	var cands := AiPlanner.candidates(state, "Rear")
	var wave := {}
	for c in cands:
		if str((c as Dictionary).get("wave", "")) != "":
			wave = c
	assert_str(str(wave.get("wave", ""))).is_equal("contested marker")
	var stop_in: float = ((wave["dest"] as Vector3) - Vector3.ZERO).length() / IN2M
	assert_float(stop_in).is_between(10.0, 20.0)   # 30" out, rush 12+2 => stop ~16" from goal
	# no contest, no battered friend -> idle reserve still moves up
	var lone := _armed(1, [Vector3(-30.0 * IN2M, 0, 0)], "Lone", [])
	var state2 := _state([lone], [Vector3.ZERO])
	var w2 := {}
	for c in AiPlanner.candidates(state2, "Lone"):
		if str((c as Dictionary).get("wave", "")) != "":
			w2 = c
	assert_str(str(w2.get("wave", ""))).is_equal("idle reserve moves up")
