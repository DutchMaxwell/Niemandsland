extends GdUnitTestSuite
## Solo-AI M2: AiDecision — the OFFICIAL v3.5.0 no-objective tree branches (objectives = M3).

const ADV := 6.0
const CHG := 12.0
const SHOOT := 24.0


func test_melee_charges_when_in_reach() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 10.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.CHARGE)


func test_melee_rushes_whenever_out_of_charge_range() -> void:
	# Official tree: a melee unit out of charge range always RUSHES toward the enemy — it never merely
	# advances (the old charge+advance window was a deviation).
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 15.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.RUSH)
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 40.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.RUSH)


func test_shooter_kites_when_already_in_range() -> void:
	# "Advancing" basic concept: shooters in range move AWAY from the closest enemy, staying in range.
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 12.0, ADV, CHG, SHOOT, true)).is_equal(AiDecision.Action.KITE)


func test_shooter_advances_into_range() -> void:
	# Out of range/LOS now, but advancing 6" brings the 26" target within 24" range → advance + shoot.
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 26.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.ADVANCE)


func test_shooter_rushes_when_far_out_of_range() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 40.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.RUSH)


func test_hybrid_charges_then_shoots_then_rushes() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 10.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.CHARGE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 20.0, ADV, CHG, SHOOT, true)).is_equal(AiDecision.Action.ADVANCE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 26.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.ADVANCE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 45.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.RUSH)


# ===== Official Solo & Co-Op decision trees (GF/AoF Advanced Rules v3.5.1, p.57) =====

func _dec(arch, obj, in_way, enemy_charge, shoot_adv, extra={}) -> Dictionary:
	var ctx = {"arch": arch, "objective": obj, "in_way": in_way, "enemy_in_charge": enemy_charge, "shoot_after_advance": shoot_adv}
	for k in extra: ctx[k] = extra[k]
	return AiDecision.decide_solo(ctx)


func test_shooting_tree_official() -> void:
	# No objective, advancing brings enemy in range → Advance toward ENEMY + shoot (NEVER kite).
	var d = _dec(AiArchetype.Type.SHOOTING, false, false, false, true)
	assert_int(int(d["action"])).is_equal(AiDecision.Action.ADVANCE)
	assert_int(int(d["toward"])).is_equal(AiDecision.Toward.ENEMY)
	assert_bool(bool(d["shoot"])).is_true()
	# No objective, out of range even after advance → Rush toward enemy.
	assert_int(int(_dec(AiArchetype.Type.SHOOTING, false, false, false, false)["action"])).is_equal(AiDecision.Action.RUSH)
	# Uncontrolled objective + advance keeps enemy in range → Advance toward OBJECTIVE + shoot.
	var o = _dec(AiArchetype.Type.SHOOTING, true, false, false, true)
	assert_int(int(o["toward"])).is_equal(AiDecision.Toward.OBJECTIVE)
	assert_int(int(o["action"])).is_equal(AiDecision.Action.ADVANCE)
	# Objective + no shooting after advance → Rush toward objective.
	assert_int(int(_dec(AiArchetype.Type.SHOOTING, true, false, false, false)["toward"])).is_equal(AiDecision.Toward.OBJECTIVE)


func test_melee_tree_official() -> void:
	# No objective, enemy in charge range → Charge.
	assert_int(int(_dec(AiArchetype.Type.MELEE, false, false, true, false)["action"])).is_equal(AiDecision.Action.CHARGE)
	# No objective, not in charge → Rush toward enemy.
	var d = _dec(AiArchetype.Type.MELEE, false, false, false, false)
	assert_int(int(d["action"])).is_equal(AiDecision.Action.RUSH)
	assert_int(int(d["toward"])).is_equal(AiDecision.Toward.ENEMY)
	# Objective, enemy in the way AND chargeable → Charge; else Rush toward objective.
	assert_int(int(_dec(AiArchetype.Type.MELEE, true, true, true, false)["action"])).is_equal(AiDecision.Action.CHARGE)
	assert_int(int(_dec(AiArchetype.Type.MELEE, true, false, true, false)["toward"])).is_equal(AiDecision.Toward.OBJECTIVE)


func test_hybrid_tree_official() -> void:
	# No objective, enemy in charge → Charge.
	assert_int(int(_dec(AiArchetype.Type.HYBRID, false, false, true, false)["action"])).is_equal(AiDecision.Action.CHARGE)
	# No objective, not chargeable, advance→shoot → Advance toward enemy + shoot.
	var d = _dec(AiArchetype.Type.HYBRID, false, false, false, true)
	assert_int(int(d["action"])).is_equal(AiDecision.Action.ADVANCE)
	assert_int(int(d["toward"])).is_equal(AiDecision.Toward.ENEMY)
	# Objective, not in the way, obj in rush but not advance range → Rush toward objective.
	var r = _dec(AiArchetype.Type.HYBRID, true, false, false, false, {"obj_in_rush": true, "obj_in_advance": false})
	assert_int(int(r["action"])).is_equal(AiDecision.Action.RUSH)
	assert_int(int(r["toward"])).is_equal(AiDecision.Toward.OBJECTIVE)


func test_no_kite_action_exists_in_official_output() -> void:
	# Sweep the whole context space — the official trees must never output a retreat/kite.
	for arch in [AiArchetype.Type.MELEE, AiArchetype.Type.SHOOTING, AiArchetype.Type.HYBRID]:
		for obj in [true, false]:
			for iw in [true, false]:
				for ec in [true, false]:
					for sa in [true, false]:
						var a = int(_dec(arch, obj, iw, ec, sa)["action"])
						assert_bool(a in [AiDecision.Action.HOLD, AiDecision.Action.ADVANCE, AiDecision.Action.RUSH, AiDecision.Action.CHARGE]).is_true()
