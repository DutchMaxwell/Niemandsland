extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-04 (folds AI-02): Artillery may move like any unit from the rules 3.6
## epoch (73) on; below it (72) it keeps to Hold actions. Immobile keeps to Hold actions at both.
## The player's move feeder and the AI's own gate answer alike (the enemy reply model the planner prices
## is pinned in the core: core/nml-core/src/tests/sim/v36_shoot.rs).

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, unit_name: String, positions: Array, rules: Array = [], weapons: Array = []) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules}
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


func _notes(report: Dictionary) -> PackedStringArray:
	var texts := PackedStringArray()
	for note in report.get("rule_notes", []):
		texts.append(str((note as Dictionary).get("text", "")) if note is Dictionary else str(note))
	return texts


func test_artillery_rush_is_refused_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var gun := _unit(2, "Gun", [Vector3.ZERO], ["Artillery"])
	var target := _unit(1, "Target", [Vector3(20 * IN2M, 0, 0)])
	var solo := _controller([gun, target])
	var intent := solo.player_intent(gun, AiDecision.Action.RUSH, target)
	assert_str(str(intent.get("refused", ""))) \
		.override_failure_message("rules 3.5: Artillery may only Hold, the rush must be refused") \
		.contains("Hold")


func test_artillery_rush_moves_and_logs_once_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var gun := _unit(2, "Gun", [Vector3.ZERO], ["Artillery"])
	var target := _unit(1, "Target", [Vector3(20 * IN2M, 0, 0)])
	var solo := _controller([gun, target])
	var intent := solo.player_intent(gun, AiDecision.Action.RUSH, target)
	assert_bool(intent.has("refused")) \
		.override_failure_message("rules 3.6: Artillery may move, got refused: %s" % intent.get("refused", "")) \
		.is_false()
	if intent.has("refused"):
		return
	var report := solo.execute_intent(intent, ActIntent.blank_report(gun))
	assert_bool(bool(report.get("moved", false))).is_true()
	var hits := 0
	for text in _notes(report):
		if text.contains("Artillery") and text.contains("3.6"):
			hits += 1
	assert_int(hits) \
		.override_failure_message("one battle-log line must say Artillery moves under rules 3.6: %s" % "\n".join(_notes(report))) \
		.is_equal(1)


func test_immobile_rush_is_still_refused_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var turret := _unit(2, "Turret", [Vector3.ZERO], ["Immobile"])
	var target := _unit(1, "Target", [Vector3(20 * IN2M, 0, 0)])
	var solo := _controller([turret, target])
	assert_str(str(solo.player_intent(turret, AiDecision.Action.RUSH, target).get("refused", ""))).contains("Hold")
