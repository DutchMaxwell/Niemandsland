extends GdUnitTestSuite
## Rules 3.6 wave, row UX-01 (Transport): a unit only climbs into a transport of its own side, and on the
## table it may do so once one of its models stands within 2" of the transport, base edge to base edge.
## The own-side check holds at every epoch (the menu never offered an enemy truck, the gate below it simply
## never asked); the wider reach is new at EPOCH_73_V36, the epoch-72 leg keeps the old 1".

const INCH := 0.0254

var _mgr: OPRArmyManager
var _radial: RadialMenuController
var _log: BattleLog
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	_mgr = auto_free(OPRArmyManager.new())
	_mgr.game_phase = OPRArmyManager.GamePhase.PLAYING
	_log = auto_free(BattleLog.new())
	_radial = auto_free(RadialMenuController.new())
	add_child(_radial)   # the log hop looks for main by absolute path, which needs the tree
	_radial.army_manager = _mgr
	_radial.battle_log = _log


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(id: String, n: int, rules: Array, pid: int) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "special_rules": rules, "name": id}
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


func _radius(u: GameUnit) -> float:
	return SeparationChecker.shape_for_model(u.models[0] as ModelInstance).bounding_radius()


## A transport at the origin and a three-model squad in a file along +x whose nearest base edge stands
## `gap_in` inches from the transport's base edge.
func _truck_and_squad(gap_in: float, truck_pid: int = 1) -> Array:
	var truck := _unit("truck", 1, ["Transport(6)"], truck_pid)
	var squad := _unit("squad", 3, [], 1)
	var near := gap_in * INCH + _radius(truck) + _radius(squad)
	for i in range(squad.models.size()):
		(squad.models[i] as ModelInstance).node.global_position = Vector3(near + 0.03 * i, 0.0, 0.0)
	return [truck, squad]


func _log_text() -> String:
	var text := ""
	for e in _log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _assert_enemy_truck_refused() -> void:
	var tc := _truck_and_squad(0.5, 2)
	var gate: Dictionary = _mgr.can_embark(tc[1], tc[0])
	assert_bool(bool(gate.get("ok", true))) \
		.override_failure_message("a unit of player 1 may not climb into player 2's transport") \
		.is_false()
	assert_str(str(gate.get("reason", ""))).contains("belongs to the other player")


func test_an_enemy_transport_refuses_the_unit_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	_assert_enemy_truck_refused()
	AiActRecorder.rules_epoch = _epoch_before


func test_an_enemy_transport_refuses_the_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_assert_enemy_truck_refused()
	AiActRecorder.rules_epoch = _epoch_before


## The refusal reaches the player through the radial's existing "cannot embark" log line, and the
## unit stays on the table.
func test_the_enemy_refusal_is_logged_and_nothing_embarks_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tc := _truck_and_squad(0.5, 2)
	_radial._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_mgr.transport_of(tc[1])) \
		.override_failure_message("the squad climbed into the enemy's transport") \
		.is_null()
	assert_str(_log_text()).contains("squad cannot embark")
	assert_str(_log_text()).contains("belongs to the other player")
	AiActRecorder.rules_epoch = _epoch_before


func test_a_unit_one_and_a_half_inches_away_is_not_offered_embark_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tc := _truck_and_squad(1.5)
	assert_array(_radial._embark_targets_for(tc[1])) \
		.override_failure_message("the epoch-72 leg keeps the old 1\" reach") \
		.is_empty()
	AiActRecorder.rules_epoch = _epoch_before


func test_a_unit_one_and_a_half_inches_away_is_offered_embark_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tc := _truck_and_squad(1.5)
	assert_array(_radial._embark_targets_for(tc[1])) \
		.override_failure_message("within 2\" (base edge to base edge) the squad must be offered Embark") \
		.contains_exactly([tc[0]])
	AiActRecorder.rules_epoch = _epoch_before


func test_a_unit_three_inches_away_is_not_offered_embark_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tc := _truck_and_squad(3.0)
	assert_array(_radial._embark_targets_for(tc[1])).is_empty()
	AiActRecorder.rules_epoch = _epoch_before


func test_a_unit_three_inches_away_is_not_offered_embark_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tc := _truck_and_squad(3.0)
	assert_array(_radial._embark_targets_for(tc[1])) \
		.override_failure_message("3\" is beyond the 2\" reach") \
		.is_empty()
	AiActRecorder.rules_epoch = _epoch_before


func test_the_embark_line_names_transport_without_a_new_reach_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tc := _truck_and_squad(0.5)
	_radial._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_mgr.transport_of(tc[1])).is_same(tc[0])
	assert_str(_log_text()).contains("squad embarks into truck")
	assert_str(_log_text()).contains("Transport")
	assert_str(_log_text()).not_contains("2\"")
	AiActRecorder.rules_epoch = _epoch_before


func test_the_embark_line_names_transport_and_the_two_inch_reach_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tc := _truck_and_squad(1.5)
	_radial._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_mgr.transport_of(tc[1])).is_same(tc[0])
	assert_str(_log_text()).contains("squad embarks into truck")
	assert_str(_log_text()).contains("Transport")
	assert_str(_log_text()).contains("within 2\"")
	AiActRecorder.rules_epoch = _epoch_before
