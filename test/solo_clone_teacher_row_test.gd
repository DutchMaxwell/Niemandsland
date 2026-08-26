extends GdUnitTestSuite
## TR (NML-1009, wave C8): the IMITATION ROW must never teach a move the body
## refused. _solve_clone writes the row from its own argmax; only THEN does
## _act's adoption re-gate (NML-1026) turn an illegal charge into a Rush.

const IN2M := 0.0254


func _unit(pid: int, pos: Vector3, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	# 10 mm bases: SeparationChecker.shape_for_model derives the radius from
	# unit_properties.base_size_round (no CollisionShape node needed) — two of
	# these sum to a 0.394" edge allowance, read by BOTH the menu (NML-1073
	# S1b: BattleSim.edge_gap_in) and the re-gate (nearest_melee_gap_in). See
	# the individual tests for how/whether they still diverge.
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": [], "base_size_round": 10}
	var m := ModelInstance.new()
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var cc := OPRApiClient.OPRWeapon.new()
	cc.name = "CCW"
	cc.range_value = 0   # melee profile: without one the menu offers no charge
	cc.attacks = 4
	opr.weapons.append(cc)
	u.source_type = "opr"
	u.source_data = opr
	return u


## A policy scoring CHARGE 1.0 and all else 0.0: the clone's argmax IS the charge.
func before() -> void:
	var act_w1: Array = []
	for i in range(18):
		act_w1.append([1.0 if i == AiDecision.Action.CHARGE else 0.0])
	SoloController._teacher_rows_env = 1
	SoloController._menu_probe_env = 1
	AiClone._seat_nets = {}
	AiClone.set_net({"in_dim": 1, "act_dim": 18,
		"row_w1": [[0.0]], "row_b1": [0.0], "row_w2": [[0.0]], "row_b2": [0.0],
		"state_w1": [[0.0], [0.0], [0.0], [0.0]], "state_b1": [0.0],
		"act_w1": act_w1, "act_b1": [0.0], "head_w1": [[0.0], [1.0]],
		"head_b1": [0.0], "head_w2": [1.0], "head_b2": 0.0})


## PROCESS-wide statics: left set, the rest of the suite inherits a clone brain.
func after() -> void:
	SoloController._teacher_rows_env = -1
	SoloController._menu_probe_env = -1
	AiClone._net_cache = {}
	AiClone._tried = false
	AiClone._seat_nets = {}


func test_the_teacher_row_never_learns_a_charge_the_body_refused() -> void:
	var grunts := _unit(2, Vector3.ZERO, "Grunts")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	# NML-1073 S1b: the OLD lever (menu measured centre-1.0", body measured the
	# TRUE edge gap) is closed by design -- both now read the same 0.394" radii
	# sum. The NEW lever is the menu's own contact epsilon: it accepts up to
	# band + CHARGE_CONTACT_MARGIN_IN (12.25"), the re-gate accepts only up to
	# band, raw (12.0") -- a genuine ~0.25" window. Edge gap 12.1" (raw 12.4937"
	# minus the 0.394" radii sum) sits inside it: menu gap_in = 12.1-0.25 =
	# 11.85" <= 12" -> offered; re-gate gap = 12.1" > 12" -> refused. Old raw
	# distance was 12.8" (menu 11.8" <= 12" via the old flat -1.0"; re-gate
	# 12.406" > 12" via the true edge gap -- the closed lever).
	army.game_units = {"Grunts": grunts, "Foe": _unit(1, Vector3(12.4937 * IN2M, 0, 0), "Foe")}
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.objectives_provider = func() -> Array: return [Vector3(0, 0, 20.0 * IN2M)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	assert_bool(sc._clone_active()).is_true()
	var report := sc._act(grunts)
	# A (no-idle guard): the re-gate FIRED, so B cannot pass on a charge-free turn.
	assert_int(int(report["action"])).is_equal(AiDecision.Action.RUSH)
	var rows := sc.decision_log.filter(func(r: Dictionary) -> bool:
		return str(r.get("kind", "")) == "teacher_row")
	assert_int(rows.size()).is_equal(1)
	var data: Dictionary = (rows[0] as Dictionary)["data"]
	var idx := int(data["teacher"])
	var learned := -1 if idx < 0 else int(((data["menu"] as Array)[idx] as Dictionary)["kind"])
	# B: what the corpus learns must not be the charge the body just refused.
	assert_int(learned).is_not_equal(AiDecision.Action.CHARGE)


## NML-1073 S1b (positive, GREEN-only -- same change as the fix, not a fresh
## RED): the base-radius mismatch above is a narrow ~0.25" epsilon window, not
## a wide-open gap -- a target the menu can clearly see is out of band (edge
## gap 14", well past band 12" + the 0.25" margin) is never offered a CHARGE
## candidate either. 10 mm bases again; raw distance 14.3937" = 14" edge gap
## + the 0.394" radii sum.
func test_menu_no_longer_offers_a_charge_past_the_true_edge_gap() -> void:
	var grunts := _unit(2, Vector3.ZERO, "Grunts")
	var foe := _unit(1, Vector3(14.3937 * IN2M, 0, 0), "Foe")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Grunts": grunts, "Foe": foe}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 4)
	var sc: SoloController = auto_free(SoloController.new())
	state["charge_illegal"] = sc.charge_candidate_illegal
	var akey := ""
	for k in state["units"]:
		if (state["units"][k] as Dictionary)["unit"] == grunts:
			akey = str(k)
	var kinds: Array = AiPlanner.candidates_wide(state, akey).map(
		func(c: Dictionary) -> int: return int(c["kind"]))
	assert_bool(kinds.has(AiDecision.Action.CHARGE)).is_false()
