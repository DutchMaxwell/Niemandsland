extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-11: four faction aliases of the Reinforced family lose their distance
## condition. Guardian (custodian_brothers), Primeborn (prime_brothers), Warden (eternal_wardens)
## and Ossified (ossified_undead) are plain Fortified entries in 3.6, so they reduce incoming AP
## against every hit instead of only against attacks from over 9" away. The core already reads an
## entry without "over_in" as an ungated entry, so only the map data changes.
## Godot's JSON reads every number as a float.

const UNGATED_ALIASES := [
	["gf", "custodian_brothers", "Guardian"],
	["gf", "prime_brothers", "Primeborn"],
	["aof", "eternal_wardens", "Warden"],
	["aof", "ossified_undead", "Ossified"],
]

const GATED_CONTROLS := [
	["gf", "custodian_brothers", "Reinforced"],
	["gf", "prime_brothers", "Reinforced"],
	["aof", "eternal_wardens", "Reinforced"],
	["aof", "ossified_undead", "Reinforced"],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func test_the_four_aliases_carry_no_distance_gate() -> void:
	for row in UNGATED_ALIASES:
		var system: String = row[0]
		var section: String = row[1]
		var name: String = row[2]
		var where := "%s/%s/%s" % [system, section, name]
		var entry := RulesRegistry.lookup(system, section, name)
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s: must resolve to the Fortified primitive" % where) \
			.is_equal("Fortified")
		var params: Dictionary = entry.get("params", {})
		assert_bool((params.get("incoming_ap_reduction", 0) is int
				or params.get("incoming_ap_reduction", 0) is float)
			and int(params.get("incoming_ap_reduction", 0)) == 1) \
			.override_failure_message("%s: AP reduction must stay 1" % where).is_true()
		var has_gate := params.has("over_in")
		var gate_positive := has_gate and float(params["over_in"]) > 0.0
		assert_bool(gate_positive) \
			.override_failure_message("%s: must not carry a positive 'over_in' distance gate" % where) \
			.is_false()


func test_control_reinforced_keeps_its_gate() -> void:
	for row in GATED_CONTROLS:
		var system: String = row[0]
		var section: String = row[1]
		var name: String = row[2]
		var where := "%s/%s/%s" % [system, section, name]
		var entry := RulesRegistry.lookup(system, section, name)
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s: must keep the Fortified primitive" % where) \
			.is_equal("Fortified")
		var params: Dictionary = entry.get("params", {})
		assert_bool(params.has("over_in")) \
			.override_failure_message("%s: the Reinforced control keeps its 'over_in' gate" % where) \
			.is_true()
		assert_int(int(params.get("over_in", 0))) \
			.override_failure_message("%s: the Reinforced control keeps over_in 9" % where) \
			.is_equal(9)
