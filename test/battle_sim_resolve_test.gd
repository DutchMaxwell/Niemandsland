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


## T2: a walled pair (captured LOS false) never trades wounds in expectation —
## resolve leaves the target untouched; the same shot with LOS lands as before.
func test_resolve_gates_shooting_on_captured_los() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter", [{"name": "Rifle", "range": 24}])
	var targets: Array = []
	for i in range(4):
		targets.append(Vector3((12.0 + i) * IN2M, 0, 0))
	var squad := _armed(1, targets, "Squad", [{"name": "Rifle", "range": 24}])
	var state := _capture([shooter, squad])
	(state["units"]["Shooter"] as Dictionary)["los"] = {"Squad": false}
	var action := {"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Squad"}
	assert_int(int((BattleSim.resolve(state, action)["units"]["Squad"] as Dictionary)["alive"])).is_equal(4)
	(state["units"]["Shooter"] as Dictionary)["los"] = {"Squad": true}
	assert_int(int((BattleSim.resolve(state, action)["units"]["Squad"] as Dictionary)["alive"])).is_equal(3)


## T2b: a mover's in_cover follows it through the rollout — stamped from the
## terrain probe at the NEW unit centre; without a probe the captured flag
## stays frozen (pre-T2b behaviour).
func test_move_restamps_cover_from_the_terrain_probe() -> void:
	var state := _state_with_grunts()
	# forest patch around x = 6", nothing anywhere else
	(state as Dictionary)["terrain_at"] = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.FOREST \
			if absf(p.x / IN2M - 6.0) < 2.0 and absf(p.z) < 2.0 * IN2M else TerrainRules.TerrainType.NONE
	var into := BattleSim.resolve(state, {"unit": "Grunts",
		"kind": AiDecision.Action.ADVANCE, "dest": Vector3(6.0 * IN2M, 0, 0)})
	assert_bool((into["units"]["Grunts"] as Dictionary)["in_cover"]).is_true()
	var out := BattleSim.resolve(into, {"unit": "Grunts",
		"kind": AiDecision.Action.RUSH, "dest": Vector3(30.0 * IN2M, 0, 0)})
	assert_bool((out["units"]["Grunts"] as Dictionary)["in_cover"]).is_false()
	state.erase("terrain_at")
	(state["units"]["Grunts"] as Dictionary)["in_cover"] = true
	var frozen := BattleSim.resolve(state, {"unit": "Grunts",
		"kind": AiDecision.Action.RUSH, "dest": Vector3(30.0 * IN2M, 0, 0)})
	assert_bool((frozen["units"]["Grunts"] as Dictionary)["in_cover"]).is_true()


## Danger term: every living enemy replies once with its best-EV shot. Rifle
## Q4 vs Def4 at 12": 4 * 0.5 * 0.5 = 1.0 expected wound on the open target;
## the covered twin (save 3+) is only worth 0.67, so the open one is picked.
## Blocking the open target's sight line shifts the reply to the covered one;
## blind to both = no threat at all.
func test_reply_threat_picks_best_visible_target() -> void:
	var enemy := _armed(1, [Vector3.ZERO], "Enemy", [{"name": "Rifle", "range": 24}])
	var open := _armed(2, [Vector3(12.0 * IN2M, 0, 0)], "Open", [{"name": "CCW", "range": 0}])
	var covered := _armed(2, [Vector3(0, 0, 12.0 * IN2M)], "Covered", [{"name": "CCW", "range": 0}])
	var state := _capture([enemy, open, covered])
	(state["units"]["Covered"] as Dictionary)["in_cover"] = true
	var threat := BattleSim.reply_threat(state, 2)
	assert_that(threat.keys()).is_equal(["Open"])
	assert_float(threat["Open"]).is_equal_approx(1.0, 0.001)
	(state["units"]["Enemy"] as Dictionary)["los"] = {"Open": false, "Covered": true}
	threat = BattleSim.reply_threat(state, 2)
	assert_that(threat.keys()).is_equal(["Covered"])
	assert_float(threat["Covered"]).is_equal_approx(2.0 / 3.0, 0.001)
	(state["units"]["Enemy"] as Dictionary)["los"] = {"Open": false, "Covered": false}
	assert_that(BattleSim.reply_threat(state, 2)).is_equal({})


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


# === Morale in expectation (parity wave step 2a, NML-995) ===

## Hand-computed: 8 attacks Q4 (hit 0.5) into Def4 (unsaved 0.5) = 2.0 wounds
## -> 2 of 4 models die -> at half. Q4's fail chance (50%) breaks in
## expectation; Q3 (33%) and Fearless-Q4 (25%) hold. Rout never — shooting
## fails are SHAKEN only (playtest bug 9).
func test_shooting_to_half_shakes_q4_but_not_q3_or_fearless() -> void:
	for cfg in [[4, [], true], [3, [], false], [4, ["Fearless"], false]]:
		var shooter := _armed(2, [Vector3.ZERO], "Shooter",
			[{"name": "Rifle", "range": 24, "attacks": 8}])
		var squad_pos: Array = []
		for i in range(4):
			squad_pos.append(Vector3((12.0 + i) * IN2M, 0, 0))
		var squad := _armed(1, squad_pos, "Squad", [{"name": "Rifle", "range": 24}], cfg[1])
		squad.unit_properties["quality"] = cfg[0]
		var state := _capture([shooter, squad])
		var next := BattleSim.resolve(state,
			{"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Squad"})
		var sq: Dictionary = next["units"]["Squad"]
		assert_int(int(sq["alive"])).is_equal(2)
		assert_bool(bool(sq.get("shaken", false))).override_failure_message(
			"Q%d rules=%s expected shaken=%s" % [cfg[0], cfg[1], cfg[2]]).is_equal(cfg[2])
		assert_bool(bool((state["units"]["Squad"] as Dictionary).get("shaken", false))).is_false()


## A volley that leaves the squad ABOVE half (1 of 4 dead) never tests — no
## shaken flag even for Q4 (the p.10 trigger needs casualties AND <= half).
func test_shooting_above_half_never_tests() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter", [{"name": "Rifle", "range": 24}])
	var squad_pos: Array = []
	for i in range(4):
		squad_pos.append(Vector3((12.0 + i) * IN2M, 0, 0))
	var squad := _armed(1, squad_pos, "Squad", [{"name": "Rifle", "range": 24}])
	var next := BattleSim.resolve(_capture([shooter, squad]),
		{"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Squad"})
	var sq: Dictionary = next["units"]["Squad"]
	assert_int(int(sq["alive"])).is_equal(3)
	assert_bool(bool(sq.get("shaken", false))).is_false()


## Single-model units measure morale in TOUGH WOUNDS (p.10): a Tough(6) hero
## shot from 6 to 3 wounds is at half its tough value and shakes at Q4.
func test_single_model_tough_tests_on_the_wounds_scale() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter",
		[{"name": "Cannon", "range": 24, "attacks": 12}])
	var hero := _armed(1, [Vector3(12.0 * IN2M, 0, 0)], "Hero",
		[{"name": "Rifle", "range": 24}], ["Tough(6)"], 6)
	(hero.models[0] as ModelInstance).wounds_max = 6
	var next := BattleSim.resolve(_capture([shooter, hero]),
		{"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Hero"})
	var h: Dictionary = next["units"]["Hero"]
	assert_int(int(h["wounds"][0])).is_equal(3)
	assert_bool(bool(h.get("shaken", false))).is_true()


## Shaken recovery (p.10): the bare recovery hold clears Shaken on the clone —
## the mental game no longer treats a shaken unit as shaken forever.
func test_hold_recovers_shaken_on_the_clone() -> void:
	var state := _state_with_grunts()
	(state["units"]["Grunts"] as Dictionary)["shaken"] = true
	var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.HOLD})
	assert_bool(bool((next["units"]["Grunts"] as Dictionary)["shaken"])).is_false()
	assert_bool(bool((state["units"]["Grunts"] as Dictionary)["shaken"])).is_true()


# === Melee morale in expectation (parity wave step 2b, NML-995) ===

## Hand-computed: 4 attacks Q4 into Def4 = 1.0 wound -> 1 of 2 victims dies
## (at half); the club's 1 attack strikes back for 0.25 -> floored to none.
## Loser (fewer wounds dealt) tests, Q4 fails at/below half => ROUT — the
## unit leaves the board. The winner stands untouched.
func test_melee_loser_at_half_routs_winner_stands() -> void:
	var brutes := _armed(2, [Vector3.ZERO], "Brutes", [{"name": "Fists", "range": 0}])
	var victims := _armed(1, [Vector3(8.0 * IN2M, 0, 0), Vector3(9.0 * IN2M, 0, 0)],
		"Victims", [{"name": "Club", "range": 0, "attacks": 1}])
	var next := BattleSim.resolve(_capture([brutes, victims]),
		{"unit": "Brutes", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(8.0 * IN2M, 0, 0), "charge": "Victims"})
	var v: Dictionary = next["units"]["Victims"]
	assert_int(int(v["alive"])).is_equal(0)
	assert_int((v["positions"] as Array).size()).is_equal(0)
	var b: Dictionary = next["units"]["Brutes"]
	assert_int(int(b["alive"])).is_equal(1)
	assert_bool(bool(b.get("shaken", false))).is_false()


## The same loss ABOVE half (1 of 4 dead) is only SHAKEN — Rout needs half or
## less even in melee.
func test_melee_loser_above_half_is_shaken() -> void:
	var brutes := _armed(2, [Vector3.ZERO], "Brutes", [{"name": "Fists", "range": 0}])
	var pos: Array = []
	for i in range(4):
		pos.append(Vector3((8.0 + i) * IN2M, 0, 0))
	var victims := _armed(1, pos, "Victims", [{"name": "Club", "range": 0, "attacks": 1}])
	var next := BattleSim.resolve(_capture([brutes, victims]),
		{"unit": "Brutes", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(8.0 * IN2M, 0, 0), "charge": "Victims"})
	var v: Dictionary = next["units"]["Victims"]
	assert_int(int(v["alive"])).is_equal(3)
	assert_bool(bool(v.get("shaken", false))).is_true()


## A wound-for-wound tie (here: 0 vs 0 — both clubs floor to nothing) tests
## nobody; the charge still fatigues the charger.
func test_melee_tie_tests_nobody() -> void:
	var a := _armed(2, [Vector3.ZERO], "A", [{"name": "Club", "range": 0, "attacks": 1}])
	var b := _armed(1, [Vector3(8.0 * IN2M, 0, 0)], "B", [{"name": "Club", "range": 0, "attacks": 1}])
	var next := BattleSim.resolve(_capture([a, b]),
		{"unit": "A", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(8.0 * IN2M, 0, 0), "charge": "B"})
	assert_bool(bool((next["units"]["A"] as Dictionary).get("shaken", false))).is_false()
	assert_bool(bool((next["units"]["B"] as Dictionary).get("shaken", false))).is_false()
	assert_int(int((next["units"]["B"] as Dictionary)["alive"])).is_equal(1)
	assert_bool(bool((next["units"]["A"] as Dictionary)["fatigued"])).is_true()
