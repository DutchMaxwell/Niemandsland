extends GdUnitTestSuite
## DAT-12b-fix (0.3.15, rules 3.6): a rule whose name starts with "Enhanced " carries its effect
## with no distance gate, spelled `over_in: 0`. No such entry may keep a positive gate; the older
## wording's distance belongs to the base rule.
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
			assert_float(float(params.get("over_in", 0.0))).override_failure_message(
				"%s/%s: '%s' carries a distance gate over_in=%s" % [system, book, rule, params.get("over_in")]) \
				.is_equal_approx(0.0, 0.001)


func test_pinned_enhanced_forms_keep_their_other_knobs() -> void:
	for c: Array in PINNED:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		var params: Dictionary = entry.get("params", {})
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"%s/%s: '%s' moved off Surge: %s" % [c[0], c[1], c[2], entry]).is_equal("Surge")
		assert_float(float(params.get("over_in", -1.0))).override_failure_message(
			"%s/%s: '%s' lost the explicit no-distance spelling: %s" % [c[0], c[1], c[2], params]) \
			.is_equal_approx(0.0, 0.001)
		assert_float(float(params.get("surge_low", 6.0))).override_failure_message(
			"%s/%s: '%s' lost the base 6s window: %s" % [c[0], c[1], c[2], params]).is_equal_approx(6.0, 0.001)
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


## A live carrier of the base rule plus its Enhanced form, in the book that prints both.
func _enhanced_ferocious_unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "enh_fer"
	u.unit_properties = {"player_id": 2, "name": "E", "quality": 4, "defense": 4,
		"special_rules": ["Ferocious", "Enhanced Ferocious"],
		"game_system": "gf", "faction_folder": "orc_marauders"}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## The LIVE AiEv stamp (not a hand-built dictionary) at `epoch`; restores the static clock first,
## so a failing assert cannot leak the epoch into the next case.
func _stamped_surge(epoch: int) -> Dictionary:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	var p := {"name": "Rifle", "attacks": 8, "ap": 0, "range": 24, "rules": []}
	AiEv.stamp_sergeant([p], _enhanced_ferocious_unit())
	AiActRecorder.rules_epoch = epoch0
	return p


func test_enhanced_ferocious_stamps_the_base_window_at_epoch_73() -> void:
	var p := _stamped_surge(AiActRecorder.EPOCH_73_V36)
	assert_bool(bool(p.get("surge", false))).override_failure_message(
		"the base Ferocious never reached the stamp").is_true()
	assert_int(int(p.get("surge_low", 0))).override_failure_message(
		"the Enhanced form keeps the base Ferocious 6s window, not the Boost's 5").is_equal(6)
	assert_float(float(p.get("surge_over_in", 9.0))).override_failure_message(
		"an explicit over_in 0 means no distance condition").is_equal_approx(-1.0, 0.001)


func test_enhanced_ferocious_keeps_the_boost_window_at_epoch_72() -> void:
	var p := _stamped_surge(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_int(int(p.get("surge_low", 0))).override_failure_message(
		"epoch 72 keeps the 3.5 Boost 5s window").is_equal(5)
	assert_float(float(p.get("surge_over_in", 0.0))).override_failure_message(
		"epoch 72 keeps the old 9-inch default").is_equal_approx(9.0, 0.001)
