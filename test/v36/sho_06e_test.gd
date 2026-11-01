extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-06e: the AI's shooting ESTIMATE prices Artillery the way the resolver
## does at EPOCH_73_V36 — the target's -1 needs most models carrying the rule and no move this
## round, and both the target's -1 and the shooter's +1 only pay past 12". At epoch 72 the
## estimate keeps the old over-9" numbers (+1 shooter, -2 target).
##
## An estimate adds no battle-log line: the rules-must-log rule covers APPLIED rules only, and the
## estimate applies nothing. Only the price changes.

const ATT := {"quality": 4, "models": 5}
const ATT_ART := {"quality": 4, "models": 5, "artillery": true,
	"artillery_shooter_over_in": 12.0, "artillery_shooter_needs_hold": true, "held": true}
const DEF_PLAIN := {"defense": 4, "tough": 1, "models": 5}
const DEF_ART := {"defense": 4, "tough": 1, "models": 5, "artillery": true,
	"artillery_target_over_in": 12.0, "artillery_target_hit_penalty_v36": 1,
	"artillery_target_most_models": true, "held": true}
const DEF_ART_MOVED := {"defense": 4, "tough": 1, "models": 5, "artillery": true,
	"artillery_target_over_in": 12.0, "artillery_target_hit_penalty_v36": 1,
	"artillery_target_most_models": true, "held": false}
## Epoch 72: the ctx carries no v36 keys, exactly what `ctx_for` stamps below the gate.
const ATT_ART_72 := {"quality": 4, "models": 5, "artillery": true, "held": false}
const DEF_ART_72 := {"defense": 4, "tough": 1, "models": 5, "artillery": true}

## 10 Quality-4 attacks into Defense 4+.
const FREE := 2.5
const ONE_MINUS := 10.0 / 3.0 * 0.5     # 5+ to hit
const TWO_MINUS := 10.0 / 6.0 * 0.5     # 6+ to hit
const PLUS_ONE := 10.0 * 4.0 / 6.0 * 0.5  # 3+ to hit

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0


func _rprof() -> Dictionary:
	return {"name": "Rifle", "attacks": 10, "ap": 0, "deadly": 0, "relentless": false, "blast": 0,
		"reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "range": 24, "rules": []}


func _ev(att: Dictionary, def_ctx: Dictionary, dist_in: float) -> float:
	return AiEv.profile_ev(_rprof(), att, def_ctx, dist_in, false)


## RED on main: the estimate still charges the old -2 to an unmoved gun over 12".
func test_an_unmoved_artillery_target_over_12in_is_priced_minus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_float(_ev(ATT, DEF_ART, 13.0)).is_equal_approx(ONE_MINUS, 0.0001)


## A move takes the target's protection away.
func test_an_artillery_target_that_moved_over_12in_is_priced_free_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_float(_ev(ATT, DEF_ART_MOVED, 13.0)).is_equal_approx(FREE, 0.0001)


## Inside 12" the target's -1 is off.
func test_an_unmoved_artillery_target_under_12in_is_priced_free_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_float(_ev(ATT, DEF_ART, 10.0)).is_equal_approx(FREE, 0.0001)


## Control: the shooter's +1 needs a Hold.
func test_an_artillery_shooter_that_moved_over_12in_earns_no_plus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var moved := ATT_ART.duplicate()
	moved["held"] = false
	assert_float(_ev(moved, DEF_PLAIN, 13.0)).is_equal_approx(FREE, 0.0001)


func test_an_artillery_shooter_that_held_over_12in_earns_the_plus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_float(_ev(ATT_ART, DEF_PLAIN, 13.0)).is_equal_approx(PLUS_ONE, 0.0001)


## Epoch 72 keeps the old over-9" numbers byte for byte.
func test_the_old_numbers_stay_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_float(_ev(ATT, DEF_ART_72, 13.0)).is_equal_approx(TWO_MINUS, 0.0001)
	assert_float(_ev(ATT_ART_72, DEF_PLAIN, 13.0)).is_equal_approx(PLUS_ONE, 0.0001)
