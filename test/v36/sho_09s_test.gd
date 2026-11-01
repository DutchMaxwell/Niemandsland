extends GdUnitTestSuite
## Rules 3.6 row SHO-09s: the two conditional-AP conditions that read TARGET STATE instead of
## geometry — above_half_strength (more than half its models left; a single model: more than half
## its Tough) and shaken_or_fatigued (Shaken OR Fatigued, also while it is being shot at). No
## shipped map entry spells either name, so the arms carry no epoch gate (the SHO-09 precedent):
## the _at_epoch_72 control pins every existing condition unchanged.

const MainScript := preload("res://scripts/main.gd")

const ABOVE := {"ap_bonus": 1, "condition": "above_half_strength"}
const SHAKEN := {"ap_bonus": 1, "condition": "shaken_or_fatigued"}
const ATT := {"quality": 4, "models": 5}


func after_test() -> void:
	RulesRegistry.reset_cache()


func _rifle(over: Dictionary = {}) -> Dictionary:
	var p := {"name": "Probe Gun", "attacks": 8, "ap": 0, "range": 24, "rules": []}
	for k in over:
		p[k] = over[k]
	return p


func _unit(defense: int, models: int = 1) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho09s_%d_%d" % [defense, models]
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": defense,
		"special_rules": [], "game_system": "gf", "faction_folder": ""}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_max = 1
		m.wounds_current = 1
		u.models.append(m)
	return u


func test_the_pure_arm_reads_the_target_state_at_epoch_73() -> void:
	assert_int(AiCombatMath.conditional_ap_bonus(ABOVE, 1, 4, false, 6.0, false,
		{"above_half_strength": true})).is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(ABOVE, 1, 4, false, 6.0, false,
		{"above_half_strength": false})).is_equal(0)
	assert_int(AiCombatMath.conditional_ap_bonus(SHAKEN, 1, 4, false, 6.0, false,
		{"shaken_or_fatigued": true})).is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(SHAKEN, 1, 4, false, 6.0, false, {})).is_equal(0)
	assert_str(AiCombatMath.conditional_ap_why(ABOVE)).is_equal("target is above half strength")
	assert_str(AiCombatMath.conditional_ap_why(SHAKEN)).is_equal("target is Shaken or Fatigued")


func test_the_snapshot_ctx_carries_both_facts_at_epoch_73() -> void:
	var snap := {"unit": _unit(4, 4), "alive": 4, "in_cover": false, "shaken": false,
		"fatigued": true, "wounds": [1, 1, 1, 1]}
	var ctx := BattleSim._ctx_of(snap)
	assert_bool(bool(ctx.get("above_half_strength", false))).is_true()
	assert_bool(bool(ctx.get("shaken_or_fatigued", false))).is_true()
	snap["alive"] = 2
	snap["wounds"] = [1, 1]
	assert_bool(bool(BattleSim._ctx_of(snap).get("above_half_strength", false))).is_false()


func test_the_table_pays_and_names_the_condition_at_epoch_73() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"common": {
		"Probe Half": {"params": ABOVE.duplicate()},
		"Probe Shaken": {"params": SHAKEN.duplicate()}}}
	var main: Node3D = auto_free(MainScript.new())
	var target := _unit(4, 5)
	assert_array(main._solo_conditional_ap_parts(_rifle({"rules": ["Probe Half"]}), _unit(4), target, false, 6.0, false)) \
		.contains_exactly([{"name": "Probe Half", "bonus": 1, "why": "target is above half strength"}])
	var below := _unit(4, 5)
	for i in 3:
		(below.models[i] as ModelInstance).is_alive = false
	assert_array(main._solo_conditional_ap_parts(_rifle({"rules": ["Probe Half"]}), _unit(4), below, false, 6.0, false)).is_empty()
	var shaken := _unit(4, 1)
	shaken.is_shaken = true
	assert_array(main._solo_conditional_ap_parts(_rifle({"rules": ["Probe Shaken"]}), _unit(4), shaken, false, 6.0, false)) \
		.contains_exactly([{"name": "Probe Shaken", "bonus": 1, "why": "target is Shaken or Fatigued"}])


func test_the_ev_prices_the_same_state_at_epoch_73() -> void:
	var armed := _rifle({"cond_ap": [ABOVE]})
	var plain := _rifle()
	var above := {"defense": 4, "tough": 1, "models": 5, "above_half_strength": true}
	var below := {"defense": 4, "tough": 1, "models": 5, "above_half_strength": false}
	assert_bool(AiEv.profile_ev(armed, ATT, above, 6.0, false) > AiEv.profile_ev(plain, ATT, above, 6.0, false)) \
		.override_failure_message("above half: the AP(+1) must lower the save").is_true()
	assert_float(AiEv.profile_ev(armed, ATT, below, 6.0, false)) \
		.is_equal_approx(AiEv.profile_ev(plain, ATT, below, 6.0, false), 0.0001)


func test_existing_conditions_answer_unchanged_at_epoch_72() -> void:
	var tough := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(tough, 3, 4, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(tough, 2, 4, false)).is_equal(0)
	var armor := {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(armor, 1, 3, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(armor, 1, 5, false)).is_equal(0)
	var ranged := {"ap_bonus": 2, "condition": "ranged_over", "over_in": 9.0}
	assert_int(AiCombatMath.conditional_ap_bonus(ranged, 1, 5, false, 12.0, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(ranged, 1, 5, false, 6.0, false)).is_equal(0)
	var charge := {"ap_bonus": 2, "condition": "on_charge"}
	assert_int(AiCombatMath.conditional_ap_bonus(charge, 1, 5, true, 0.0, true)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(charge, 1, 5, false, 0.0, true)).is_equal(0)
