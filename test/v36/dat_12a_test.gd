extends GdUnitTestSuite
## DAT-12a (0.3.15, rules 3.6): the carried forms of the Enhanced "-born" family for the six Brothers
## books and the Voidspace Stalkers. Each book prints an "Enhanced <X> Aura" that hands out its
## "Enhanced <X>" rule, and the Voidspace Stalkers also print "Enhanced Shadowborn" and its Buff
## form. The gf map must resolve all nine names in the book that prints them, so "apply manually"
## disappears there. The base "Shadowborn" entry must not move. Godot's JSON reads every number as a
## float, so the expected params below are floats.

## [book, aura name, rule the aura grants] - every carried form here resolves to Aura Channel.
const AURAS := [
	["blood_brothers", "Enhanced Bloodborn Aura", "Enhanced Bloodborn"],
	["blood_prime_brothers", "Enhanced Bloodborn Aura", "Enhanced Bloodborn"],
	["dark_brothers", "Enhanced Darkborn Aura", "Enhanced Darkborn"],
	["dark_prime_brothers", "Enhanced Darkborn Aura", "Enhanced Darkborn"],
	["wolf_brothers", "Enhanced Wolfborn Aura", "Enhanced Wolfborn"],
	["wolf_prime_brothers", "Enhanced Wolfborn Aura", "Enhanced Wolfborn"],
	["voidspace_stalkers", "Enhanced Shadowborn Aura", "Enhanced Shadowborn"],
]

## [book, name, primitive, params] - the complete set of nine entries this row adds.
const ENTRIES := [
	["blood_brothers", "Enhanced Bloodborn Aura", "Aura Channel", {"grants": "Enhanced Bloodborn"}],
	["blood_prime_brothers", "Enhanced Bloodborn Aura", "Aura Channel", {"grants": "Enhanced Bloodborn"}],
	["dark_brothers", "Enhanced Darkborn Aura", "Aura Channel", {"grants": "Enhanced Darkborn"}],
	["dark_prime_brothers", "Enhanced Darkborn Aura", "Aura Channel", {"grants": "Enhanced Darkborn"}],
	["wolf_brothers", "Enhanced Wolfborn Aura", "Aura Channel", {"grants": "Enhanced Wolfborn"}],
	["wolf_prime_brothers", "Enhanced Wolfborn Aura", "Aura Channel", {"grants": "Enhanced Wolfborn"}],
	["voidspace_stalkers", "Enhanced Shadowborn", "Ranged Shrouding",
		{"range_penalty_in": 8.0, "floor_in": 6.0, "melee_move_penalty_in": 4.0, "melee_floor_in": 6.0}],
	["voidspace_stalkers", "Enhanced Shadowborn Aura", "Aura Channel", {"grants": "Enhanced Shadowborn"}],
	["voidspace_stalkers", "Enhanced Shadowborn Buff", "Utility Buff",
		{"grants_rule": "Enhanced Shadowborn", "range_in": 12.0, "target": "friendly",
		"max_targets": 1.0, "once": true}],
]

const SHADOWBORN_PARAMS := {"range_penalty_in": 4.0, "floor_in": 6.0, "melee_move_penalty_in": 2.0,
	"melee_floor_in": 6.0}


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _assert_entry(book: String, rule: String, primitive: String, params: Dictionary) -> void:
	var entry := RulesRegistry.lookup("gf", book, rule)
	assert_str(str(entry.get("primitive", ""))) \
		.override_failure_message("gf/%s does not resolve %s to %s: %s" % [book, rule, primitive, entry]) \
		.is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary) \
		.override_failure_message("gf/%s resolves %s with other knobs: %s" % [book, rule, entry]) \
		.is_equal(params)


func test_each_carried_aura_grants_its_enhanced_rule() -> void:
	for c: Array in AURAS:
		var entry := RulesRegistry.lookup("gf", c[0], c[1])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"gf %s: '%s' does not resolve to Aura Channel: %s" % [c[0], c[1], entry]).is_equal("Aura Channel")
		assert_dict(entry.get("params", {})).override_failure_message(
			"gf %s: '%s' does not grant '%s': %s" % [c[0], c[1], c[2], entry]).is_equal({"grants": c[2]})


func test_voidspace_enhanced_shadowborn_widens_the_ranged_shrouding() -> void:
	_assert_entry("voidspace_stalkers", "Enhanced Shadowborn", "Ranged Shrouding",
		{"range_penalty_in": 8.0, "floor_in": 6.0, "melee_move_penalty_in": 4.0, "melee_floor_in": 6.0})


func test_voidspace_enhanced_shadowborn_buff_grants_the_rule() -> void:
	_assert_entry("voidspace_stalkers", "Enhanced Shadowborn Buff", "Utility Buff",
		{"grants_rule": "Enhanced Shadowborn", "range_in": 12.0, "target": "friendly",
		"max_targets": 1.0, "once": true})


func test_every_new_entry_is_a_3_6_0_unrated_entry() -> void:
	for c: Array in ENTRIES:
		var entry := RulesRegistry.lookup("gf", c[0], c[1])
		assert_str(str(entry.get("book_version", ""))).override_failure_message(
			"gf %s: '%s' is not a 3.6.0 entry: %s" % [c[0], c[1], entry]).is_equal("3.6.0")
		assert_bool(bool(entry.get("rated", true))).override_failure_message(
			"gf %s: '%s' must be unrated" % [c[0], c[1]]).is_false()


func test_the_base_voidspace_shadowborn_is_unchanged() -> void:
	var entry := RulesRegistry.lookup("gf", "voidspace_stalkers", "Shadowborn")
	assert_str(str(entry.get("primitive", ""))).override_failure_message(
		"gf voidspace_stalkers: base 'Shadowborn' moved to %s" % entry.get("primitive")).is_equal("Ranged Shrouding")
	assert_dict(entry.get("params", {})).override_failure_message(
		"gf voidspace_stalkers: base 'Shadowborn' params moved: %s" % entry).is_equal(SHADOWBORN_PARAMS)
