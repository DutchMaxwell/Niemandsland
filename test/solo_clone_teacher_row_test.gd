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
	# NML-1073 S1d: BOTH menu/body windows are now closed. S1b closed the first
	# (menu measured centre-1.0", body the true edge gap); S1d closes the second
	# (menu measured edge_gap-0.25", body the raw edge gap) by passing the RAW
	# edge gap -- literally the quantity the body reads (charge_illegal_why ->
	# nearest_melee_gap_in, solo_controller.gd:1406). One measure, no window, so
	# this fixture now proves the CLOSURE end to end: edge gap 12.1" (raw
	# 12.4937" minus the 0.394" radii sum) > the 12" band, so the menu never
	# offers the charge, the body never charges, and the row cannot learn one.
	# A3 below is the positive control the old A2 used to be.
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
	# A (no-idle guard): the body did NOT charge, so B cannot pass by accident.
	# S1d: the refusal moved from the re-gate into the MENU, so the played action
	# is whatever the tree prefers among the legal ones, not the re-gate's RUSH.
	assert_int(int(report["action"])).is_not_equal(AiDecision.Action.CHARGE)
	var rows := sc.decision_log.filter(func(r: Dictionary) -> bool:
		return str(r.get("kind", "")) == "teacher_row")
	assert_int(rows.size()).is_equal(1)
	var data: Dictionary = (rows[0] as Dictionary)["data"]
	var menu: Array = data["menu"]
	# A2 (S1d): the menu itself must refuse the out-of-band charge -- the body no
	# longer has to catch it.
	assert_int(menu.filter(func(m: Dictionary) -> bool:
		return int(m["kind"]) == AiDecision.Action.CHARGE).size()).is_equal(0)
	# A3 (positive control, the honest half of the old A2): the SAME menu builder
	# with the SAME gate still offers CHARGE against a foe inside the band --
	# without this, a regression that stopped offering charges at all would leave
	# A2 and B green for the wrong reason.
	var near_army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var brawler := _unit(2, Vector3.ZERO, "Brawler")
	near_army.game_units = {"Brawler": brawler, "Near": _unit(1, Vector3(6.0 * IN2M, 0, 0), "Near")}
	var near_state := BattleSim.capture(near_army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 4)
	near_state["charge_illegal"] = sc.charge_candidate_illegal
	var bkey := ""
	for k in near_state["units"]:
		if (near_state["units"][k] as Dictionary)["unit"] == brawler:
			bkey = str(k)
	var near_kinds: Array = AiPlanner.candidates_wide(near_state, bkey).map(
		func(c: Dictionary) -> int: return int(c["kind"]))
	assert_bool(near_kinds.has(AiDecision.Action.CHARGE)).is_true()
	var idx := int(data["teacher"])
	var learned := -1 if idx < 0 else int((menu[idx] as Dictionary)["kind"])
	# B: what the corpus learns must not be the charge the body just refused.
	assert_int(learned).is_not_equal(AiDecision.Action.CHARGE)


## NML-1073 S1b (RED-then-GREEN, fixup2 review 3c): the previous fixture (raw
## 14.3937", edge gap 14") was INERT -- the OLD flat -1.0" formula also
## refused it (14.3937 - 1.0 = 13.39 > 12), so it never distinguished the fix
## from the bug it replaced. This geometry sits INSIDE the ~0.25" window the
## fix closed: raw 12.8937" = edge gap 12.5" (10 mm bases, 0.394" radii sum).
## OLD menu gate (dist_in - CONTACT_IN): 12.8937 - 1.0 = 11.89 <= 12" band ->
## OFFERED (the bug). NEW menu gate (the RAW edge gap since NML-1073 S1d,
## edge_gap_in - CHARGE_CONTACT_MARGIN_IN in S1b): 12.5 > 12" band -> REFUSED
## (the fix, asserted below; S1b's 12.25" refused it too).
## Verified by hand (fixup2 review): temporarily reverted _best_charge's
## gap_in lines in ai_planner.gd to the OLD formula -- this test FAILED
## (charge offered); `git checkout` restored the file byte-exact and the same
## run PASSED.
func test_menu_no_longer_offers_a_charge_past_the_true_edge_gap() -> void:
	var grunts := _unit(2, Vector3.ZERO, "Grunts")
	var foe := _unit(1, Vector3(12.8937 * IN2M, 0, 0), "Foe")
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
