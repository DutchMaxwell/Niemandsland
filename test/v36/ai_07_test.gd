extends GdUnitTestSuite
## Rules 3.6 wave, row AI-07: the AI's GDScript estimate reads the successor names of the Versatile
## Attack family. Versatile Expert and Versatile Warrior resolve through the same map primitive the
## stamping already walks, and both carry the 3.6 no-distance-gate switch. Below EPOCH_73_V36 and for
## the legacy literal name the old over-9" read stays. The Rust twin (`unit.rs` SHO-19) stamps the
## same switch on its Ctx, so the same inputs produce the same number.

const ATT := {"quality": 4, "models": 5}
const DEF := {"defense": 4, "tough": 1, "models": 5}

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	RulesRegistry.reset_cache()


func _unit(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "ai07"
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "watch_brothers"}
	return u


func _gun() -> Dictionary:
	return {"name": "Rifle", "range": 24, "attacks": 10, "ap": 0, "deadly": 0, "relentless": false,
		"blast": 0, "reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "rules": []}


func _blade() -> Dictionary:
	return {"name": "Blade", "range": 0, "attacks": 10, "ap": 0, "deadly": 0, "relentless": false,
		"blast": 0, "reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "rules": []}


func _stamped(rules: Array, profile: Dictionary) -> Dictionary:
	AiEv.stamp_sergeant([profile], _unit(rules))
	return profile


## The twin pin: Rust `combat::profile_ev` with `versatile_no_gate` set (unit.rs SHO-19) answers the
## same 10/3 — 10 attacks hit on 4+ (5 hits), the chooser ties and picks AP(+1), Defense 4 saves on 5+.
func test_versatile_expert_shoots_at_six_inches_like_the_rust_twin_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var expert := _stamped(["Versatile Expert"], _gun())
	var ev: float = AiEv.profile_ev(expert, ATT, DEF, 6.0, false)
	assert_float(ev).override_failure_message("Versatile Expert at 6\" must pick AP(+1) or +1 to hit, got %f" % ev) \
		.is_equal_approx(10.0 / 3.0, 0.0001)


func test_versatile_expert_keeps_the_old_gate_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var expert := _stamped(["Versatile Expert"], _gun())
	assert_float(AiEv.profile_ev(expert, ATT, DEF, 6.0, false)) \
		.override_failure_message("epoch 72 keeps the over-9\" read").is_equal_approx(2.5, 0.0001)


func test_versatile_warrior_shoots_over_nine_and_charges_over_six_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shoot: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _gun()), ATT, DEF, 10.0, false)
	var charge: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _blade()), ATT, DEF, 7.0, true)
	assert_float(shoot).override_failure_message("a shot over 9\" benefits, got %f" % shoot) \
		.is_equal_approx(10.0 / 3.0, 0.0001)
	assert_float(charge).override_failure_message("a charge over 6\" benefits, got %f" % charge) \
		.is_equal_approx(10.0 / 3.0, 0.0001)


## AI-07b: at epoch 73 a Warrior CHARGE only benefits over 6" (twin: combat.rs charge_gate_in),
## so 4.0" stays at the plain 2.5 and 7.0" still picks (10/3).
func test_versatile_warrior_charge_uses_the_six_inch_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var inside: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _blade()), ATT, DEF, 4.0, true)
	var outside: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _blade()), ATT, DEF, 7.0, true)
	assert_float(inside).override_failure_message("a charge at 4\" must not pick, got %f" % inside) \
		.is_equal_approx(2.5, 0.0001)
	assert_float(outside).override_failure_message("a charge at 7\" must pick, got %f" % outside) \
		.is_equal_approx(10.0 / 3.0, 0.0001)


## AI-07b: a Warrior SHOT keeps the 9" band at epoch 73 — 6.0" stays at 2.5, 10.0" picks.
func test_versatile_warrior_shot_keeps_the_nine_inch_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var inside: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _gun()), ATT, DEF, 6.0, false)
	var outside: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _gun()), ATT, DEF, 10.0, false)
	assert_float(inside).override_failure_message("a shot at 6\" must not pick, got %f" % inside) \
		.is_equal_approx(2.5, 0.0001)
	assert_float(outside).override_failure_message("a shot at 10\" must pick, got %f" % outside) \
		.is_equal_approx(10.0 / 3.0, 0.0001)


func test_versatile_warrior_keeps_the_old_gates_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shoot: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _gun()), ATT, DEF, 10.0, false)
	var charge: float = AiEv.profile_ev(_stamped(["Versatile Warrior"], _blade()), ATT, DEF, 7.0, true)
	assert_float(shoot).is_equal_approx(10.0 / 3.0, 0.0001)
	assert_float(charge).override_failure_message("epoch 72 keeps the over-9\" charge gate") \
		.is_equal_approx(2.5, 0.0001)


func test_the_old_versatile_attack_name_keeps_its_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shoot: float = AiEv.profile_ev(_stamped(["Versatile Attack"], _gun()), ATT, DEF, 6.0, false)
	var charge: float = AiEv.profile_ev(_stamped(["Versatile Attack"], _blade()), ATT, DEF, 5.0, true)
	assert_float(shoot).override_failure_message("the legacy name keeps the over-9\" shot read") \
		.is_equal_approx(2.5, 0.0001)
	assert_float(charge).override_failure_message("the legacy name keeps the over-9\" charge read") \
		.is_equal_approx(2.5, 0.0001)


func test_the_stamp_reads_the_no_gate_switch_only_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(bool(_stamped(["Versatile Expert"], _gun()).get("versatile_no_gate", false))) \
		.override_failure_message("the 3.6 map entry must stamp the no-gate switch").is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(_stamped(["Versatile Expert"], _gun()).has("versatile_no_gate")) \
		.override_failure_message("epoch 72 stamps no switch").is_false()
