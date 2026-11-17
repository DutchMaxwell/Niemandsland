extends GdUnitTestSuite
## Rules 3.6 wave, row AI-03b: from the rules 3.6 epoch (73) on a Cumbersome unit may only Hold
## or Advance and fires no volley after it moved, so the live AI refuses Rush and Charge and an
## Advance carries no shot. Below 73 everything keeps its old shape.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0
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
