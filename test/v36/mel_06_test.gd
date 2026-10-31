extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-06: the melee grant forms resolve through the mechanics maps instead of
## printing "apply manually". Counter in Melee is the melee-scoped Counter primitive (rules 3.6 no
## longer cut Impact), Counter in Melee Aura is the Aura Channel that hands it to the unit, Counter
## in Melee Buff is the once-per-activation Utility Buff, Brace in Melee is the Brace primitive, and
## the Voidspace Stalkers' Thrust pair is the Thrust grant plus its Utility Buff. Godot's JSON reads
## every number as a float, so the expected params below are floats.

const COUNTER_PARAMS := {"strikes_first": true, "melee_only": true}
const COUNTER_AURA_PARAMS := {"grants": "Counter in Melee"}
const COUNTER_BUFF_PARAMS := {"grants_rule": "Counter in Melee", "range_in": 12.0, "target": "friendly",
	"max_targets": 1.0, "once": true}
const BRACE_PARAMS := {"rating": 1.0, "melee_only": true}
const THRUST_PARAMS := {"hit_bonus": 1.0, "ap_bonus": 1.0, "charge_only": true, "melee_only": true}
const THRUST_BUFF_PARAMS := {"grants_rule": "Thrust in Melee", "range_in": 12.0, "target": "friendly",
	"max_targets": 1.0, "once": true}

## [system, book, name, primitive, params] - the complete set of entries this row adds.
const ENTRIES := [
	["gf", "wolf_brothers", "Counter in Melee", "Counter", COUNTER_PARAMS],
	["gf", "wolf_brothers", "Counter in Melee Aura", "Aura Channel", COUNTER_AURA_PARAMS],
	["gf", "human_defense_force", "Counter in Melee Buff", "Utility Buff", COUNTER_BUFF_PARAMS],
	["gf", "voidspace_stalkers", "Thrust in Melee", "Thrust", THRUST_PARAMS],
	["gf", "voidspace_stalkers", "Thrust in Melee Buff", "Utility Buff", THRUST_BUFF_PARAMS],
	["aof", "orcs", "Counter in Melee", "Counter", COUNTER_PARAMS],
	["aof", "saurians", "Counter in Melee Aura", "Aura Channel", COUNTER_AURA_PARAMS],
	["aof", "orcs", "Brace in Melee", "Brace", BRACE_PARAMS],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "mel06_%s_%d" % [system, rules.size()]
	u.unit_properties = {"player_id": 2, "name": "Carrier", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _assert_entry(system: String, book: String, rule: String, primitive: String, params: Dictionary) -> void:
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))) \
		.override_failure_message("%s/%s does not resolve %s to %s: %s" % [system, book, rule, primitive, entry]) \
		.is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary) \
		.override_failure_message("%s/%s resolves %s with other knobs: %s" % [system, book, rule, entry]) \
		.is_equal(params)


func test_each_melee_grant_resolves_to_its_primitive() -> void:
	for c: Array in ENTRIES:
		_assert_entry(c[0], c[1], c[2], c[3], c[4])


func test_every_new_entry_is_a_3_6_0_unrated_entry() -> void:
	for c: Array in ENTRIES:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		assert_str(str(entry.get("book_version", ""))) \
			.override_failure_message("%s/%s: '%s' is not a 3.6.0 entry: %s" % [c[0], c[1], c[2], entry]) \
			.is_equal("3.6.0")
		assert_bool(bool(entry.get("rated", true))) \
			.override_failure_message("%s/%s: '%s' must be unrated" % [c[0], c[1], c[2]]) \
			.is_false()


## A 3.6 carrier of the book that prints the grant resolves it, and the primitive walk hands the
## same name back - the grant, not a stale manual note.
func test_a_carrier_gets_the_grant_back_off_its_primitive_walk() -> void:
	for c: Array in ENTRIES:
		var carrier := _unit([c[2]], c[0], c[1])
		assert_bool(RulesRegistry.unit_rule_active(carrier, c[2])) \
			.override_failure_message("%s/%s: a carrier of %s must be active" % [c[0], c[1], c[2]]) \
			.is_true()
		var names: Array = []
		for e in RulesRegistry.unit_rules_of_primitive(carrier, c[3]):
			names.append(str((e as Dictionary)["name"]))
		assert_bool(names.has(c[2])) \
			.override_failure_message("%s/%s: %s must come back off the %s walk" % [c[0], c[1], c[2], c[3]]) \
			.is_true()


## Control: the stale 3.5 name keeps its old entry (a later data row cleans it), and a carrier of
## the new name does not make the old one active.
func test_the_old_counter_attack_entry_is_left_alone() -> void:
	var entry := RulesRegistry.lookup("gf", "wolf_brothers", "Counter-Attack")
	assert_str(str(entry.get("primitive", ""))).is_equal("Counter")
	assert_dict(entry.get("params", {}) as Dictionary) \
		.is_equal({"strikes_first": true, "impact_reduction_per_model": 1.0})
	assert_bool(RulesRegistry.unit_rule_active(_unit(["Counter in Melee"], "gf", "wolf_brothers"), "Counter-Attack")) \
		.is_false()
