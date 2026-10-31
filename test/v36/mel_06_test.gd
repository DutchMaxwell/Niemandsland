extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-06: the melee grant forms resolve through the mechanics maps instead of
## printing "apply manually". Counter in Melee is the melee-scoped Counter primitive (rules 3.6 no
## longer cut Impact), Counter in Melee Aura is the Aura Channel that hands it to the unit, Counter
## in Melee Buff is the once-per-activation Utility Buff, Brace in Melee is the Brace primitive, and
## the Voidspace Stalkers' Thrust pair is the Thrust grant plus its Utility Buff. Godot's JSON reads
## every number as a float, so the expected params are floats.

const COUNTER_PARAMS := {"strikes_first": true, "melee_only": true}
const COUNTER_AURA_PARAMS := {"grants": "Counter in Melee"}
const COUNTER_BUFF_PARAMS := {"grants_rule": "Counter in Melee", "max_targets": 1.0, "once": true, "range_in": 12.0, "target": "friendly"}
const BRACE_PARAMS := {"rating": 1.0, "melee_only": true}
const THRUST_PARAMS := {"hit_bonus": 1.0, "ap_bonus": 1.0, "charge_only": true, "melee_only": true}
const THRUST_BUFF_PARAMS := {"grants_rule": "Thrust in Melee", "max_targets": 1.0, "once": true, "range_in": 12.0, "target": "friendly"}


func before_test() -> void:
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


## A 3.6 carrier of `book` whose rule list holds `rule` resolves that name to `primitive` with the
## expected params, and the primitive walk sees the same grant on the unit.
func _assert_grant(system: String, book: String, rule: String, primitive: String, params: Dictionary) -> void:
	assert_bool(RulesRegistry.has_primitive(system, book, rule)) \
		.override_failure_message("%s / %s: %s must resolve to a primitive, not 'apply manually'" % [system, book, rule]) \
		.is_true()
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))).is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary).is_equal(params)
	var carrier := _unit([rule], system, book)
	assert_bool(RulesRegistry.unit_rule_active(carrier, rule)) \
		.override_failure_message("%s / %s: a carrier of %s must be active" % [system, book, rule]) \
		.is_true()
	var names: Array = []
	for e in RulesRegistry.unit_rules_of_primitive(carrier, primitive):
		names.append(str((e as Dictionary)["name"]))
	assert_bool(names.has(rule)) \
		.override_failure_message("%s / %s: %s must come back off the %s walk" % [system, book, rule, primitive]) \
		.is_true()


func test_counter_in_melee_is_the_melee_scoped_counter_primitive() -> void:
	_assert_grant("gf", "wolf_brothers", "Counter in Melee", "Counter", COUNTER_PARAMS)
	_assert_grant("aof", "orcs", "Counter in Melee", "Counter", COUNTER_PARAMS)


func test_counter_in_melee_aura_grants_counter_in_melee_to_the_unit() -> void:
	_assert_grant("gf", "wolf_brothers", "Counter in Melee Aura", "Aura Channel", COUNTER_AURA_PARAMS)
	_assert_grant("aof", "saurians", "Counter in Melee Aura", "Aura Channel", COUNTER_AURA_PARAMS)


func test_counter_in_melee_buff_is_the_once_per_activation_utility_buff() -> void:
	_assert_grant("gf", "human_defense_force", "Counter in Melee Buff", "Utility Buff", COUNTER_BUFF_PARAMS)


func test_brace_in_melee_is_the_brace_primitive() -> void:
	_assert_grant("aof", "orcs", "Brace in Melee", "Brace", BRACE_PARAMS)


func test_the_voidspace_stalkers_thrust_pair_resolves() -> void:
	_assert_grant("gf", "voidspace_stalkers", "Thrust in Melee", "Thrust", THRUST_PARAMS)
	_assert_grant("gf", "voidspace_stalkers", "Thrust in Melee Buff", "Utility Buff", THRUST_BUFF_PARAMS)


## Control: the stale 3.5 name keeps its old entry (a later data row cleans it), and a rule the
## carrier does not have stays inactive.
func test_the_old_counter_attack_entry_is_left_alone() -> void:
	assert_str(str(RulesRegistry.lookup("gf", "wolf_brothers", "Counter-Attack").get("primitive", ""))) \
		.is_equal("Counter")
	assert_bool(RulesRegistry.unit_rule_active(_unit(["Counter in Melee"], "gf", "wolf_brothers"), "Counter-Attack")) \
		.is_false()
