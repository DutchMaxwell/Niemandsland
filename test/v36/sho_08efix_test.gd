extends GdUnitTestSuite
## SHO-08e-fix (rules 3.6): the AI's expected-wound estimate clamps the bearer's spell
## net with the enemy side, exactly like the resolver's `m - own` clamp in dice.rs. A
## lone spell -1 is dropped; a +2 spell into a -1 Stealth target nets +1. Below the
## clamp nothing changes and epoch < 73 stays byte-identical.

const ATT := {"quality": 4, "models": 5}
const ATT_SPELL_MINUS := {"quality": 4, "models": 5, "spell_hit_mod": -1}
const ATT_SPELL_TWO := {"quality": 4, "models": 5, "spell_hit_mod": 2}
const DEF_PLAIN := {"defense": 4, "tough": 1, "models": 5}
const DEF_STEALTH := {"defense": 4, "tough": 1, "models": 5, "stealth": true}

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


## The estimate prices the resolver's net: +2 spell into a -1 Stealth target is +1.
func test_the_estimate_matches_the_resolver_spell_net_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var estimated: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_SPELL_TWO, DEF_STEALTH, 12.0, false)
	var net_one: float = AiEv.profile_ev(_rprof({"unstoppable": true}),
		{"quality": 4, "models": 5, "spell_hit_mod": 1}, DEF_PLAIN, 12.0, false)
	assert_float(estimated).is_equal_approx(net_one, 0.0001)


## Beyond the clamp: a lone spell -1 is dropped (the resolver's floor), shooting and melee.
func test_a_lone_spell_minus_is_clamped_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var free: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_PLAIN, 12.0, false)
	var clamped: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_SPELL_MINUS, DEF_PLAIN, 12.0, false)
	assert_float(clamped).is_equal_approx(free, 0.0001)
	var m_free: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT, DEF_PLAIN, 0.0, true)
	var m_clamped: float = AiEv.profile_ev(_mprof({"unstoppable": true}), ATT_SPELL_MINUS, DEF_PLAIN, 0.0, true)
	assert_float(m_clamped).is_equal_approx(m_free, 0.0001)


## Below the clamp nothing changes: a +2 spell into a plain target still prices +2.
func test_a_spell_bonus_below_the_clamp_is_unchanged_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var plus_two: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_SPELL_TWO, DEF_PLAIN, 12.0, false)
	var no_spell: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_PLAIN, 12.0, false)
	assert_bool(plus_two > no_spell).is_true()


## CONTROL: epoch < 73 keeps the old single clamp over the whole sum (spell included).
func test_epoch_72_keeps_the_whole_sum_clamp() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var free: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT, DEF_PLAIN, 12.0, false)
	var both: float = AiEv.profile_ev(_rprof({"unstoppable": true}), ATT_SPELL_MINUS, DEF_STEALTH, 12.0, false)
	assert_float(both).is_equal_approx(free, 0.0001)
