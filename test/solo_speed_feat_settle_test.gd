extends GdUnitTestSuite
## E2 (EPOCH_76_MOVE_FIXES): the AI spends its once-per-game Speed Feat only on an activation that moves. The table
## used to set the latch at the head of _act, before a later re-gate (here Immobile's forced Hold) could turn the
## action into a Hold; the core grants and stamps the feat on ADVANCE, RUSH and CHARGE alone (sim.rs
## speed_feat_band_in). Below 76 the head spend stays, so recorded games replay unchanged.

const IN2M := 0.0254
const FLAG := "speed_feat_used_speed_feat"
const TAKEN := {"name": "Speed Feat", "advance": 2.0, "rush": 4.0}

var _epoch0 := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, pos: Vector3, uid: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": rules,
		"game_system": "gf", "faction_folder": "orc_marauders", "base_size_round": 25}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 2
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## Round 3 of 4 (two rounds left: the endgame window the feat waits for); the bearer (AI, player 2) at 0", a foe 20" off.
func _controller(bearer: GameUnit) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {bearer.unit_id: bearer, "Foe": _unit(1, Vector3(20.0 * IN2M, 0, 0), "Foe", [])}
	army.current_round = 3
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 3
	sc.objectives_provider = func() -> Array: return []
	sc.objective_owner_of = func(_i: int) -> int: return 0
	return sc


func _spend_notes(report: Dictionary) -> Array:
	return (report["rule_notes"] as Array).filter(func(n: Dictionary) -> bool:
		return str(n["text"]).contains("spends its once-per-game move bonus"))


func test_an_immobile_bearer_holds_and_keeps_its_feat_from_epoch_76() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_76_MOVE_FIXES
	var bearer := _unit(2, Vector3.ZERO, "Boyz", ["Speed Feat", "Immobile"])
	var report := _controller(bearer)._act(bearer)
	assert_int(int(report["action"])).is_equal(AiDecision.Action.HOLD)
	assert_bool(bool(bearer.unit_properties.get(FLAG, false))) \
		.override_failure_message("a Hold spent the once-per-game Speed Feat") \
		.is_false()
	assert_int(_spend_notes(report).size()).is_equal(0)


## The below-76 leg (passes before and after the fix): a record stamped 75 spends the feat at the head, Hold or not.
func test_at_epoch_75_the_head_spends_the_feat_even_on_a_hold() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_76_MOVE_FIXES - 1
	var bearer := _unit(2, Vector3.ZERO, "Boyz", ["Speed Feat", "Immobile"])
	var report := _controller(bearer)._act(bearer)
	assert_int(int(report["action"])).is_equal(AiDecision.Action.HOLD)
	assert_bool(bool(bearer.unit_properties.get(FLAG, false))).is_true()
	assert_int(_spend_notes(report).size()).is_equal(1)


func test_a_moving_bearer_spends_its_feat_at_epoch_76() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_76_MOVE_FIXES
	var bearer := _unit(2, Vector3.ZERO, "Boyz", ["Speed Feat"])
	var report := _controller(bearer)._act(bearer)
	assert_array([AiDecision.Action.ADVANCE, AiDecision.Action.RUSH, AiDecision.Action.CHARGE]) \
		.contains([int(report["action"])])
	assert_bool(bool(bearer.unit_properties.get(FLAG, false))).is_true()
	assert_int(_spend_notes(report).size()).is_equal(1)


func test_settle_spends_on_every_move_verb_and_never_on_a_hold() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_76_MOVE_FIXES
	for verb in [AiDecision.Action.HOLD, AiDecision.Action.ADVANCE, AiDecision.Action.RUSH, AiDecision.Action.CHARGE]:
		var bearer := _unit(2, Vector3.ZERO, "Boyz", ["Speed Feat"])
		var sc := _controller(bearer)
		# .call: the suite still loads (and its below-76 leg still runs) on a build without the settle step.
		if not sc.has_method("_settle_speed_feat"):
			fail("no _settle_speed_feat step")
			return
		sc.call("_settle_speed_feat", bearer, verb, ActIntent.blank_report(bearer), TAKEN)
		assert_bool(bool(bearer.unit_properties.get(FLAG, false))) \
			.override_failure_message("verb %d" % verb) \
			.is_equal(verb != AiDecision.Action.HOLD)
