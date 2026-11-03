extends GdUnitTestSuite
## Rules 3.6 row MOR-16c: the CORE Spell Drain now rolls the real tray Morale
## test and leaves the target Shaken. The GD half is already merged and this
## PR must not reopen it; the table-side Shaken fix is the separate PR #2303.
## This suite only guards the table-side data contract the core reads.

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


## The core drains two tokens on a failed test, once per activation, at 18"
## against an enemy in line of sight. The GD data must keep saying exactly
## that or the core and the table drift apart.
func test_the_spell_drain_table_contract_is_unchanged() -> void:
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
