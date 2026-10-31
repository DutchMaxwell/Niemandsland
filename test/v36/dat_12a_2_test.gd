extends GdUnitTestSuite
## DAT-12a(2) (0.3.15, rules 3.6): the carried "Enhanced Knightborn Aura" form of the two Knight
## Brothers books. Each book prints the aura, and the aura hands out the "Enhanced Knightborn"
## rule that MOR-17 added. The gf map must resolve the name in the book that prints it, so
## "apply manually" disappears there.

const AURAS := [
	["knight_brothers", "Enhanced Knightborn Aura", "Enhanced Knightborn"],
	["knight_prime_brothers", "Enhanced Knightborn Aura", "Enhanced Knightborn"],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func test_each_knight_aura_grants_its_enhanced_rule() -> void:
	for c: Array in AURAS:
		var entry := RulesRegistry.lookup("gf", c[0], c[1])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"gf %s: '%s' does not resolve to Aura Channel: %s" % [c[0], c[1], entry]).is_equal("Aura Channel")
		assert_dict(entry.get("params", {})).override_failure_message(
			"gf %s: '%s' does not grant '%s': %s" % [c[0], c[1], c[2], entry]).is_equal({"grants": c[2]})


func test_every_knight_aura_is_a_3_6_0_unrated_entry() -> void:
	for c: Array in AURAS:
		var entry := RulesRegistry.lookup("gf", c[0], c[1])
		assert_str(str(entry.get("book_version", ""))).override_failure_message(
			"gf %s: '%s' is not a 3.6.0 entry: %s" % [c[0], c[1], entry]).is_equal("3.6.0")
		assert_bool(bool(entry.get("rated", true))).override_failure_message(
			"gf %s: '%s' must be unrated" % [c[0], c[1]]).is_false()
