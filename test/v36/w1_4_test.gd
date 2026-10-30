extends GdUnitTestSuite
## Rules 3.6 wave, row W1.4: the shared "most models" reader (ruling D-MOST). A rule is on when a strict
## majority of the unit's LIVING models carry it; a joined hero counts as one model however Tough, and an
## exact half is off. The core's twin in core/nml-core/src/tests/unit/v36_w1.rs runs the same case table.
## The reader is looked up by name, so a build without it fails on the assertion, not on parsing.

const PLAIN_HERO := [["Hero"], true]
const FEARLESS_HERO := [["Hero", "Fearless"], true]

const MOST_CASES := [
	{"name": "three host models with it, two joined heroes without: 3 of 5, on", "host_rules": ["Fearless"], "host_models": 3, "host_dead": 0, "heroes": [PLAIN_HERO, PLAIN_HERO], "solo": false, "want": true},
	{"name": "one host model with it, one joined hero without: an exact half, off", "host_rules": ["Fearless"], "host_models": 1, "host_dead": 0, "heroes": [PLAIN_HERO], "solo": false, "want": false},
	{"name": "one host model without it, a joined hero with it: 1 of 2, off", "host_rules": [], "host_models": 1, "host_dead": 0, "heroes": [FEARLESS_HERO], "solo": false, "want": false},
	{"name": "two host models without it, a joined hero with it: 1 of 3, off", "host_rules": [], "host_models": 2, "host_dead": 0, "heroes": [FEARLESS_HERO], "solo": false, "want": false},
	{"name": "a Tough(6) joined hero without it is one model, not six wounds: 2 of 3, on", "host_rules": ["Fearless"], "host_models": 2, "host_dead": 0, "heroes": [[["Hero", "Tough(6)"], true]], "solo": false, "want": true},
	{"name": "a Tough(6) joined hero with it is one model, not six wounds: 1 of 3, off", "host_rules": [], "host_models": 2, "host_dead": 0, "heroes": [[["Hero", "Fearless", "Tough(6)"], true]], "solo": false, "want": false},
	{"name": "a Tough(3) host model with it is one model, not three wounds: 1 of 3, off", "host_rules": ["Fearless", "Tough(3)"], "host_models": 1, "host_dead": 0, "heroes": [PLAIN_HERO, PLAIN_HERO], "solo": false, "want": false},
	{"name": "a lone hero keeps its own rule", "host_rules": ["Hero", "Fearless"], "host_models": 1, "host_dead": 0, "heroes": [], "solo": false, "want": true},
	{"name": "a lone hero without the rule stays off", "host_rules": ["Hero"], "host_models": 1, "host_dead": 0, "heroes": [], "solo": false, "want": false},
	{"name": "dead host models without it do not count: 2 of 3 living, on", "host_rules": [], "host_models": 3, "host_dead": 2, "heroes": [FEARLESS_HERO, FEARLESS_HERO], "solo": false, "want": true},
	{"name": "dead host models with it do not count: 1 of 3 living, off", "host_rules": ["Fearless"], "host_models": 3, "host_dead": 2, "heroes": [PLAIN_HERO, PLAIN_HERO], "solo": false, "want": false},
	{"name": "a fallen joined hero without it does not count: 1 of 1, on", "host_rules": ["Fearless"], "host_models": 1, "host_dead": 0, "heroes": [[["Hero"], false]], "solo": false, "want": true},
	{"name": "a wiped-out unit has no majority", "host_rules": ["Fearless"], "host_models": 2, "host_dead": 2, "heroes": [], "solo": false, "want": false},
	{"name": "solo: the picked host model answers from its own unit, on", "host_rules": ["Fearless"], "host_models": 1, "host_dead": 0, "heroes": [PLAIN_HERO, PLAIN_HERO], "solo": true, "want": true},
	{"name": "solo: the collapse never borrows the heroes' rule, off", "host_rules": [], "host_models": 1, "host_dead": 0, "heroes": [FEARLESS_HERO, FEARLESS_HERO], "solo": true, "want": false},
	{"name": "solo: a host with no living model is off", "host_rules": ["Fearless"], "host_models": 1, "host_dead": 1, "heroes": [], "solo": true, "want": false},
]


## A unit of `models` models carrying `rules`, the first `dead` of them fallen.
func _unit(rules: Array, models: int, dead: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"special_rules": rules.duplicate()}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = i >= dead
		u.models.append(m)
	return u


func _host_of(c: Dictionary) -> GameUnit:
	var host := _unit(c["host_rules"], int(c["host_models"]), int(c["host_dead"]))
	var heroes: Array = []
	for h in c["heroes"]:
		heroes.append(_unit(h[0], 1, 0 if h[1] else 1))
	host.unit_properties["attached_heroes"] = heroes
	return host


## AiEv's static `method` called by name; null when this build has no such method.
func _ev(method: String, args: Array) -> Variant:
	var ev := AiEv.new()
	if not ev.has_method(method):
		return null
	return ev.callv(method, args)


func test_rule_on_most_models_answers_the_shared_case_table() -> void:
	for c in MOST_CASES:
		var got: Variant = _ev("rule_on_most_models", [_host_of(c), "Fearless", c["solo"]])
		assert_bool(got is bool and got == c["want"]) \
			.override_failure_message("%s: want %s, got %s" % [c["name"], c["want"], got]) \
			.is_true()


## The one majority test the morale rows count live state with: strictly more than half.
func test_most_models_of_needs_a_strict_majority() -> void:
	for row in [[1, 2, false], [2, 3, true], [0, 0, false], [1, 1, true], [2, 5, false]]:
		var got: Variant = _ev("most_models_of", [row[0], row[1]])
		assert_bool(got is bool and got == row[2]) \
			.override_failure_message("%d of %d: want %s, got %s" % [row[0], row[1], row[2], got]) \
			.is_true()
