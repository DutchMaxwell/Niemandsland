extends GdUnitTestSuite
## Rules 3.6 row SHO-11 (lane shoot): the four data rows on the conditional-AP hook.
## Destructive, Shatter and Disintegrate keep their 3.5 names but change meaning;
## Purge is new. The tests read the REAL maps through RulesRegistry and reach the
## live stamp/resolution seams, never a hand-built copy of the field under test.

const MainScript := preload("res://scripts/main.gd")

## [system, book, rule, primitive, params, book_version] - the 3.6 books that print each.
const PINNED := [
	["gf", "jackals", "Shatter", "Shatter", {"on6_ap": 3.0}],
	["gf", "robot_legions", "Shatter", "Shatter", {"on6_ap": 3.0}],
	["aof", "kingdom_of_angels", "Shatter", "Shatter", {"on6_ap": 3.0}],
	["aof", "ossified_undead", "Shatter", "Shatter", {"on6_ap": 3.0}],
	["gf", "elven_jesters", "Destructive", "Destructive",
		{"ap_bonus": 1.0, "condition": "above_half_strength"}],
	["gf", "eternal_dynasty", "Destructive", "Destructive",
		{"ap_bonus": 1.0, "condition": "above_half_strength"}],
	["aof", "shadow_stalkers", "Destructive", "Destructive",
		{"ap_bonus": 1.0, "condition": "above_half_strength"}],
	["aof", "sky_city_dwarves", "Destructive", "Destructive",
		{"ap_bonus": 1.0, "condition": "above_half_strength"}],
	["gf", "jackals", "Disintegrate", "Disintegrate",
		{"ap_bonus": 2.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["gf", "custodian_brothers", "Disintegrate", "Disintegrate",
		{"ap_bonus": 2.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["aof", "beastmen", "Disintegrate", "Disintegrate",
		{"ap_bonus": 2.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["gf", "blessed_sisters", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["gf", "daemons_of_war", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["gf", "titan_lords_war_disciples", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["gf", "war_disciples", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["aof", "daemons_of_war", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["aof", "giant_tribes_war_disciples", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["aof", "havoc_dwarves", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
	["aof", "war_disciples", "Purge", "Purge",
		{"ap_bonus": 2.0, "condition": "shaken_or_fatigued"}],
]


func before_test() -> void:
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func _unit(faction: String, alive: int = 1, models: int = 1, rules: Array = []) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho11_%s_%d_%d" % [faction, alive, models]
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = i < alive
		m.wounds_max = 1
		m.wounds_current = 1
		u.models.append(m)
	return u


func _weapon(rule: String) -> Dictionary:
	return {"name": "Blade", "range_value": 0, "attacks": 8, "count": 1, "special_rules": [rule]}


## The live stamp chain the table uses: weapon -> profile -> Sergeant -> conditional AP.
func _stamped(faction: String, rule: String, epoch: int = AiActRecorder.EPOCH_73_V36) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var unit := _unit(faction)
	var profiles := AiEv.stamp_sergeant(AiShooting.melee_profiles([_weapon(rule)]), unit)
	return (AiEv.stamp_conditional_ap(profiles, unit)[0] as Dictionary).duplicate()


func test_the_3_6_books_carry_the_new_rows() -> void:
	for c: Array in PINNED:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"%s/%s: '%s' must exist" % [c[0], c[1], c[2]]).is_equal(c[3])
		assert_str(str(entry.get("book_version", ""))).is_equal("3.6.0")
		assert_dict(entry.get("params", {})).is_equal(c[4])


func test_purge_is_no_longer_applied_by_hand() -> void:
	var main: Node3D = auto_free(MainScript.new())
	var modeled: Array = main._solo_modeled_rules_for(_unit("blessed_sisters", 1, 1, ["Purge"]))
	assert_bool(modeled.has("Purge")).override_failure_message(
		"Purge must be resolved once its book prints it").is_true()


func test_destructive_keeps_the_3_5_on6_below_73_and_drops_it_at_73() -> void:
	var old := _stamped("elven_jesters", "Destructive", AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_bool(bool(old.get("destructive", false))).override_failure_message(
		"below the wave the 3.5 unmodified-six AP(+4) still rides the profile").is_true()
	var now := _stamped("elven_jesters", "Destructive")
	assert_bool(now.has("destructive")).override_failure_message(
		"from 73 the fixed on-6 AP is gone").is_false()
	var specs: Array = now.get("cond_ap", [])
	if specs.is_empty():
		fail("from 73 Destructive stamps the above-half-strength condition")
		return
	assert_array(specs).is_not_empty()
	assert_str(str((specs[0] as Dictionary).get("condition", ""))).is_equal("above_half_strength")
	assert_int(int((specs[0] as Dictionary).get("ap_bonus", 0))).is_equal(1)


func test_destructive_prices_ap1_against_a_target_above_half_strength() -> void:
	var main: Node3D = auto_free(MainScript.new())
	var striker := _unit("elven_jesters")
	var profile := _stamped("elven_jesters", "Destructive")
	var high: Array = main._solo_conditional_ap_parts(profile, striker, _unit("elven_jesters", 5, 5), false, 6.0, true)
	var low: Array = main._solo_conditional_ap_parts(profile, striker, _unit("elven_jesters", 2, 5), false, 6.0, true)
	if high.is_empty():
		fail("Destructive must price AP(+1) against a target above half strength")
		return
	assert_int(int((high[0] as Dictionary).get("bonus", 0))).is_equal(1)
	assert_str(str((high[0] as Dictionary).get("why", ""))).is_equal("target is above half strength")
	assert_array(low).is_empty()


func test_shatter_prices_ap3_on_the_unmodified_sixes() -> void:
	var profile := _stamped("robot_legions", "Shatter")
	assert_int(int(profile.get("on6_ap", 0))).override_failure_message(
		"Shatter is the 3.6 on-6 AP(+3) shape, not the 3.5 Tough-3 condition").is_equal(3)
	assert_array(profile.get("cond_ap", [])).is_empty()


func test_disintegrate_prices_ap2_against_tough3() -> void:
	var main: Node3D = auto_free(MainScript.new())
	var profile := _stamped("custodian_brothers", "Disintegrate")
	var striker := _unit("custodian_brothers")
	var tough := _unit("custodian_brothers", 3, 3, ["Tough(3)"])
	var soft := _unit("custodian_brothers", 3, 3, ["Tough(2)"])
	var high: Array = main._solo_conditional_ap_parts(profile, striker, tough, false, 6.0, true)
	var low: Array = main._solo_conditional_ap_parts(profile, striker, soft, false, 6.0, true)
	if high.is_empty():
		fail("Disintegrate must price AP(+2) against a Tough 3+ target")
		return
	assert_int(int((high[0] as Dictionary).get("bonus", 0))).is_equal(2)
	assert_array(low).is_empty()


func test_purge_prices_ap2_against_shaken_or_fatigued() -> void:
	var main: Node3D = auto_free(MainScript.new())
	var profile := _stamped("blessed_sisters", "Purge")
	var striker := _unit("blessed_sisters")
	var shaken := _unit("blessed_sisters", 3, 3)
	shaken.is_shaken = true
	var steady := _unit("blessed_sisters", 3, 3)
	var high: Array = main._solo_conditional_ap_parts(profile, striker, shaken, false, 6.0, true)
	var low: Array = main._solo_conditional_ap_parts(profile, striker, steady, false, 6.0, true)
	if high.is_empty():
		fail("Purge must price AP(+2) against a Shaken or Fatigued target")
		return
	assert_int(int((high[0] as Dictionary).get("bonus", 0))).is_equal(2)
	assert_array(low).is_empty()
