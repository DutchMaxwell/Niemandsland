extends GdUnitTestSuite
## Rules 3.6 row DAT-02: nine army books changed their name in 3.6 (the daemon books lost their
## "Wormhole" / "Rift" prefix, the GF saurian book gained a plural "s"). An imported 3.6 book
## stamps its units with the folder derived from the NEW book name, and that folder is the second
## half of every rules/spells registry key. Until the map sections carry the new keys, such a unit
## finds none of its faction rules and no spell book: it silently plays with the common rules only.

const RENAMED := [
	["gf", "wormhole_daemons_of_change", "daemons_of_change"],
	["gf", "wormhole_daemons_of_lust", "daemons_of_lust"],
	["gf", "wormhole_daemons_of_plague", "daemons_of_plague"],
	["gf", "wormhole_daemons_of_war", "daemons_of_war"],
	["gf", "saurian_starhost", "saurian_starhosts"],
	["aof", "rift_daemons_of_change", "daemons_of_change"],
	["aof", "rift_daemons_of_lust", "daemons_of_lust"],
	["aof", "rift_daemons_of_plague", "daemons_of_plague"],
	["aof", "rift_daemons_of_war", "daemons_of_war"],
]


func before_test() -> void:
	RulesRegistry.reset_cache()
	SpellsRegistry.reset_cache()


func _unit(system: String, folder: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "dat02_%s_%s" % [system, folder]
	u.unit_properties = {"player_id": 1, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": folder}
	return u


func test_a_3_6_daemons_of_change_unit_finds_its_faction_rule() -> void:
	# "Changebound" lives only in the faction section, never in common: an empty answer means the
	# unit fell through to the common rules.
	for system in ["gf", "aof"]:
		var u := _unit(system, "daemons_of_change", ["Changebound"])
		var entry := RulesRegistry.lookup(RulesRegistry.system_of_unit(u),
			RulesRegistry.faction_of_unit(u), "Changebound")
		assert_bool(entry.is_empty()) \
			.override_failure_message("%s daemons_of_change: Changebound fell to common" % system) \
			.is_false()
		assert_bool(RulesRegistry.has_primitive(system, "daemons_of_change", "Changebound")) \
			.override_failure_message("%s daemons_of_change: Changebound is not automated" % system) \
			.is_true()


func test_a_3_6_daemons_of_change_caster_finds_its_spell_book() -> void:
	for system in ["gf", "aof"]:
		var u := _unit(system, "daemons_of_change", ["Caster(2)"])
		assert_bool(SpellsRegistry.spells_for_unit(u).is_empty()) \
			.override_failure_message("%s daemons_of_change: no spell book" % system).is_false()
		assert_bool(SpellsRegistry.entry_for(system, "daemons_of_change", "Shifting Form").is_empty()) \
			.override_failure_message("%s daemons_of_change: Shifting Form missing" % system).is_false()


func test_every_renamed_section_answers_only_under_its_3_6_key() -> void:
	# Hard switch: the old key is gone, so a 3.5 folder no longer resolves (accepted for 0.3.15).
	for row in RENAMED:
		var system: String = row[0]
		var old_key: String = row[1]
		var new_key: String = row[2]
		var rule_factions: Dictionary = RulesRegistry.map_for(system).get("factions", {})
		var spell_factions: Dictionary = SpellsRegistry.map_for(system).get("factions", {})
		assert_bool(rule_factions.has(new_key)) \
			.override_failure_message("%s rules map lacks section %s" % [system, new_key]).is_true()
		assert_bool(spell_factions.has(new_key)) \
			.override_failure_message("%s spells map lacks section %s" % [system, new_key]).is_true()
		assert_bool(rule_factions.has(old_key)) \
			.override_failure_message("%s rules map still keys %s" % [system, old_key]).is_false()
		assert_bool(spell_factions.has(old_key)) \
			.override_failure_message("%s spells map still keys %s" % [system, old_key]).is_false()


func test_control_aof_saurians_keeps_its_key_and_rules() -> void:
	# The AoF saurian book kept its name in 3.6, so its section must stay where it is.
	var u := _unit("aof", "saurians", ["Primal"])
	assert_bool(RulesRegistry.lookup("aof", RulesRegistry.faction_of_unit(u), "Primal").is_empty()) \
		.override_failure_message("aof saurians: Primal fell to common").is_false()
	assert_bool(SpellsRegistry.spells_for_unit(u).is_empty()) \
		.override_failure_message("aof saurians: no spell book").is_false()
