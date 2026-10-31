extends GdUnitTestSuite
## DAT-12b (0.3.15, rules 3.6): a rule whose name starts with "Enhanced " carries its effect with no
## distance gate, so no such entry may keep an `over_in` knob. The gate belongs to the older wording.
## The walk reads both rules 3.6 maps (gf and aof) through RulesRegistry, over the common section and
## every faction section; a per-system floor keeps an empty walk from passing. Two pinned cases name
## the books that print Enhanced Ferocious, and two non-Enhanced controls prove their gate stays.
## Godot's JSON reads every number as a float, so the pinned params below are floats.

const SYSTEMS := ["gf", "aof"]

## Minimum number of "Enhanced " entries per system today, so a broken walk fails instead of passing.
const MIN_ENHANCED := {"gf": 70, "aof": 67}

## [system, book, rule] - each book prints this Enhanced form today.
const PINNED := [
	["gf", "orc_marauders", "Enhanced Ferocious"],
	["aof", "orcs", "Enhanced Ferocious"],
]

## [system, book, rule] - non-Enhanced entries whose own gate must not be dropped.
const CONTROLS := [
	["gf", "common", "Stealth"],
	["aof", "common", "Stealth"],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


## Every [book, rule] pair of `system` whose rule name starts with "Enhanced ".
func _enhanced_entries(system: String) -> Array:
	var out: Array = []
	var m := RulesRegistry.map_for(system)
	for rule: String in m.get("common", {}):
		if rule.begins_with("Enhanced "):
			out.append([RulesRegistry.COMMON, rule])
	var factions: Dictionary = m.get("factions", {})
	for book: String in factions:
		for rule: String in factions[book]:
			if rule.begins_with("Enhanced "):
				out.append([book, rule])
	return out


func test_no_enhanced_form_resolves_with_a_distance_gate() -> void:
	for system: String in SYSTEMS:
		var seen := _enhanced_entries(system)
		assert_int(seen.size()).override_failure_message(
			"%s: only %d Enhanced entries found, the walk is broken" % [system, seen.size()]) \
			.is_greater_equal(int(MIN_ENHANCED[system]))
		for pair: Array in seen:
			var book: String = pair[0]
			var rule: String = pair[1]
			var entry := RulesRegistry.lookup(system, book, rule)
			var params: Dictionary = entry.get("params", {})
			assert_bool(params.has("over_in")).override_failure_message(
				"%s/%s: '%s' still carries over_in=%s" % [system, book, rule, params.get("over_in")]) \
				.is_false()


func test_pinned_enhanced_forms_keep_their_other_knobs() -> void:
	for c: Array in PINNED:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		var params: Dictionary = entry.get("params", {})
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"%s/%s: '%s' moved off Surge: %s" % [c[0], c[1], c[2], entry]).is_equal("Surge")
		assert_bool(params.has("over_in")).override_failure_message(
			"%s/%s: '%s' still carries over_in=%s" % [c[0], c[1], c[2], params.get("over_in")]) \
			.is_false()
		assert_float(float(params.get("surge_low", -1.0))).override_failure_message(
			"%s/%s: '%s' lost surge_low: %s" % [c[0], c[1], c[2], params]).is_equal_approx(5.0, 0.001)
		assert_str(str(params.get("upgrades", ""))).override_failure_message(
			"%s/%s: '%s' lost its upgrade link: %s" % [c[0], c[1], c[2], params]) \
			.is_equal("Ferocious")


func test_non_enhanced_forms_keep_their_distance_gate() -> void:
	for c: Array in CONTROLS:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		var params: Dictionary = entry.get("params", {})
		assert_bool(params.has("over_in")).override_failure_message(
			"%s/%s: control '%s' lost its over_in gate: %s" % [c[0], c[1], c[2], params]) \
			.is_true()
