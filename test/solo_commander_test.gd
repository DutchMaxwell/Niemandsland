extends GdUnitTestSuite
## AI PLAUSIBILITY Stage 4 — commander STANDING ORDERS (plan persistence) + firepower preservation.
## Every graded AI unit carries a standing order that survives activations AND rounds and is RE-VALIDATED
## each activation (Killzone continue/abort) rather than re-derived: a melee/monster keeps closing on ONE
## enemy across rounds; a ranged-line unit HOLDS a firing position with LOS + range instead of being dragged
## off a clean shot toward an out-of-reach marker (the Stage-3 firepower dip). Difficulty scales the
## discipline; the null-AI / SoloSim path never enters the commander (byte-identical).

const IN2M := 0.0254


func _unit(pid: int, positions: Array, rules: Array = [], uid: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": 4, "defense": 4, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
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


func _wire_objectives(sc: SoloController, markers: Array) -> void:
	sc.objectives_provider = func() -> Array: return markers
	sc.objective_owner_of = func(_i: int) -> int: return 0   # neutral = uncontrolled


func _commander_record(recs: Array) -> Dictionary:
	for rec in recs:
		if str((rec as Dictionary).get("kind", "")) == "commander":
			return rec
	return {}


func _hold_fire_record(recs: Array) -> Dictionary:
	# The ranged-line ACTION overlay record (chosen = hold and shoot / abort hold), distinct from the
	# _commander_apply role assignment (chosen = a role name).
	for rec in recs:
		var r := rec as Dictionary
		if str(r.get("kind", "")) != "commander":
			continue
		var chosen := str(r.get("chosen", ""))
		if chosen.begins_with("hold and shoot") or chosen.begins_with("abort hold"):
			return r
	return {}


# === Part B — preserve firepower: the ranged-line hold-and-shoot standing order ===

func _shooter_board(marker_dist_in: float) -> Array:
	# A ranged-line shooter (24" rifle, not Fast → RANGED_LINE) with a clean shot at an enemy 10" away and
	# an uncontrolled marker `marker_dist_in` off to the side. The official SHOOTING tree, seeing the marker,
	# would ADVANCE toward it (and risk the shot); the commander decides whether to hold the clean shot.
	var gun := _unit(2, [Vector3.ZERO], [], "Gunners")
	_arm(gun, [{"name": "Rifle", "range": 24, "attacks": 3, "rules": []}])
	var enemy := _unit(1, [Vector3(10.0 * IN2M, 0, 0)], [], "Grunts")
	var sc := _controller([gun, enemy])
	_wire_objectives(sc, [Vector3(0, 0, marker_dist_in * IN2M)])
	return [sc, gun]


func test_kriegsherr_shooter_holds_the_clean_shot_off_an_unreachable_marker() -> void:
	var pair := _shooter_board(30.0)   # marker well beyond a Rush → the walk is a pure firepower loss
	var sc: SoloController = pair[0]
	sc.difficulty_seed = 7
	sc.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 7))
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_equal(AiDecision.Action.HOLD)
	assert_bool(bool(sc.last_report.get("can_shoot", false))).is_true()
	var hf := _hold_fire_record(sc.drain_decisions())
	assert_bool(hf.is_empty()).is_false()
	assert_str(str((hf.get("data", {}) as Dictionary).get("order", ""))).is_equal("hold_fire")


func test_planner_promise_outbids_the_hold_on_a_cheap_reachable_marker() -> void:
	# NML-210 doctrine: a rush-reachable marker (13", ONE march round) with a modest volley in hand
	# is a PROMISED seize — the round planner priced the trade, and the commander hold must not
	# freeze a promised runner (that would rebuild the baseline's 82%-short pathology). The unit
	# moves toward the marker instead of holding.
	var kh := _shooter_board(13.0)
	var sc_kh: SoloController = kh[0]
	sc_kh.difficulty_seed = 7
	sc_kh.set_difficulty(2, SoloDifficulty.for_grade("nachtmahr", 7))
	sc_kh.activate_next_ai_unit()
	assert_int(int(sc_kh.last_report.get("action", -1))).is_not_equal(AiDecision.Action.HOLD)
	assert_bool(bool(sc_kh.last_report.get("to_objective", false)) 		or int(sc_kh.last_report.get("action", -1)) != AiDecision.Action.HOLD).is_true()


func test_zero_persistence_tier_never_holds_fire() -> void:
	# NML-211: NONE-tier machinery (persistence 0) kept alive for the later persona rebuild.
	var pair := _shooter_board(30.0)
	var sc: SoloController = pair[0]
	sc.difficulty_seed = 7
	var none_tier := SoloDifficulty.new()
	none_tier.grade_name = "none-tier"
	none_tier.ev_noise = 0.0
	none_tier.mission_focus = 1.0
	none_tier.persistence = 0.0
	none_tier.base_seed = 7
	sc.set_difficulty(2, none_tier)
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_not_equal(AiDecision.Action.HOLD)
	assert_bool(_hold_fire_record(sc.drain_decisions()).is_empty()).is_true()


func test_null_ai_shooter_never_enters_the_commander() -> void:
	# No difficulty configured → the commander is skipped entirely (byte-identical to the official tree).
	var pair := _shooter_board(30.0)
	var sc: SoloController = pair[0]
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_not_equal(AiDecision.Action.HOLD)
	for rec in sc.drain_decisions():
		assert_str(str((rec as Dictionary).get("kind", ""))).is_not_equal("commander")


func test_seize_task_shooter_without_a_shot_marches_with_no_hold_order() -> void:
	# NML-210: enemy 40" away (out of the 24" rifle) with a FEASIBLE marker 30" off — the round
	# plan sends the gun to the marker. A promised runner carries NO hold-fire order at all (its
	# abort record disappears BY DESIGN; the "AI [plan]" record is the transparency line now),
	# and the unit is never frozen.
	var gun := _unit(2, [Vector3.ZERO], [], "Gunners")
	_arm(gun, [{"name": "Rifle", "range": 24, "attacks": 3, "rules": []}])
	var enemy := _unit(1, [Vector3(40.0 * IN2M, 0, 0)], [], "Grunts")
	var sc := _controller([gun, enemy])
	_wire_objectives(sc, [Vector3(0, 0, 30.0 * IN2M)])
	sc.difficulty_seed = 7
	sc.set_difficulty(2, SoloDifficulty.for_grade("nachtmahr", 7))
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_not_equal(AiDecision.Action.HOLD)
	var recs := sc.drain_decisions()
	assert_bool(_hold_fire_record(recs).is_empty()).is_true()
	var has_plan := false
	for rec in recs:
		if str((rec as Dictionary).get("kind", "")) == "plan":
			has_plan = true
	assert_bool(has_plan).is_true()


func test_ranged_hold_is_not_frozen_in_the_final_round() -> void:
	# In the LAST round only held markers score — a shooter is never held off a marker there (decisiveness wins).
	var pair := _shooter_board(13.0)
	var sc: SoloController = pair[0]
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 4
	sc.difficulty_seed = 7
	sc.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 7))
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_not_equal(AiDecision.Action.HOLD)


# === Part A — plan persistence: the close-and-fight standing target across rounds ===

func _close_board(rnd: Array) -> Array:
	# A pure-melee monster (no ranged weapon → CLOSE_AND_FIGHT) and two enemies: A near (8"), B far (20").
	var rex := _unit(2, [Vector3.ZERO], [], "Rex")
	var a := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], [], "EnemyA")
	var b := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], [], "EnemyB")
	var sc := _controller([rex, a, b])
	sc.round_provider = func() -> int: return rnd[0]
	sc.difficulty_seed = 7
	sc.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 7))
	return [sc, rex, a, b]


func test_close_order_persists_the_same_target_across_rounds() -> void:
	var rnd := [1]
	var board := _close_board(rnd)
	var sc: SoloController = board[0]
	var rex: GameUnit = board[1]
	var a: GameUnit = board[2]
	sc._act(rex)
	assert_str(str(sc.commander_orders[rex.unit_id].get("target_id", ""))).is_equal(a.unit_id)
	var rec1 := _commander_record(sc.drain_decisions())
	assert_str(str((rec1.get("data", {}) as Dictionary).get("continuity", ""))).is_equal("issue")
	assert_bool(bool((rec1.get("data", {}) as Dictionary).get("persisted", true))).is_false()   # first issue → not yet persisted

	# Round 2 — same board: the order is RE-VALIDATED and CONTINUES on the same enemy (multi-round approach).
	rnd[0] = 2
	sc._act(rex)
	assert_str(str(sc.commander_orders[rex.unit_id].get("target_id", ""))).is_equal(a.unit_id)
	var rec2 := _commander_record(sc.drain_decisions())
	var d2 := rec2.get("data", {}) as Dictionary
	assert_str(str(d2.get("continuity", ""))).is_equal("continue")
	assert_int(int(d2.get("since_round", -1))).is_equal(1)
	assert_int(int(d2.get("rounds_held", -1))).is_equal(2)
	# `persisted` is truthful: a CONTINUED order held for >1 round reports true (was mislabelled false when the
	# standing target coincided with the momentary nearest — reporting only, no gameplay effect).
	assert_bool(bool(d2.get("persisted", false))).is_true()


func test_close_order_aborts_and_re_adopts_when_the_target_dies() -> void:
	var rnd := [1]
	var board := _close_board(rnd)
	var sc: SoloController = board[0]
	var rex: GameUnit = board[1]
	var a: GameUnit = board[2]
	var b: GameUnit = board[3]
	sc._act(rex)
	assert_str(str(sc.commander_orders[rex.unit_id].get("target_id", ""))).is_equal(a.unit_id)
	sc.drain_decisions()

	# Enemy A is wiped out → the standing order ABORTS and the commander re-adopts the nearest survivor (B).
	for m in a.models:
		(m as ModelInstance).is_alive = false
	rnd[0] = 2
	sc._act(rex)
	assert_str(str(sc.commander_orders[rex.unit_id].get("target_id", ""))).is_equal(b.unit_id)
	var rec := _commander_record(sc.drain_decisions())
	var d := rec.get("data", {}) as Dictionary
	assert_str(str(d.get("continuity", ""))).is_equal("abort")
	assert_int(int(d.get("since_round", -1))).is_equal(2)   # since_round resets on abort


# === Difficulty knob wiring ===

func test_persistence_tier_machinery_separates_knob_values() -> void:
	# NML-211: the tier thresholds stay covered via raw knob values (persona rebuild ground).
	var lo := SoloDifficulty.new(); lo.persistence = 0.0
	var mid := SoloDifficulty.new(); mid.persistence = 0.5
	var hi := SoloDifficulty.new(); hi.persistence = 1.0
	assert_int(lo.persistence_tier()).is_equal(0)
	assert_int(mid.persistence_tier()).is_equal(1)
	assert_int(hi.persistence_tier()).is_equal(2)
	assert_int(SoloDifficulty.for_grade("nachtmahr").persistence_tier()).is_equal(2)
	assert_float(SoloDifficulty.for_grade("nachtmahr").to_dict().get("persistence", -1.0)).is_equal(1.0)
