extends GdUnitTestSuite
## Rules 3.6 row MOR-16a (core half): the six carrier factions carry the
## "Spell Drain" Utility Buff entry (18", enemy, once, line of sight, 2
## tokens on a failed Morale test), and the spell-token store never drops
## below zero. The engine/table half is MOR-16b.

const CARRIERS := [
	["gf", "blessed_sisters"],
	["gf", "daemons_of_change"],
	["gf", "human_inquisition"],
	["aof", "beastmen"],
	["aof", "daemons_of_change"],
	["aof", "sky_city_dwarves"],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


## Every carrier folder resolves the new entry from its own map section.
func test_the_six_carrier_factions_parse_the_spell_drain_entry() -> void:
	for c in CARRIERS:
		var got := RulesRegistry.lookup(str(c[0]), str(c[1]), "Spell Drain")
		var where := "%s/%s" % [c[0], c[1]]
		assert_str(str(got.get("primitive", ""))).override_failure_message(where) \
			.is_equal("Utility Buff")
		var params: Dictionary = got.get("params", {})
		assert_int(int(params.get("range_in", 0))).override_failure_message(where).is_equal(18)
		assert_str(str(params.get("target", ""))).override_failure_message(where).is_equal("enemy")
		assert_bool(bool(params.get("once", false))).override_failure_message(where).is_true()
		assert_bool(bool(params.get("needs_los", false))).override_failure_message(where).is_true()
		assert_int(int(params.get("spell_token_drain", 0))).override_failure_message(where) \
			.is_equal(2)


## The token store is an integer that floors at zero, never a negative count.
func test_the_spell_token_store_floors_at_zero() -> void:
	var u := GameUnit.new()
	u.set_caster_points(3)
	assert_int(u.casts_current).is_equal(3)
	u.set_caster_points(-2)
	assert_int(u.casts_current).override_failure_message(
		"the spell-token store never goes below zero").is_equal(0)
