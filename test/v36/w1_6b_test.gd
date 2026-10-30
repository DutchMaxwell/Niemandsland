extends GdUnitTestSuite
## W1.6b (0.3.15, rules 3.6): batch 2 of the Boost -> Enhanced rename (D-ENH, no alias). Rules 3.6
## books print "Enhanced <X>" where 3.5 books printed "<X> Boost" (and "Enhanced <X> Aura" for the
## carried form). The gf and aof maps resolve each 3.6 name to the same primitive and params the 3.5
## entry had, a carried form hands out the 3.6 base name, and the 3.5 name is gone from the map.
## Every case reads the real maps through RulesRegistry.

## The batch's 3.6 names next to the 3.5 names they replace.
const RENAMED := {
	"Enhanced Ferocious": "Ferocious Boost",
	"Enhanced Ferocious Aura": "Ferocious Boost Aura",
	"Enhanced Guardian": "Guardian Boost",
	"Enhanced Guardian Aura": "Guardian Boost Aura",
	"Enhanced Guerrilla": "Guerrilla Boost",
	"Enhanced Guerrilla Aura": "Guerrilla Boost Aura",
	"Enhanced Harassing": "Harassing Boost",
	"Enhanced Harassing Aura": "Harassing Boost Aura",
	"Enhanced Havocbound": "Havocbound Boost",
	"Enhanced Havocbound Aura": "Havocbound Boost Aura",
	"Enhanced Highborn": "Highborn Boost",
	"Enhanced Highborn Aura": "Highborn Boost Aura",
}

## [system, faction, 3.6 name, primitive, params] - the params the 3.5 entry carries today, with a
## carried form's grant spelled with the 3.6 base name. JSON numbers read back as floats.
const CASES := [
	["gf", "havoc_brothers", "Enhanced Havocbound", "Piercing Hunter",
		{"ap_bonus": 1.0, "always": true, "upgrades": "Havocbound"}],
	["gf", "custodian_brothers", "Enhanced Guardian", "Fortified", {"incoming_ap_reduction": 1.0}],
	["gf", "rebel_guerrillas", "Enhanced Guerrilla Aura", "Aura Channel", {"grants": "Enhanced Guerrilla"}],
	["aof", "orcs", "Enhanced Ferocious", "Surge", {"upgrades": "Ferocious", "surge_low": 5.0, "over_in": 9.0}],
	["aof", "high_elves", "Enhanced Highborn", "Fast", {"advance_mod": 4.0, "rush_mod": 4.0, "upgrades": "Highborn"}],
	["aof", "dark_elves", "Enhanced Harassing", "Hit & Run", {"move_in": 6.0, "upgrades": "Harassing"}],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func test_the_3_6_names_resolve_to_the_primitive_and_params_of_their_3_5_boost() -> void:
	for c: Array in CASES:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"%s %s: '%s' does not resolve to %s" % [c[0], c[1], c[2], c[3]]).is_equal(c[3])
		assert_dict(entry.get("params", {})).override_failure_message(
			"%s %s: '%s' params differ from its 3.5 entry: %s" % [c[0], c[1], c[2], entry]).is_equal(c[4])
		assert_dict(RulesRegistry.lookup(c[0], c[1], RENAMED[c[2]])).override_failure_message(
			"%s %s: the 3.5 name '%s' still resolves (no alias)" % [c[0], c[1], RENAMED[c[2]]]).is_empty()


## No faction entry, carried grant or modeled token of the gf / aof maps still names a batch 3.5 name.
func test_no_batch_3_5_name_is_left_in_the_gf_and_aof_maps() -> void:
	for system: String in ["gf", "aof"]:
		var m := RulesRegistry.map_for(system)
		var left: Array = []
		for token: Variant in m.get("modeled", []):
			if RENAMED.values().has(str(token)):
				left.append("modeled: %s" % token)
		for faction: String in m.get("factions", {}):
			var fmap: Dictionary = m["factions"][faction]
			for rule: String in fmap:
				var params: Dictionary = (fmap[rule] as Dictionary).get("params", {})
				for named: String in [rule, str(params.get("grants", "")), str(params.get("grants_rule", ""))]:
					if RENAMED.values().has(named):
						left.append("%s/%s: %s" % [faction, rule, named])
		assert_array(left).override_failure_message(
			"%s map still names batch 3.5 names: %s" % [system, left]).is_empty()


## Each 3.6 name of the batch is a modeled token of the maps that field it.
func test_the_3_6_names_are_modeled_tokens() -> void:
	var gf := RulesRegistry.modeled_tokens("gf")
	var aof := RulesRegistry.modeled_tokens("aof")
	for token: String in RENAMED:
		assert_bool(gf.has(token)).override_failure_message("gf does not model '%s'" % token).is_true()
	for token: String in ["Enhanced Ferocious", "Enhanced Harassing Aura", "Enhanced Havocbound",
			"Enhanced Highborn Aura"]:
		assert_bool(aof.has(token)).override_failure_message("aof does not model '%s'" % token).is_true()


## The spell maps hand out the 3.6 names too: a gf / aof spell that granted a batch 3.5 name now
## grants its 3.6 name, and that name resolves in the caster's own faction of the live (epoch 73)
## rules map, so the granted upgrade works when the spell lands. No spell grants a 3.5 name.
func test_a_spell_granting_a_renamed_upgrade_resolves_its_3_6_name_at_epoch_73() -> void:
	SpellsRegistry.reset_cache()
	assert_int(AiActRecorder.rules_epoch).is_equal(73)
	var picks := [["gf", "havoc_brothers", "Havoc Boon", "Enhanced Havocbound"],
		["aof", "orcs", "Way-Clan Chant", "Enhanced Ferocious"]]
	for pick: Array in picks:
		var effect: Variant = SpellsRegistry.entry_for(pick[0], pick[1], pick[2]).get("effect")
		var grant := str((effect as Dictionary).get("grants_rule", "")) if effect is Dictionary else ""
		assert_str(grant).override_failure_message(
			"%s %s '%s' grants '%s'" % [pick[0], pick[1], pick[2], grant]).is_equal(pick[3])
	var granted := 0
	for system: String in ["gf", "aof"]:
		var factions: Dictionary = SpellsRegistry.map_for(system).get("factions", {})
		for faction: String in factions:
			for sp: Variant in (factions[faction] as Dictionary).get("spells", []):
				var eff: Variant = (sp as Dictionary).get("effect")
				var grant := str((eff as Dictionary).get("grants_rule", "")) if eff is Dictionary else ""
				assert_bool(RENAMED.values().has(grant)).override_failure_message(
					"%s %s: a spell still grants the 3.5 name '%s'" % [system, faction, grant]).is_false()
				if RENAMED.has(grant):
					granted += 1
					assert_bool(RulesRegistry.lookup(system, faction, grant).is_empty()).override_failure_message(
						"%s %s: the granted '%s' does not resolve" % [system, faction, grant]).is_false()
	assert_int(granted).override_failure_message("no spell grants a batch 3.6 name").is_equal(10)
