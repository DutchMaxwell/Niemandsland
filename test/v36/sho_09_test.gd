extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-09: the conditional-AP target hook. Two new condition spellings the 3.6
## weapon-family data rows will use: over_half_range (shooting from beyond half the weapon's range)
## and def_5_6 (the target's Defense value is 5+ or 6+). No shipped 3.5 entry spells either name, so
## the hook needs no epoch gate: the _at_epoch_72 test pins every existing condition unchanged, the
## _at_epoch_73 tests the new answers. RED before the hook: an unknown condition answered 0, so the
## table, the pure function and the EV all ignored both entries.

const MainScript := preload("res://scripts/main.gd")

const OVER_HALF := {"ap_bonus": 1, "condition": "over_half_range"}
const DEF_5_6 := {"ap_bonus": 1, "condition": "def_5_6"}
const ATT := {"quality": 4, "models": 5}


func after_test() -> void:
	RulesRegistry.reset_cache()


func _rifle(over: Dictionary = {}) -> Dictionary:
	var p := {"name": "Probe Gun", "attacks": 8, "ap": 0, "deadly": 0, "relentless": false, "blast": 0,
		"reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "range": 24, "rules": []}
	for k in over:
		p[k] = over[k]
	return p


func _unit(defense: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_def%d" % defense
	u.unit_properties = {"player_id": 1, "name": "U", "quality": 4, "defense": defense,
		"special_rules": [], "game_system": "gf", "faction_folder": ""}
	return u


## A gf book whose common section carries one probe weapon rule per new spelling — the shape the
## 3.6 data rows will ship (no real book spells these names yet).
func _probe_book() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"common": {
		"Probe Far": {"params": OVER_HALF.duplicate()},
		"Probe Soft": {"params": DEF_5_6.duplicate()}}}


func test_def_5_6_pays_only_against_a_5_plus_or_6_plus_target_at_epoch_73() -> void:
	assert_int(AiCombatMath.conditional_ap_bonus(DEF_5_6, 1, 5, false)).is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(DEF_5_6, 1, 6, false)).is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(DEF_5_6, 1, 5, false, 0.0, true)) \
		.override_failure_message("a target property: it pays in melee too").is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(DEF_5_6, 1, 4, false)).is_equal(0)


func test_over_half_range_raises_the_ev_only_beyond_half_the_weapon_range_at_epoch_73() -> void:
	var armed := _rifle({"cond_ap": [OVER_HALF]})
	var plain := _rifle()
	var def_ctx := {"defense": 4, "tough": 1, "models": 5}
	assert_bool(AiEv.profile_ev(armed, ATT, def_ctx, 18.0, false) > AiEv.profile_ev(plain, ATT, def_ctx, 18.0, false)) \
		.override_failure_message("18\" is beyond half of 24\": the AP(+1) must lower the save").is_true()
	assert_float(AiEv.profile_ev(armed, ATT, def_ctx, 12.0, false)) \
		.is_equal_approx(AiEv.profile_ev(plain, ATT, def_ctx, 12.0, false), 0.0001)
	assert_float(AiEv.profile_ev(armed, ATT, def_ctx, 6.0, false)) \
		.is_equal_approx(AiEv.profile_ev(plain, ATT, def_ctx, 6.0, false), 0.0001)


## The table half: the conditional-AP parts carry the rule, its bonus and the condition in words, so the
## battle-log line names both (rules-must-log).
func test_the_table_pays_and_names_the_condition_that_fired_at_epoch_73() -> void:
	_probe_book()
	var main: Node3D = auto_free(MainScript.new())
	var far := _rifle({"rules": ["Probe Far"]})
	assert_array(main._solo_conditional_ap_parts(far, _unit(4), _unit(4), false, 18.0, false)) \
		.contains_exactly([{"name": "Probe Far", "bonus": 1, "why": "target beyond half the weapon's range"}])
	assert_array(main._solo_conditional_ap_parts(far, _unit(4), _unit(4), false, 12.0, false)).is_empty()
	assert_array(main._solo_conditional_ap_parts(far, _unit(4), _unit(4), false, -1.0, false)) \
		.override_failure_message("no distance known: the ranged leg stays shut").is_empty()
	var soft := _rifle({"rules": ["Probe Soft"]})
	assert_array(main._solo_conditional_ap_parts(soft, _unit(4), _unit(5), false, 6.0, false)) \
		.contains_exactly([{"name": "Probe Soft", "bonus": 1, "why": "target defends on 5+ or 6+"}])
	assert_array(main._solo_conditional_ap_parts(soft, _unit(4), _unit(4), false, 6.0, false)).is_empty()


## Control: every condition that exists before the hook answers exactly as before.
func test_existing_conditions_answer_unchanged_at_epoch_72() -> void:
	var tough := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(tough, 3, 4, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(tough, 2, 4, false)).is_equal(0)
	var armor := {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(armor, 1, 3, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(armor, 1, 5, false)).is_equal(0)
	var far := {"ap_bonus": 2, "condition": "ranged_over", "over_in": 9.0}
	assert_int(AiCombatMath.conditional_ap_bonus(far, 1, 5, false, 12.0, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(far, 1, 5, false, 6.0, false)).is_equal(0)
	var near := {"ap_bonus": 2, "condition": "ranged_within", "within_in": 12.0}
	assert_int(AiCombatMath.conditional_ap_bonus(near, 1, 5, false, 12.0, false)).is_equal(2)
	var charge := {"ap_bonus": 2, "condition": "on_charge"}
	assert_int(AiCombatMath.conditional_ap_bonus(charge, 1, 5, true, 0.0, true)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(charge, 1, 5, false, 0.0, true)).is_equal(0)
