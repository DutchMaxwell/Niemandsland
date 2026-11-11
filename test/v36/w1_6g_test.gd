extends GdUnitTestSuite
## W1.6g (0.3.15, rules 3.6): the three Brothers "Enhanced" base rules that no earlier rename row
## owned (Enhanced Bloodborn, Enhanced Darkborn, Enhanced Wolfborn). Each of the six Brothers books
## resolves its 3.6 name to the widened effect, while the base rule's own entry is unchanged. Every
## case reads the real gf map through RulesRegistry.

## [book, base rule, enhanced rule, enhanced primitive, enhanced params] - the numbers are written
## out here, not read back from the map. JSON numbers read back as floats.
const CASES := [
	["blood_brothers", "Bloodborn", "Enhanced Bloodborn", "Surge",
		{"upgrades": "Bloodborn", "extra_attack": true, "surge_low": 5.0}],
	["blood_prime_brothers", "Bloodborn", "Enhanced Bloodborn", "Surge",
		{"upgrades": "Bloodborn", "extra_attack": true, "surge_low": 5.0}],
	["dark_brothers", "Darkborn", "Enhanced Darkborn", "Ranged Shrouding",
		{"range_penalty_in": 8.0, "floor_in": 6.0, "melee_move_penalty_in": 4.0, "melee_floor_in": 6.0}],
	["dark_prime_brothers", "Darkborn", "Enhanced Darkborn", "Ranged Shrouding",
		{"range_penalty_in": 8.0, "floor_in": 6.0, "melee_move_penalty_in": 4.0, "melee_floor_in": 6.0}],
	["wolf_brothers", "Wolfborn", "Enhanced Wolfborn", "Bounding",
		{"place_d3_plus": 0.0, "dice_count": 2.0}],
	["wolf_prime_brothers", "Wolfborn", "Enhanced Wolfborn", "Bounding",
		{"place_d3_plus": 0.0, "dice_count": 2.0}],
]

## The base entry of each book as it stands on main: primitive and params must not move.
const BASES := [
	["blood_brothers", "Bloodborn", "Surge", {"extra_attack": true}],
	["blood_prime_brothers", "Bloodborn", "Surge", {"extra_attack": true}],
	["dark_brothers", "Darkborn", "Ranged Shrouding",
		{"range_penalty_in": 4.0, "floor_in": 6.0, "melee_move_penalty_in": 2.0, "melee_floor_in": 6.0}],
	["dark_prime_brothers", "Darkborn", "Ranged Shrouding",
		{"range_penalty_in": 4.0, "floor_in": 6.0, "melee_move_penalty_in": 2.0, "melee_floor_in": 6.0}],
	["wolf_brothers", "Wolfborn", "Bounding", {"place_d3_plus": 0.0}],
	["wolf_prime_brothers", "Wolfborn", "Bounding", {"place_d3_plus": 0.0}],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func test_each_brothers_book_resolves_its_enhanced_rule() -> void:
	for c: Array in CASES:
		var entry := RulesRegistry.lookup("gf", c[0], c[2])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"gf %s: '%s' does not resolve to %s" % [c[0], c[2], c[3]]).is_equal(c[3])
		assert_dict(entry.get("params", {})).override_failure_message(
			"gf %s: '%s' params are %s, expected %s" % [c[0], c[2], entry.get("params", {}), c[4]]).is_equal(c[4])
		assert_str(str(entry.get("book_version", ""))).override_failure_message(
			"gf %s: '%s' is not a 3.6.0 entry" % [c[0], c[2]]).is_equal("3.6.0")
		assert_bool(bool(entry.get("rated", true))).override_failure_message(
			"gf %s: '%s' must be unrated" % [c[0], c[2]]).is_false()


func test_each_base_rule_entry_is_unchanged() -> void:
	for c: Array in BASES:
		var entry := RulesRegistry.lookup("gf", c[0], c[1])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"gf %s: base '%s' moved to %s" % [c[0], c[1], entry.get("primitive")]).is_equal(c[2])
		assert_dict(entry.get("params", {})).override_failure_message(
			"gf %s: base '%s' params moved: %s" % [c[0], c[1], entry.get("params", {})]).is_equal(c[3])
