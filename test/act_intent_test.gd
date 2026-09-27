extends GdUnitTestSuite
## Automodus A0: ActIntent.validate() refuses the four impossible shapes before any dice are
## touched, and passes the one valid shape through untouched. Pure dictionary logic — no board,
## no nodes, no rendering.


func _unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p1_0"
	u.unit_properties = {"player_id": 1, "name": "U1", "quality": 4, "defense": 4}
	return u


func test_null_unit_is_refused() -> void:
	assert_str(ActIntent.validate({})).is_equal("no unit")


func test_unknown_action_is_refused() -> void:
	var intent := {"unit": _unit(), "action": 99}
	assert_str(ActIntent.validate(intent)).is_equal("unknown action")


func test_charge_without_target_is_refused() -> void:
	var intent := {"unit": _unit(), "action": AiDecision.Action.CHARGE, "target": null}
	assert_str(ActIntent.validate(intent)).is_equal("charge needs a target")


func test_move_action_with_no_band_is_refused() -> void:
	var advance := {"unit": _unit(), "action": AiDecision.Action.ADVANCE, "band_in": 0.0}
	assert_str(ActIntent.validate(advance)).is_equal("no move band")
	var rush := {"unit": _unit(), "action": AiDecision.Action.RUSH, "band_in": -1.0}
	assert_str(ActIntent.validate(rush)).is_equal("no move band")


func test_valid_intent_is_not_refused() -> void:
	var target := _unit()
	var intent := ActIntent.make(_unit(), AiDecision.Action.RUSH, target, Vector3.ZERO, 12.0, false)
	assert_str(ActIntent.validate(intent)).is_equal("")


func test_hold_needs_no_band() -> void:
	var intent := ActIntent.make(_unit(), AiDecision.Action.HOLD, null, Vector3.ZERO, 0.0, true)
	assert_str(ActIntent.validate(intent)).is_equal("")


func test_blank_report_matches_acts_starting_shape() -> void:
	var u := _unit()
	var report := ActIntent.blank_report(u)
	assert_that(report["unit"]).is_equal(u)
	assert_that(report["target"]).is_null()
	assert_int(report["action"]).is_equal(AiDecision.Action.HOLD)
	assert_int(report["toward"]).is_equal(AiDecision.Toward.ENEMY)
	assert_bool(report["shoot"]).is_false()
	assert_bool(report["can_shoot"]).is_false()
	assert_float(report["dist_in"]).is_equal(INF)
	assert_int(report["dangerous_models"]).is_equal(0)
	assert_array(report["rule_notes"]).is_empty()
