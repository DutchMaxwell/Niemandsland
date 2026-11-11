extends GdUnitTestSuite
## UX-17 (rules 3.6): Bounding / Nimble / Dash MOVE the rolled inches instead of placing the unit.
## The table AI already spends the roll as a bonus on every move band, so its move keeps the normal
## path rules; from EPOCH_73_V36 its decision record says the unit moves, at EPOCH_72 the old words
## stay. The band bonus itself (the rolled faces plus the rule's flat inches) is the same at both epochs.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _unit(pid: int, uid: String, pos: Vector3) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	return u


## One seeded AI activation of a gf/eternal_dynasty "Bounding" unit far from its foe, at `epoch`.
## Returns the activation's decision log.
func _activate_bounder(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var foe := _unit(1, "Foe", Vector3(30.0 * IN2M, 0, 0))
	var ai := _unit(2, "Bounder", Vector3.ZERO)
	ai.unit_properties["special_rules"] = ["Bounding"]
	ai.unit_properties["game_system"] = "gf"
	ai.unit_properties["faction_folder"] = "eternal_dynasty"
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {foe.unit_id: foe, ai.unit_id: ai}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo._rng.seed = 7
	solo._act(ai)
	return solo.decision_log.duplicate()


func _bounding_record(dlog: Array) -> Dictionary:
	for rec in dlog:
		if str((rec as Dictionary).get("why", "")) == "bounding placement":
			return rec
	return {}


## The band bonus the record carries is exactly the rolled D3 plus Bounding's flat inch.
func _assert_bonus_is_the_roll(dlog: Array) -> float:
	var rec := _bounding_record(dlog)
	assert_bool(rec.is_empty()).override_failure_message("no Bounding record: %s" % [dlog]).is_false()
	var face := -1
	for r in dlog:
		if str((r as Dictionary).get("tag", "")) == "bounding_d3":
			face = int(r["value"])
	assert_int(face).is_between(1, 3)
	var bonus := float(rec["data"]["bonus_in"])
	assert_float(bonus).is_equal_approx(float(face) + 1.0, 0.001)
	return bonus


func test_bounding_record_keeps_the_placed_wording_at_epoch_72() -> void:
	var dlog := _activate_bounder(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	_assert_bonus_is_the_roll(dlog)
	var text := str(_bounding_record(dlog)["rule"])
	assert_str(text).contains("Bounding")
	assert_str(text).contains("placed")


func test_bounding_record_says_the_unit_moves_at_epoch_73() -> void:
	var dlog := _activate_bounder(AiActRecorder.EPOCH_73_V36)
	_assert_bonus_is_the_roll(dlog)
	var text := str(_bounding_record(dlog)["rule"])
	assert_str(text).contains("Bounding")
	assert_str(text).contains("moves up to")
	assert_str(text).not_contains("placed")


func test_bounding_band_bonus_is_the_same_at_epoch_72_and_at_epoch_73() -> void:
	var b72 := _assert_bonus_is_the_roll(_activate_bounder(AiActRecorder.EPOCH_72_PLAYTEST_RULES))
	var b73 := _assert_bonus_is_the_roll(_activate_bounder(AiActRecorder.EPOCH_73_V36))
	assert_float(b73).is_equal_approx(b72, 0.001)
