extends GdUnitTestSuite
## SHO-12 (0.3.15, rules 3.6): the five new weapon rules carry a namesake entry in every book that
## prints them, so the table stops saying "apply manually" for those units. Each entry is the 3.6
## shape: one Bane save re-roll window (6s, widened 5-6 where the book says so) with the target
## condition that opens it, or, for Demolish, ignores Cover plus AP(+1) against a target by terrain.
## Godot reads every JSON number as a float, so the expected numbers below are floats.

## [system, book, rule, primitive, params] - the entries this row adds (SHO-12).
const ENTRIES := [
	["gf", "battle_brothers", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["gf", "watch_brothers", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["gf", "knight_brothers", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["gf", "blood_brothers", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["gf", "dark_brothers", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["gf", "wolf_brothers", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["aof", "eternal_wardens", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["aof", "wood_elves", "Smash", "Bane", {"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false}],
	["gf", "titan_lords_plague_disciples", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["gf", "infected_colonies", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["gf", "daemons_of_plague", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["gf", "plague_disciples", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["aof", "halflings", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["aof", "giant_tribes_plague_disciples", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["aof", "plague_disciples", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["aof", "daemons_of_plague", "Decimate", "Bane", {"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false}],
	["gf", "alien_hives", "Fragment", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "def_5_6", "bypass_regen": false}],
	["aof", "ogres", "Fragment", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "def_5_6", "bypass_regen": false}],
	["aof", "vampiric_undead", "Fragment", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "def_5_6", "bypass_regen": false}],
	["gf", "daemons_of_lust", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["gf", "titan_lords_lust_disciples", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["gf", "lust_disciples", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["aof", "daemons_of_lust", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["aof", "chivalrous_kingdoms", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["aof", "giant_tribes_lust_disciples", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["aof", "lust_disciples", "Obliterate", "Bane", {"reroll_save_sixes": true, "reroll_save_low": 5.0, "condition": "vs_tough_ge", "threshold": 3.0, "bypass_regen": true}],
	["gf", "machine_cults", "Demolish", "Indirect", {"ignores_cover": true, "cover_only": true, "ap_bonus": 1.0, "condition": "near_terrain"}],
	["gf", "voidspace_stalkers", "Demolish", "Indirect", {"ignores_cover": true, "cover_only": true, "ap_bonus": 1.0, "condition": "near_terrain"}],
	["aof", "volcanic_dwarves", "Demolish", "Indirect", {"ignores_cover": true, "cover_only": true, "ap_bonus": 1.0, "condition": "near_terrain"}],
	["aof", "dragon_empire", "Demolish", "Indirect", {"ignores_cover": true, "cover_only": true, "ap_bonus": 1.0, "condition": "near_terrain"}],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func test_every_carrier_book_resolves_its_rule() -> void:
	for row: Array in ENTRIES:
		var system := str(row[0])
		var book := str(row[1])
		var rule := str(row[2])
		var primitive := str(row[3])
		var params := row[4] as Dictionary
		var entry := RulesRegistry.lookup(system, book, rule)
		assert_bool(RulesRegistry.has_primitive(system, book, rule)) \
			.override_failure_message("%s/%s does not resolve %s: %s" % [system, book, rule, entry]) \
			.is_true()
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s/%s resolves %s to the wrong primitive: %s" % [system, book, rule, entry]) \
			.is_equal(primitive)
		assert_dict(entry.get("params", {}) as Dictionary) \
			.override_failure_message("%s/%s resolves %s with other knobs: %s" % [system, book, rule, entry]) \
			.is_equal(params)
		assert_str(str(entry.get("book_version", ""))).is_equal("3.6.0")


func test_a_book_that_does_not_print_the_rule_does_not_resolve_it() -> void:
	# None of the five is a common mechanic: a book outside the carrier list stays unresolved.
	for c: Array in [["gf", "battle_brothers", "Demolish"], ["aof", "wood_elves", "Demolish"],
			["gf", "alien_hives", "Smash"], ["aof", "ogres", "Obliterate"]]:
		assert_bool(RulesRegistry.has_primitive(str(c[0]), str(c[1]), str(c[2]))) \
			.override_failure_message("%s/%s must not resolve %s" % [c[0], c[1], c[2]]) \
			.is_false()
