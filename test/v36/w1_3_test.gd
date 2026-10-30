extends GdUnitTestSuite
## Rules 3.6 wave, row W1.3: a named hero carries "Unique Hero" in place of a separate "Hero" rule, and
## "Unique Hero" is a Hero for every purpose (join, hero morale, solo sims, modeled lists). The core's twin
## in core/nml-core/src/tests/unit/v36_w1.rs pins the same hero cases on the profile stamp.

const MainScript := preload("res://scripts/main.gd")

## [rules, is a hero]. The control rows keep the exact-name reading: a rule that only CONTAINS the word
## is no hero.
const HERO_CASES := [
	[["Unique Hero"], true],
	[["Unique Hero", "Tough(3)"], true],
	[["Hero"], true],
	[["Fearless"], false],
	[["Hero Hunter Made-Up"], false],
]


## A unit of one living model carrying `rules`.
func _unit(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"special_rules": rules.duplicate(), "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func test_a_unique_hero_is_a_hero() -> void:
	for c in HERO_CASES:
		assert_bool(_unit(c[0]).is_hero()) \
			.override_failure_message("%s: want is_hero %s" % [c[0], c[1]]) \
			.is_equal(c[1])


## The solo targeting overlay ranks heroes through the same truth as the join.
func test_the_targeting_overlay_marks_a_unique_hero() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	for c in HERO_CASES:
		var desc: Dictionary = solo._overlay_descriptor({"unit": _unit(c[0]), "d": 3.0})
		assert_bool(bool(desc.get("is_hero", false))) \
			.override_failure_message("%s: want overlay is_hero %s" % [c[0], c[1]]) \
			.is_equal(c[1])


## The solo sim's own reader is a substring test, so it already counts the named hero; this pins it.
func test_the_solo_sim_counts_a_unique_hero() -> void:
	assert_bool(SoloSim._is_hero({"rules": ["Unique Hero"]})).is_true()
	assert_bool(SoloSim._is_hero({"rules": ["Hero"]})).is_true()
	assert_bool(SoloSim._is_hero({"rules": ["Fearless"]})).is_false()


## The rule inventory battle-log line names the rule by the name the unit carries: a Unique Hero is
## listed as run by the engine (and steering decisions), never under "apply by hand".
func test_the_inventory_line_names_a_unique_hero_as_run_by_the_engine() -> void:
	var inv := SoloController.classify_rule_inventory(["Unique Hero", "Hero"],
		MainScript.SOLO_MODELED_RULES, MainScript.SOLO_DECISION_RULES)
	assert_dict(inv["unknown"]).is_empty()
	assert_str(MainScript._solo_inventory_list(inv["resolved"])).is_equal("Hero x1, Unique Hero x1")
	assert_str(MainScript._solo_inventory_list(inv["decision"])).is_equal("Hero x1, Unique Hero x1")


## Like "Hero", the named hero's rule is always on and spawns no buff token, whatever its description says.
func test_a_unique_hero_spawns_no_buff_token() -> void:
	var desc := {"Unique Hero": "test-only words with a +1 in them", "Hero": "test-only words with a +1 in them"}
	assert_array(OPRArmyManager.buff_tokens_from_rules(["Unique Hero", "Hero"], desc)).is_empty()
