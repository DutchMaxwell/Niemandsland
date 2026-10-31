extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-08b: eight shooting / move / deploy rules get ONE shared ("common") entry per
## game system, so a 3.6 book that fields the rule but never had its own entry resolves it too. Before
## this row a carrier in such a book matched nothing in the map: the rule inventory still listed it as
## automated (the name is on the modeled list), but the table never applied it.
##
## Each case below is one book that fields the rule in its 3.6 data and has no faction entry for it.
## The control case is a book that always had its own entry: it must resolve the same before and after.

## [system, book (faction section key), rule, primitive, params] — params checked against the 3.6 data.
const GAP_CASES := [
	["gf", "machine_cults", "Agile", "Quick", {"advance_mod": 1, "rush_mod": 2}],
	["gf", "elven_jesters", "Ambushing Piercing Shot", "Ambush", {"counts_as": "Ambush"}],
	["gf", "alien_hives", "Predator", "Surge", {"extra_attack": true}],
	["gf", "watch_brothers", "Re-Deployment", "Re-Deployment", {"max_units": 2}],
	["gf", "elven_jesters", "Repel Ambushers", "Repel Ambushers", {"min_dist_in": 12.0}],
	["gf", "voidspace_stalkers", "Repel Ambushers", "Repel Ambushers", {"min_dist_in": 12.0}],
	["gf", "robot_legions", "Stealth Buff", "Stealth", {"hit_penalty": 1, "over_in": 9.0}],
	["aof", "vampiric_undead", "Ambush Aura", "Aura Channel", {"grants": "Ambush"}],
	["aof", "duchies_of_vinci", "Good Shot", "Shot Modifier", {"hit_bonus": 1}],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _unit_with(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "dat08b"
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## The map's JSON numbers load as floats, so params compare key by key, numbers by value.
func _params_match(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for k in expected:
		if not actual.has(k):
			return false
		var want: Variant = expected[k]
		var got: Variant = actual[k]
		if want is int or want is float:
			if not (got is int or got is float) or not is_equal_approx(float(got), float(want)):
				return false
		elif got != want:
			return false
	return true


func test_every_gap_book_resolves_its_rule_with_the_3_6_params() -> void:
	for c in GAP_CASES:
		var system := str(c[0])
		var book := str(c[1])
		var rule := str(c[2])
		var entry := RulesRegistry.lookup(system, book, rule)
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s/%s: %s resolves to nothing, the table never applies it" % [system, book, rule]) \
			.is_equal(str(c[3]))
		assert_bool(_params_match(entry.get("params", {}) as Dictionary, c[4] as Dictionary)) \
			.override_failure_message("%s/%s: %s params differ from the 3.6 data" % [system, book, rule]) \
			.is_true()


func test_a_gap_book_carrier_passes_the_rule_gate() -> void:
	for c in GAP_CASES:
		var u := _unit_with([str(c[2])], str(c[0]), str(c[1]))
		assert_bool(RulesRegistry.unit_rule_active(u, str(c[2]))) \
			.override_failure_message("%s/%s: a unit carrying %s fails the rule gate" % [c[0], c[1], c[2]]) \
			.is_true()


func test_an_agile_unit_of_a_gap_book_moves_farther() -> void:
	var bands := MovementRangeController.move_bands_for_props({"special_rules": ["Agile"],
		"game_system": "gf", "faction_folder": "machine_cults"})
	assert_int(int(bands["advance"])).override_failure_message("Agile adds 1\" to Advance").is_equal(7)
	assert_int(int(bands["rush"])).override_failure_message("Agile adds 2\" to Rush").is_equal(14)


## Control: books that always had their own entry keep resolving exactly that entry.
func test_control_books_with_their_own_entry_resolve_unchanged() -> void:
	var gf_own := RulesRegistry.lookup("gf", "orc_marauders", "Agile")
	assert_str(str(gf_own.get("primitive", ""))).is_equal("Quick")
	assert_bool(_params_match(gf_own.get("params", {}) as Dictionary, {"advance_mod": 1, "rush_mod": 2})).is_true()
	var aof_own := RulesRegistry.lookup("aof", "saurians", "Good Shot")
	assert_str(str(aof_own.get("primitive", ""))).is_equal("Shot Modifier")
	assert_bool(_params_match(aof_own.get("params", {}) as Dictionary, {"hit_bonus": 1})).is_true()
	var bands := MovementRangeController.move_bands_for_props({"special_rules": ["Agile"],
		"game_system": "gf", "faction_folder": "orc_marauders"})
	assert_int(int(bands["advance"])).is_equal(7)
	assert_int(int(bands["rush"])).is_equal(14)
