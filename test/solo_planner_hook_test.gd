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
