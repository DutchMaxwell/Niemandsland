extends GdUnitTestSuite
## Rules 3.6 row SHO-13: the new Precise-family spellings and Reap had no mechanics entry, so a
## 3.6 book that prints them resolved to "apply manually". The maps now carry one entry per book
## section that prints each name, with the primitive and knobs the 3.6 text states. Godot's JSON
## reads every number as a float, so the expected params below are floats.
##
## Precision Charge / Precision Fighter (the model-only bases) stay UNMAPPED: their 3.5 "Aura"
## entries already carry the effect, and import expansion grants the base to every aura carrier, so
## mapping the base would add +2 to the same model. Moving that effect needs an epoch gate in the
## Shot Modifier seam, which is outside this data row.

const IMPRECISE := {"hit_bonus": -1.0}
const INFILTRATING := {"grants": "Infiltrate", "min_enemy_dist_in": 3.0,
	"melee_hit_bonus": 1.0, "arrival_round_only": true}
const PREDATOR_AURA := {"grants": "Predator"}
const REAP := {"reroll_save_sixes": true, "reroll_save_low": 5.0,
	"condition": "shaken_or_fatigued", "upgrades": "Reap", "over_in": 0.0, "bypass_regen": false}

## [system, book, name, primitive, params] - the complete set of entries this row adds.
const ENTRIES := [
	["gf", "alien_hives", "Imprecise", "Shot Modifier", IMPRECISE],
	["gf", "alien_hives", "Predator Aura", "Aura Channel", PREDATOR_AURA],
	["gf", "elven_jesters", "Infiltrating Precision Strike", "Infiltrate", INFILTRATING],
	["gf", "eternal_dynasty", "Imprecise", "Shot Modifier", IMPRECISE],
	["gf", "goblin_reclaimers", "Imprecise", "Shot Modifier", IMPRECISE],
	["gf", "rebel_guerrillas", "Reap", "Bane", REAP],
	["gf", "robot_legions", "Imprecise", "Shot Modifier", IMPRECISE],
	["gf", "soul_snatcher_cults", "Reap", "Bane", REAP],
	["aof", "deep_sea_elves", "Reap", "Bane", REAP],
	["aof", "ghostly_undead", "Reap", "Bane", REAP],
	["aof", "shadow_stalkers", "Imprecise", "Shot Modifier", IMPRECISE],
]

## [system, book, name, primitive, params, book_version] - 3.5 entries this row must leave alone.
const CONTROLS := [
	["gf", "orc_marauders", "Precision Charge Aura", "Shot Modifier",
		{"hit_bonus": 1.0, "when": "charge"}, "3.5.3"],
	["gf", "alien_hives", "Predator Fighter", "Surge",
		{"extra_attack": true, "melee_only": true}, "3.5.3"],
	["aof", "dwarves", "Precision Charge Aura", "Shot Modifier",
		{"hit_bonus": 1.0, "when": "charge"}, "3.5.3"],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "sho13_%s_%d" % [system, rules.size()]
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


func test_each_new_name_resolves_in_the_book_that_prints_it() -> void:
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


## A 3.6 carrier resolves the name as active and the primitive walk hands it back.
func test_a_carrier_gets_the_name_back_off_its_primitive_walk() -> void:
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


func test_existing_3_5_entries_are_unchanged() -> void:
	for c: Array in CONTROLS:
		var entry := RulesRegistry.lookup(c[0], c[1], c[2])
		assert_str(str(entry.get("primitive", ""))).override_failure_message(
			"%s/%s/%s: control primitive moved: %s" % [c[0], c[1], c[2], entry]).is_equal(str(c[3]))
		assert_dict(entry.get("params", {}) as Dictionary).override_failure_message(
			"%s/%s/%s: control params moved: %s" % [c[0], c[1], c[2], entry]).is_equal(c[4])
		assert_str(str(entry.get("book_version", ""))).override_failure_message(
			"%s/%s/%s: control book_version moved: %s" % [c[0], c[1], c[2], entry]).is_equal(str(c[5]))


## Reap rides the existing SHO-10 condition hook: the live stamp carries the Shaken/Fatigued gate
## and the widened 5-6 save window, and the window opens only against such a target.
func test_reap_stamps_the_shaken_or_fatigued_save_window_at_epoch_73() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var carrier := _unit(["Reap"], "gf", "rebel_guerrillas")
	var profile := {"name": "Probe Gun", "attacks": 8, "ap": 0, "range": 24, "rules": [], "bane": true}
	var stamped: Dictionary = (AiEv.stamp_sergeant([profile], carrier) as Array)[0]
	assert_bool(bool(stamped.get("bane", false))) \
		.override_failure_message("Reap must stamp the Bane re-roll flag").is_true()
	var condition: Dictionary = stamped.get("bane_condition", {})
	assert_str(str(condition.get("condition", ""))) \
		.override_failure_message("Reap must stamp the target condition, got %s" % [condition]) \
		.is_equal("shaken_or_fatigued")
	var window: Dictionary = AiEv.bane_boost_window(carrier, true)
	assert_int(int(window.get("low", 0))).override_failure_message(
		"Reap re-rolls successful 5s and 6s, got %s" % [window]).is_equal(5)
	assert_str(str(window.get("rule", ""))).is_equal("Reap")
	assert_bool(AiEv.bane_applies(stamped, 1, 4, 12.0, false, {"shaken_or_fatigued": true})) \
		.override_failure_message("a Shaken or Fatigued target must open Reap").is_true()
	assert_bool(AiEv.bane_applies(stamped, 1, 4, 12.0, false, {"shaken_or_fatigued": false})) \
		.override_failure_message("a fresh target must not open Reap").is_false()
	AiActRecorder.rules_epoch = epoch0
