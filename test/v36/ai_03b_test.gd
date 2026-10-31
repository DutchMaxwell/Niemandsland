extends GdUnitTestSuite
## Rules 3.6 wave, row AI-03b: the three GDScript AI twins learn Cumbersome. From the rules 3.6
## epoch (73) on a Cumbersome unit may only Hold or Advance and fires no volley after it moved, so
## the AI's own menu drops Rush and Charge, an Advance carries no shot, and the enemy reply model
## no longer lets it charge or advance-and-shoot. Below 73 everything keeps its old shape.

const IN2M := 0.0254

var _epoch0: int
var _reply_v2_0: bool
var _hold_gate_0: bool


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_reply_v2_0 = BattleSim.reply_v2
	_hold_gate_0 = BattleSim.reply_hold_gate
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0
	BattleSim.reply_v2 = _reply_v2_0
	BattleSim.reply_hold_gate = _hold_gate_0
	RulesRegistry.reset_cache()


func _unit(pid: int, unit_name: String, positions: Array, rules: Array = [], weapons: Array = []) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "some_book"}
	for position in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.wounds_current = 1
		model.unit = unit
		var node := Node3D.new()
		add_child(node)
		node.global_position = position
		model.node = node
		unit.models.append(model)
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
	unit.source_type = "opr"
	unit.source_data = opr
	return unit


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for unit in units:
		army.game_units[(unit as GameUnit).unit_id] = unit
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


func _capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)


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


## The twin is new in this row: read it through a dynamic call, so the RED run fails on the
## assertion below instead of a parse error that would abort the whole shard.
func _cumbersome(unit: GameUnit) -> bool:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	if not solo.has_method("cumbersome_active"):
		return false
	return bool(solo.call("cumbersome_active", unit))


func test_cumbersome_is_live_only_from_epoch_73() -> void:
	var walker := _unit(2, "Walker", [Vector3.ZERO], ["Cumbersome"])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(_cumbersome(walker)) \
		.override_failure_message("rules 3.6: the twin must read the rule live at epoch 73") \
		.is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(_cumbersome(walker)) \
		.override_failure_message("rules 3.5 has no Cumbersome") \
		.is_false()


func test_a_cumbersome_unit_may_not_rush_or_charge_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var walker := _unit(2, "Walker", [Vector3.ZERO], ["Cumbersome"], [{"name": "Rifle", "range": 24}])
	var foe := _unit(1, "Foe", [Vector3(10 * IN2M, 0, 0)])
	var solo := _controller([walker, foe])
	for verb in [AiDecision.Action.RUSH, AiDecision.Action.CHARGE]:
		var intent := solo.player_intent(walker, verb, foe)
		assert_bool(intent.has("refused")) \
			.override_failure_message("rules 3.6: verb %d must be closed to a Cumbersome unit" % verb) \
			.is_true()
		assert_str(str(intent.get("refused", ""))).contains("Cumbersome")


func test_a_cumbersome_advance_carries_no_shot_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var walker := _unit(2, "Walker", [Vector3.ZERO], ["Cumbersome"], [{"name": "Rifle", "range": 24}])
	var foe := _unit(1, "Foe", [Vector3(10 * IN2M, 0, 0)])
	var solo := _controller([walker, foe])
	var intent := solo.player_intent(walker, AiDecision.Action.ADVANCE, foe)
	assert_bool(intent.has("refused")) \
		.override_failure_message("same band, same action: the Advance stays legal") \
		.is_false()
	if intent.has("refused"):
		return
	assert_bool(bool(intent.get("shoot", true))) \
		.override_failure_message("rules 3.6: a Cumbersome unit that advances fires nothing") \
		.is_false()


func test_epoch_72_still_runs_its_rush_and_advance_shoot() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var walker := _unit(2, "Walker", [Vector3.ZERO], ["Cumbersome"], [{"name": "Rifle", "range": 24}])
	var foe := _unit(1, "Foe", [Vector3(10 * IN2M, 0, 0)])
	var solo := _controller([walker, foe])
	var rush := solo.player_intent(walker, AiDecision.Action.RUSH, foe)
	assert_bool(rush.has("refused")) \
		.override_failure_message("rules 3.5: the Cumbersome name is inert, the old rush stays") \
		.is_false()
	var advance := solo.player_intent(walker, AiDecision.Action.ADVANCE, foe)
	assert_bool(bool(advance.get("shoot", false))) \
		.override_failure_message("rules 3.5: Advance & Shoot still fires below epoch 73") \
		.is_true()


## The live planner menu. A Cumbersome gunner 10" from its marker, foe in range: hold rows stay,
## one PLAIN advance per marker is offered, and no Rush/Charge/advance-shot candidate appears.
func test_the_planner_menu_at_epoch_73_offers_only_hold_or_a_plain_advance() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var gunner := _unit(2, "Gunner", [Vector3.ZERO], ["Cumbersome"], [{"name": "Rifle", "range": 24}])
	var foe := _unit(1, "Foe", [Vector3(18 * IN2M, 0, 0)])
	var state := _state([gunner, foe], [Vector3(10 * IN2M, 0, 0)])
	for menu in [AiPlanner.candidates(state, "gunner"), AiPlanner.candidates_wide(state, "gunner")]:
		assert_int(_of_kind(menu, AiDecision.Action.RUSH).size()) \
			.override_failure_message("rules 3.6: no Rush candidate for a Cumbersome unit (%s)" % str(menu)) \
			.is_equal(0)
		assert_int(_of_kind(menu, AiDecision.Action.CHARGE).size()) \
			.override_failure_message("rules 3.6: no Charge candidate for a Cumbersome unit (%s)" % str(menu)) \
			.is_equal(0)
		var shooting_advances := _of_kind(menu, AiDecision.Action.ADVANCE) \
			.filter(func(c: Dictionary) -> bool: return c.has("shoot"))
		assert_int(shooting_advances.size()) \
			.override_failure_message("rules 3.6: an advance never carries a shot (%s)" % str(menu)) \
			.is_equal(0)
		assert_bool(_of_kind(menu, AiDecision.Action.ADVANCE).size() > 0
			or not _of_kind(menu, AiDecision.Action.HOLD).is_empty()) \
			.override_failure_message("the pick must stay Hold (maybe shooting) or a plain Advance (%s)" % str(menu)) \
			.is_true()


func test_the_planner_menu_at_epoch_72_still_offers_a_rush() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var gunner := _unit(2, "Gunner", [Vector3.ZERO], ["Cumbersome"], [{"name": "Rifle", "range": 24}])
	var foe := _unit(1, "Foe", [Vector3(18 * IN2M, 0, 0)])
	var state := _state([gunner, foe], [Vector3(10 * IN2M, 0, 0)])
	assert_bool(_of_kind(AiPlanner.candidates(state, "gunner"), AiDecision.Action.RUSH).size() > 0) \
		.override_failure_message("rules 3.5: the old menu still offers its Rush") \
		.is_true()


## The enemy reply model: a Cumbersome gun 28" away cannot advance into its 24" reach at epoch 73,
## so it threatens nothing; below 73 the same gun advance-shoots. Standing volleys stay untouched.
func _gun_reply_at(epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	BattleSim.reply_v2 = true
	BattleSim.reply_hold_gate = false
	var gun := _unit(1, "Gun", [Vector3.ZERO], ["Cumbersome"], [{"name": "Cannon", "range": 24}])
	var squad := _unit(2, "Squad", [Vector3(28 * IN2M, 0, 0)], [], [{"name": "CCW", "range": 0}])
	return BattleSim.reply_threat(_capture([gun, squad]), 2)


func test_the_enemy_reply_does_not_advance_shoot_a_cumbersome_gun_at_epoch_73() -> void:
	var threat := _gun_reply_at(AiActRecorder.EPOCH_73_V36)
	assert_float(float(threat.get("squad", 0.0))) \
		.override_failure_message("rules 3.6: the Cumbersome gun may not advance and fire, got %s" % threat) \
		.is_equal(0.0)


func test_the_enemy_reply_advance_shoots_at_epoch_72() -> void:
	var threat := _gun_reply_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_float(float(threat.get("squad", 0.0))) \
		.override_failure_message("rules 3.5: the gun may advance 6\" into reach and fire, got %s" % threat) \
		.is_greater(0.0)
