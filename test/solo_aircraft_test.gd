extends GdUnitTestSuite
## AIRCRAFT (GF Advanced Rules v3.5.1 special rule; AI plausibility wave 1) — system-scoped via the
## RulesRegistry mechanics maps (the rule is printed in GF v3.5.1 only; verified against the official
## PDFs: no Aircraft in AoF / AoFS / AoFR / GFF v3.5.1). Pins, per rulebook example:
##   • the mandatory move: a straight line, the AI's fixed 30", flown in FULL — even Shaken;
##   • lane legality: the whole straight move must fit on the table (no edge-shortening);
##   • can never seize or contest an objective marker;
##   • can never be charged (a melee-only enemy has no valid path to it at all);
##   • units targeting an aircraft get -12" to their range (the aircraft's own guns are unaffected).

const IN2M := 0.0254


func _unit(pid: int, positions: Array, rules: Array = [], uid: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": 4, "defense": 4, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	return army


func _controller(units: Array) -> SoloController:
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(_army(units), null, null, 1, 2)
	return sc


func _arm(u: GameUnit, weapons: Array) -> void:
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 2))
		ow.count = 1
		for r in (w as Dictionary).get("rules", []):
			ow.special_rules.append(str(r))
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr


# === System scoping (the registry pattern: the rule fires only where the book fields it) ===

func test_is_aircraft_fires_for_gf_and_not_for_fantasy_books() -> void:
	var gf_air := _unit(1, [Vector3.ZERO], ["Aircraft", "Tough(6)"])
	assert_bool(SoloController.is_aircraft(gf_air)).is_true()   # default system resolves to gf
	var aof_air := _unit(1, [Vector3.ZERO], ["Aircraft"])
	aof_air.unit_properties["game_system"] = "aof"
	assert_bool(SoloController.is_aircraft(aof_air)).is_false() # AoF v3.5.1 prints no Aircraft rule
	var ground := _unit(1, [Vector3.ZERO], ["Fast"])
	assert_bool(SoloController.is_aircraft(ground)).is_false()
	assert_bool(SoloController.is_aircraft(null)).is_false()


func test_target_range_penalty_is_twelve_inches_against_aircraft_only() -> void:
	var air := _unit(1, [Vector3.ZERO], ["Aircraft"])
	assert_float(SoloController.target_range_penalty_in(air)).is_equal_approx(12.0, 0.001)
	var ground := _unit(1, [Vector3.ZERO])
	assert_float(SoloController.target_range_penalty_in(ground)).is_equal_approx(0.0, 0.001)


# === Rulebook example: the mandatory straight move — full 30", even Shaken ===

func test_aircraft_flies_its_full_straight_lane() -> void:
	# Aircraft at mid-west of the default 48"x48" table; one enemy to the east. The activation must
	# displace the model by EXACTLY the fixed 30" (the mandatory move), in a straight line.
	var air := _unit(2, [Vector3(-0.45, 0, 0)], ["Aircraft"], "Gunship")
	_arm(air, [{"name": "Minigun", "range": 24, "attacks": 4, "rules": ["AP(1)"]}])
	var enemy := _unit(1, [Vector3(0.45, 0, 0)], [], "Grunts")
	var sc := _controller([air, enemy])
	var start: Vector3 = (air.models[0] as ModelInstance).node.global_position
	var unit := sc.activate_next_ai_unit()
	assert_object(unit).is_same(air)
	var end: Vector3 = (air.models[0] as ModelInstance).node.global_position
	var flown_in := start.distance_to(end) / IN2M
	assert_float(flown_in).is_equal_approx(30.0, 0.1)
	assert_bool(bool(sc.last_report.get("aircraft", false))).is_true()
	# Advance-only: the report's action is ADVANCE, never Rush/Charge/Hold.
	assert_int(int(sc.last_report.get("action", -1))).is_equal(AiDecision.Action.ADVANCE)


func test_aircraft_lane_keeps_the_whole_move_on_the_table() -> void:
	# Rulebook note: an aircraft can't move into the table edges to move less than its mandatory move.
	# Parked 4" from the east edge with the only enemy due EAST, the straight 30" lane must pick a
	# direction whose FULL length stays on the table — the move is never shortened by the edge.
	var half_m := 2.0 * 0.3048   # default table 4x4 feet
	var air := _unit(2, [Vector3(half_m - 4.0 * IN2M, 0, 0)], ["Aircraft"], "Gunship")
	_arm(air, [{"name": "Minigun", "range": 24, "attacks": 4, "rules": []}])
	var enemy := _unit(1, [Vector3(half_m - 1.0 * IN2M, 0, 0)], [], "BaitAtEdge")
	var sc := _controller([air, enemy])
	var start: Vector3 = (air.models[0] as ModelInstance).node.global_position
	sc.activate_next_ai_unit()
	var end: Vector3 = (air.models[0] as ModelInstance).node.global_position
	assert_float(start.distance_to(end) / IN2M).is_equal_approx(30.0, 0.1)
	assert_float(absf(end.x)).is_less(half_m)
	assert_float(absf(end.z)).is_less(half_m)


func test_shaken_aircraft_still_makes_its_mandatory_move_and_recovers_idle() -> void:
	# GF v3.5.1: the mandatory move happens even Shaken and does not break the staying-idle recovery.
	var air := _unit(2, [Vector3(-0.45, 0, 0)], ["Aircraft"], "Gunship")
	_arm(air, [{"name": "Minigun", "range": 24, "attacks": 4, "rules": []}])
	air.is_shaken = true
	var enemy := _unit(1, [Vector3(0.45, 0, 0)], [], "Grunts")
	var sc := _controller([air, enemy])
	var start: Vector3 = (air.models[0] as ModelInstance).node.global_position
	sc.activate_next_ai_unit()
	var end: Vector3 = (air.models[0] as ModelInstance).node.global_position
	assert_float(start.distance_to(end) / IN2M).is_equal_approx(30.0, 0.1)
	assert_bool(bool(sc.last_report.get("idle_shaken", false))).is_true()
	assert_bool(bool(sc.last_report.get("can_shoot", true))).is_false()   # idle = no attacks


# === Can never seize or contest objectives ===

func test_aircraft_never_seizes_and_never_contests() -> void:
	var objectives: Array = [Vector3.ZERO]
	# Alone within 3": an aircraft seizes nothing — the marker stays neutral.
	var air_alone := [{"player": 2, "shaken": false, "aircraft": true, "positions": [Vector3(0.02, 0, 0)]}]
	var res: Dictionary = SoloController.seize_objectives(air_alone, objectives, [0])
	assert_int(int((res["owners"] as Array)[0])).is_equal(0)
	# An enemy holder within 3" PLUS the aircraft: no contest — the enemy seizes it cleanly.
	var both := [
		{"player": 2, "shaken": false, "aircraft": true, "positions": [Vector3(0.02, 0, 0)]},
		{"player": 1, "shaken": false, "positions": [Vector3(-0.02, 0, 0)]},
	]
	res = SoloController.seize_objectives(both, objectives, [0])
	assert_int(int((res["owners"] as Array)[0])).is_equal(1)


# === Can never be charged ===

func test_melee_only_unit_never_targets_an_aircraft() -> void:
	# A pure melee unit can neither charge (rule) nor ever attack an aircraft — the nearest-target key
	# must skip it: the further GROUND unit is the valid target; with only aircraft left, none.
	var melee := _unit(2, [Vector3.ZERO], [], "Claws")
	_arm(melee, [{"name": "Claws", "range": 0, "attacks": 4, "rules": []}])
	var air_near := _unit(1, [Vector3(0.10, 0, 0)], ["Aircraft"], "AirNear")
	var ground_far := _unit(1, [Vector3(0.50, 0, 0)], [], "GroundFar")
	var sc := _controller([melee, air_near, ground_far])
	assert_str(sc.nearest_human_unit(melee).get_name()).is_equal("GroundFar")
	var melee2 := _unit(2, [Vector3.ZERO], [], "Claws2")
	_arm(melee2, [{"name": "Claws", "range": 0, "attacks": 4, "rules": []}])
	var air_only := _unit(1, [Vector3(0.10, 0, 0)], ["Aircraft"], "AirOnly")
	var sc2 := _controller([melee2, air_only])
	assert_object(sc2.nearest_human_unit(melee2)).is_null()


func test_hybrid_unit_in_charge_range_of_aircraft_never_charges_it() -> void:
	# A HYBRID unit (guns + melee) base-to-base close to an aircraft: the tree must not see
	# "enemy in charge range" — it advances/shoots instead of declaring an impossible charge.
	var hybrid := _unit(2, [Vector3.ZERO], [], "Bikers")
	_arm(hybrid, [{"name": "Rifle", "range": 24, "attacks": 2, "rules": []},
		{"name": "CCW", "range": 0, "attacks": 2, "rules": []}])
	var air := _unit(1, [Vector3(6.0 * IN2M, 0, 0)], ["Aircraft"], "Gunship")
	var sc := _controller([hybrid, air])
	var unit := sc.activate_next_ai_unit()
	assert_object(unit).is_same(hybrid)
	assert_int(int(sc.last_report.get("action", -1))).is_not_equal(AiDecision.Action.CHARGE)


# === -12" to units targeting an aircraft ===

func test_shooter_range_gate_shrinks_by_twelve_inches_against_aircraft() -> void:
	# 24" gun vs an aircraft 20" away: effective range 12", an Advance (6") cannot bridge it → NO shot
	# this activation. The same distance to a ground target advances and shoots fine (the control run).
	var shooter := _unit(2, [Vector3.ZERO], [], "Shooter")
	_arm(shooter, [{"name": "Rifle", "range": 24, "attacks": 2, "rules": []}])
	var air := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], ["Aircraft"], "Gunship")
	var sc := _controller([shooter, air])
	sc.activate_next_ai_unit()
	assert_bool(bool(sc.last_report.get("can_shoot", true))).is_false()
	var shooter2 := _unit(2, [Vector3.ZERO], [], "Shooter2")
	_arm(shooter2, [{"name": "Rifle", "range": 24, "attacks": 2, "rules": []}])
	var ground := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], [], "Grunts")
	var sc2 := _controller([shooter2, ground])
	sc2.activate_next_ai_unit()
	assert_bool(bool(sc2.last_report.get("can_shoot", false))).is_true()


func test_aircrafts_own_guns_suffer_no_penalty() -> void:
	# The -12" applies to units TARGETING the aircraft — never the aircraft's own shooting: after its
	# 30" lane it shoots a ground target within its printed range.
	var air := _unit(2, [Vector3(-0.45, 0, 0)], ["Aircraft"], "Gunship")
	_arm(air, [{"name": "Minigun", "range": 24, "attacks": 4, "rules": []}])
	var enemy := _unit(1, [Vector3(0.45, 0, 0)], [], "Grunts")   # ~35" away; the lane closes in
	var sc := _controller([air, enemy])
	sc.activate_next_ai_unit()
	assert_bool(bool(sc.last_report.get("can_shoot", false))).is_true()


# === The battle-log move record: the lane is auditable ===

func test_aircraft_move_record_carries_the_straight_lane() -> void:
	var air := _unit(2, [Vector3(-0.45, 0, 0)], ["Aircraft"], "Gunship")
	_arm(air, [{"name": "Minigun", "range": 24, "attacks": 4, "rules": []}])
	var enemy := _unit(1, [Vector3(0.45, 0, 0)], [], "Grunts")
	var sc := _controller([air, enemy])
	sc.activate_next_ai_unit()
	var move_rec := {}
	for rec in sc.drain_decisions():
		if str((rec as Dictionary).get("kind", "")) == "move":
			move_rec = rec
	assert_bool(move_rec.is_empty()).is_false()
	var data := move_rec.get("data", {}) as Dictionary
	assert_bool(bool(data.get("straight", false))).is_true()
	assert_bool(bool(data.get("aircraft", false))).is_true()
	assert_float(float(data.get("achieved_in", 0.0))).is_equal_approx(30.0, 0.1)
	assert_float(float(data.get("band_in", 0.0))).is_equal_approx(30.0, 0.001)
