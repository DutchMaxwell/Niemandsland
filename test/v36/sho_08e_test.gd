extends GdUnitTestSuite
## SHO-08e (rules 3.6, CORE 13b): the AI's expected-wound estimate gets the Unstoppable
## own-vs-enemy split. From EPOCH_73_V36 the estimate clamps only the ENEMY-side negative
## hit modifiers; the bearer's own net (the att ctx "spell_hit_mod" seam) stays. At
## EPOCH_72_PLAYTEST_RULES the old single clamp over the whole sum stays byte-identical.

const ATT := {"quality": 4, "models": 5}
const ATT_OWN_MINUS := {"quality": 4, "models": 5, "spell_hit_mod": -1}
const DEF_PLAIN := {"defense": 4, "tough": 1, "models": 5}
const DEF_STEALTH := {"defense": 4, "tough": 1, "models": 5, "stealth": true}
const DEF_EVASIVE := {"defense": 4, "tough": 1, "models": 5, "evasive": true}

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0


func _rprof(over: Dictionary = {}) -> Dictionary:
	var p := {"name": "Rifle", "attacks": 10, "ap": 0, "deadly": 0, "relentless": false, "blast": 0,
		"reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "range": 24, "rules": []}
	for k in over:
		p[k] = over[k]
	return p


func _mprof(over: Dictionary = {}) -> Dictionary:
	var p := _rprof({"name": "Blades", "range": 0})
	for k in over:
		p[k] = over[k]
	return p


## OLD leg: at 72 Unstoppable clamps the whole sum, the own -1 included, so the
## volley prices like the free one (the existing ai_ev_test case is the enemy-only twin).
func test_own_minus_is_clamped_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var free: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_PLAIN, 12.0, false)
	var clamped: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_OWN_MINUS, DEF_STEALTH, 12.0, false)
	assert_float(clamped).is_equal_approx(free, 0.0001)
	var m_free: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT, DEF_PLAIN, 0.0, true)
	var m_clamped: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT_OWN_MINUS, DEF_EVASIVE, 0.0, true)
	assert_float(m_clamped).is_equal_approx(m_free, 0.0001)


## NEW leg: at 73 the bearer's own -1 survives while the target's Stealth -1 is
## ignored, so the volley prices exactly like the own-minus-only one and below free.
func test_own_minus_survives_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var free: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_PLAIN, 12.0, false)
	var own_only: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_OWN_MINUS, DEF_PLAIN, 12.0, false)
	var kept: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_OWN_MINUS, DEF_STEALTH, 12.0, false)
	assert_bool(own_only < free).is_true()
	assert_float(kept).is_equal_approx(own_only, 0.0001)
	# Melee side: the same split against an Evasive target.
	var m_free: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT, DEF_PLAIN, 0.0, true)
	var m_own: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT_OWN_MINUS, DEF_PLAIN, 0.0, true)
	var m_kept: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT_OWN_MINUS, DEF_EVASIVE, 0.0, true)
	assert_bool(m_own < m_free).is_true()
	assert_float(m_kept).is_equal_approx(m_own, 0.0001)


## HOLD: an enemy minus alone is still ignored at both epochs.
func test_enemy_minus_is_still_ignored_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var free: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_PLAIN, 12.0, false)
	var ignored: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_STEALTH, 12.0, false)
	assert_float(ignored).is_equal_approx(free, 0.0001)
	var m_free: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT, DEF_PLAIN, 0.0, true)
	var m_ignored: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT, DEF_EVASIVE, 0.0, true)
	assert_float(m_ignored).is_equal_approx(m_free, 0.0001)


## CONTROL: without Unstoppable the own and enemy minuses both count at 73.
func test_a_plain_weapon_keeps_both_minuses_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var both: float = AiEv.profile_ev(_rprof(), ATT_OWN_MINUS, DEF_STEALTH, 12.0, false)
	var own_only: float = AiEv.profile_ev(_rprof(), ATT_OWN_MINUS, DEF_PLAIN, 12.0, false)
	assert_bool(both < own_only).is_true()
