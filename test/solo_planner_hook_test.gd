extends GdUnitTestSuite
## Phase-1 step 6: the PLANNER_V0 controller hook. Only the planner preset
## routes _act through AiPlanner; null-AI and NACHTMAHR never enter the hook
## (byte-identical paths), and an adopted plan drives action, destination and
## the "planner" explainability record end to end.

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
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## AI Taker (P2) 6" from a neutral marker, enemy 30" off: the mission pick is
## the rush; the tree without a marker in Advance+3 reach would close on the
## enemy instead — so tree and planner disagree and the test discriminates.
func _controller() -> SoloController:
	var taker := _unit(2, [Vector3(6.0 * IN2M, 0, 0)], "Taker")
	var enemy := _unit(1, [Vector3(36.0 * IN2M, 0, 0)], "Enemy")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Taker": taker, "Enemy": enemy}
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.objectives_provider = func() -> Array: return [Vector3(0, 0, 12.0 * IN2M)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	return sc


func _kinds(sc: SoloController) -> Array:
	return sc.decision_log.map(func(r: Dictionary) -> String: return str(r.get("kind", "")))


func test_gate_only_opens_for_the_planner_preset() -> void:
	var sc := _controller()
	assert_bool(sc._planner_active()).is_false()   # null-AI
	sc.set_difficulty(2, SoloDifficulty.for_grade("nachtmahr"))
	assert_bool(sc._planner_active()).is_false()   # sharp tree stays the tree
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	assert_bool(sc._planner_active()).is_true()


## Unit pick: with the planner on, the marker-taker beats a far idler for the
## next activation regardless of pool order — no seeded draw, one "planner"
## record. Off-preset (NACHTMAHR) the pick must NOT come from the planner.
func test_planner_picks_which_unit_activates() -> void:
	var sc := _controller()
	var idler := _unit(2, [Vector3(60.0 * IN2M, 0, 60.0 * IN2M)], "Idler")
	sc.army_manager.game_units["Idler"] = idler
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var taker: GameUnit = sc.army_manager.game_units["Taker"]
	assert_object(sc._select_ai_unit([idler, taker])).is_same(taker)
	assert_that(_kinds(sc)).contains(["planner"])
	var sc2 := _controller()
	var idler2 := _unit(2, [Vector3(60.0 * IN2M, 0, 60.0 * IN2M)], "Idler")
	sc2.army_manager.game_units["Idler"] = idler2
	sc2.set_difficulty(2, SoloDifficulty.for_grade("nachtmahr"))
	sc2._select_ai_unit([idler2, sc2.army_manager.game_units["Taker"]])
	assert_that(_kinds(sc2)).not_contains(["planner"])


## NML-1073 M5: a side's LAST un-activated unit must take the SAME road as every
## other pick. There is no choice of UNIT left, but there is still a choice of
## ACTION — before this fix `pool.size() == 1` returned above the planner block,
## so the act ordinal was never bumped, no acts.jsonl line was written, and
## _solve_planner re-derived the action 1-ply instead of rolling it out.
func test_last_unit_of_a_side_still_goes_through_the_rollout_planner() -> void:
	var sc := _controller()
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var taker: GameUnit = sc.army_manager.game_units["Taker"]
	assert_int(sc.move_act_seq()).is_equal(0)
	assert_object(sc._select_ai_unit([taker])).is_same(taker)
	assert_int(sc.move_act_seq()) \
		.override_failure_message("the last un-activated unit bypassed _planner_pick_unit — no act ordinal, no act line") \
		.is_equal(1)
	assert_that(_kinds(sc)) \
		.override_failure_message("no planner decision record for a one-unit pool") \
		.contains(["planner"])
	assert_bool(sc._planner_intent.is_empty()) \
		.override_failure_message("the rollout intent was not cached — _solve_planner would re-plan 1-ply") \
		.is_false()
	assert_object(sc._planner_intent.get("unit", null)).is_same(taker)


## The TREE paths keep the shortcut: a one-unit pool returns that unit directly,
## above the lookahead and above the D6 section roll — no planner, no record, and
## crucially no draw off the seeded stream.
func test_tree_keeps_the_one_unit_shortcut_without_a_draw() -> void:
	for preset in ["", "nachtmahr"]:
		var sc := _controller()
		if preset != "":
			sc.set_difficulty(2, SoloDifficulty.for_grade(preset))
		var taker: GameUnit = sc.army_manager.game_units["Taker"]
		assert_object(sc._select_ai_unit([taker])).is_same(taker)
		assert_int(sc.move_act_seq()).is_equal(0)
		assert_that(_kinds(sc)).not_contains(["planner"])
		assert_that(_kinds(sc)).not_contains(["pick"])
		assert_that(_kinds(sc)).not_contains(["lookahead"])


func test_solve_planner_maps_pick_to_adoption_shape() -> void:
	var sc := _controller()
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var taker: GameUnit = sc.army_manager.game_units["Taker"]
	var sol := sc._solve_planner(taker)
	assert_bool(sol.get("used", false)).is_true()
	assert_int(int(sol["action"])).is_equal(AiDecision.Action.RUSH)
	assert_int(int(sol["toward"])).is_equal(AiDecision.Toward.OBJECTIVE)
	assert_that(sol["goal"]).is_equal(Vector3(0, 0, 12.0 * IN2M))
	assert_that(_kinds(sc)).contains(["planner"])
	assert_str(sc.plain_reason_for(taker)).contains("rush objective 1")


func test_act_executes_the_planned_rush() -> void:
	var sc := _controller()
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var taker: GameUnit = sc.army_manager.game_units["Taker"]
	var report := sc._act(taker)
	assert_int(int(report["action"])).is_equal(AiDecision.Action.RUSH)
	var pos: Vector3 = (taker.models[0] as ModelInstance).node.global_position
	assert_float(pos.distance_to(Vector3(0, 0, 12.0 * IN2M)) / IN2M).is_less(3.5)


func test_tree_paths_stay_planner_free() -> void:
	for preset in ["", "nachtmahr"]:
		var sc := _controller()
		if preset != "":
			sc.set_difficulty(2, SoloDifficulty.for_grade(preset))
		sc._act(sc.army_manager.game_units["Taker"])
		assert_that(_kinds(sc)).not_contains(["planner"])


## R3: the rollout intent decided at the unit pick is EXECUTED, not re-derived.
## Last-round gunline fixture (the R2 discriminator through the controller):
## the pick opens with the bait and keeps the striker back; _solve_planner
## consumes exactly that intent (the "kept back" suffix only exists on rollout
## intents — a 1-ply re-plan can never produce it). A mismatched unit falls
## back to the re-plan without the suffix.
func test_rollout_intent_is_executed_not_rederived() -> void:
	var gunner := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Gunner")
	(gunner.source_data as OPRApiClient.OPRUnit).weapons[0].range_value = 36
	(gunner.source_data as OPRApiClient.OPRUnit).weapons[0].attacks = 12
	var striker := _unit(2, [Vector3(42.0 * IN2M, 0, 0), Vector3(43.0 * IN2M, 0, 0),
		Vector3(44.0 * IN2M, 0, 0), Vector3(45.0 * IN2M, 0, 0)], "Striker")
	var screamer := _unit(2, [Vector3(60.0 * IN2M, 0, 30.0 * IN2M)], "Screamer")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Striker": striker, "Screamer": screamer}
	army.current_round = 4
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 4   # last round — R6's horizon must clamp here
	sc.objectives_provider = func() -> Array: return [Vector3(30.0 * IN2M, 0, 0)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var picked := sc._select_ai_unit([striker, screamer])
	assert_object(picked).is_same(screamer)
	var sol := sc._solve_planner(picked)
	assert_bool(sol.get("used", false)).is_true()
	assert_str(str(sol["why"])).contains("kept back")
	# cache consumed: a second solve for another unit re-plans without the suffix
	var again := sc._solve_planner(striker)
	if bool(again.get("used", false)):
		assert_str(str(again["why"])).not_contains("kept back")


## NML-1073 M2-5 (R1 + R2): the SEARCH SEAM is never load-bearing.
## R2 — without NML_CORE=1 BattleSim.core_enabled() is false, _planner_pick_unit
## never touches _core_plan (the NmlCore node stays null) and the pick is the
## GDScript one this suite already pins.
## R1 — the seam's own decline log is one line per REASON per game, so a corpus
## of 200 activations that all decline for the same reason says so ONCE.
func test_core_seam_stays_off_and_declines_once_per_reason() -> void:
	var want := OS.get_environment("NML_CORE") == "1"
	assert_bool(BattleSim.core_enabled()).is_equal(want and ClassDB.class_exists("NmlCore"))
	var sc := _controller()
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var taker: GameUnit = sc.army_manager.game_units["Taker"]
	assert_object(sc._select_ai_unit([taker])).is_same(taker)
	if not BattleSim.core_enabled():
		assert_bool(sc._core_node == null).is_true()
		assert_int(sc._core_calls).is_equal(0)
	sc._core_warn_once("NetPlayout")
	sc._core_warn_once("NetPlayout")
	sc._core_warn_once("FittedEval")
	assert_int(sc._core_declines.size()).is_equal(2)


## The seam only ever ADDS a source for the pick: whatever it answers, the
## dictionary the controller goes on to consume has the same keys the GDScript
## search returns, so _solve_planner and the decision records cannot tell them
## apart. Pinned on the GDScript answer, which is the shape both must have.
func test_planner_pick_keeps_its_dictionary_shape() -> void:
	var sc := _controller()
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	var state := BattleSim.capture(sc.army_manager, sc.objectives_provider,
		sc.objective_owner_of, 1, 4)
	var pick := AiPlanner.plan_with_rollout(state, 2)
	AiPlanner.close()
	for k in ["used", "unit_key", "action", "intent", "expectation", "runner_up",
			"waits", "rolled_units"]:
		assert_bool(pick.has(k)).override_failure_message("pick is missing " + k).is_true()
	assert_str(str(pick["intent"])).contains("round played out")
