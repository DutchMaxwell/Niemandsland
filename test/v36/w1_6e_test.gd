extends GdUnitTestSuite
## W1.6e (0.3.15, rules 3.6): batch 5 of the Boost -> Enhanced rename (D-ENH, no alias). Rules 3.6
## books print "Enhanced <X>" where 3.5 books printed "<X> Boost" ("Enhanced <X> Aura" and
## "Enhanced <X> Buff" for the carried forms). The gf and aof maps resolve each 3.6 name to the same
## primitive and params the 3.5 entry had, a carried form hands out the 3.6 base name, the 3.5 name
## is gone from the map, and a spell that granted the 3.5 name grants the 3.6 one. Every case reads
## the real maps through RulesRegistry / SpellsRegistry.

## The batch's 3.6 names next to the 3.5 names they replace.
const RENAMED := {
	"Enhanced Rapid Blink": "Rapid Blink Boost",
	"Enhanced Rapid Blink Aura": "Rapid Blink Boost Aura",
	"Enhanced Royal Legion": "Royal Legion Boost",
	"Enhanced Royal Legion Aura": "Royal Legion Boost Aura",
	"Enhanced Royal Warrior": "Royal Warrior Boost",
	"Enhanced Royal Warrior Aura": "Royal Warrior Boost Aura",
	"Enhanced Scrapper": "Scrapper Boost",
	"Enhanced Scrapper Aura": "Scrapper Boost Aura",
	"Enhanced Scurry": "Scurry Boost",
	"Enhanced Scurry Aura": "Scurry Boost Aura",
	"Enhanced Self-Repair": "Self-Repair Boost",
	"Enhanced Self-Repair Buff": "Self-Repair Boost Buff",
	"Enhanced Shadowborn": "Shadowborn Boost",
	"Enhanced Shadowborn Aura": "Shadowborn Boost Aura",
	"Enhanced Sturdy": "Sturdy Boost",
	"Enhanced Sturdy Aura": "Sturdy Boost Aura",
}

## [system, faction, 3.6 name, primitive, params] - the params the 3.5 entry carries today, with a
## carried form's grant spelled with the 3.6 base name. JSON numbers read back as floats.
const CASES := [
	["gf", "jackals", "Enhanced Scrapper", "Bane", {"upgrades": "Scrapper", "reroll_save_sixes": true,
		"reroll_save_from": 5.0, "over_in": 9.0, "bypass_regen": false}],
	["gf", "ratmen_clans", "Enhanced Scurry Aura", "Aura Channel", {"grants": "Enhanced Scurry"}],
	["gf", "robot_legions", "Enhanced Self-Repair Buff", "Utility Buff",
		{"grants_rule": "Enhanced Self-Repair", "range_in": 12.0, "target": "friendly", "once": true}],
	["gf", "elven_jesters", "Enhanced Rapid Blink", "Bounding", {"place_d3_plus": 0.0, "dice_count": 2.0}],
	["gf", "dwarf_guilds", "Enhanced Sturdy", "Shielded", {"defense_bonus": 1.0, "upgrades": "Sturdy"}],
	["aof", "mummified_undead", "Enhanced Royal Legion", "Royal Legion", {"range_bonus_in": 4.0, "charge_mod": 2.0}],
	["aof", "shadow_stalkers", "Enhanced Shadowborn", "Ranged Shrouding", {"range_penalty_in": 8.0,
		"floor_in": 6.0, "melee_move_penalty_in": 4.0, "melee_floor_in": 6.0}],
	["aof", "dragon_empire", "Enhanced Royal Warrior", "Surge",
		{"upgrades": "Royal Warrior", "extra_attack": true, "surge_low": 5.0}],
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


## Each 3.6 name the code now reads is a modeled token of the maps that field it.
func test_the_3_6_names_are_modeled_tokens() -> void:
	var gf := RulesRegistry.modeled_tokens("gf")
	var aof := RulesRegistry.modeled_tokens("aof")
	for token: String in ["Enhanced Rapid Blink Aura", "Enhanced Scrapper", "Enhanced Scurry Aura",
			"Enhanced Self-Repair", "Enhanced Sturdy"]:
		assert_bool(gf.has(token)).override_failure_message("gf does not model '%s'" % token).is_true()
	for token: String in ["Enhanced Royal Legion", "Enhanced Royal Warrior Aura", "Enhanced Shadowborn",
			"Enhanced Sturdy Aura"]:
		assert_bool(aof.has(token)).override_failure_message("aof does not model '%s'" % token).is_true()


## The spell maps hand out the 3.6 names too: a gf / aof spell that granted a batch 3.5 name now
## grants its 3.6 name, and that name resolves in the caster's own faction of the live (epoch 73)
## rules map, so the granted upgrade works when the spell lands. No spell grants a 3.5 name.
func test_a_spell_granting_a_renamed_upgrade_resolves_its_3_6_name_at_epoch_73() -> void:
	SpellsRegistry.reset_cache()
	assert_int(AiActRecorder.rules_epoch).is_equal(73)
	var picks := [["gf", "robot_legions", "Mending Bots", "Enhanced Self-Repair"],
		["aof", "dragon_empire", "Jade Claws", "Enhanced Royal Warrior"]]
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
	assert_int(granted).override_failure_message("no spell grants a batch 3.6 name").is_equal(9)
