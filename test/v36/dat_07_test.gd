extends GdUnitTestSuite
## v3.6 row DAT-07: Heavy Impact, Precise and Unwieldy each resolve ONCE per system from the map's
## "common" section. The 3.6 books spread the three names to books whose faction section never had
## an entry (gf: 9 Heavy Impact books, dao_union Precise, alien_hives + dwarf_guilds Unwieldy; aof:
## 11 Heavy Impact books, saurians Precise, dwarves + eternal_wardens Unwieldy). On main the lookup
## for such a book finds nothing, so the rule falls through to "apply by hand" and a registry-gated
## primitive (Unwieldy) never fires. The control: a book that already had its own entry resolves the
## same primitive and params before and after the change.

const EXPECTED := {
	"Heavy Impact": {"primitive": "Heavy Impact", "rated": true,
		"params": {"rating": "X", "ap": 1, "counts_as": "Impact"}},
	"Precise": {"primitive": "Precise", "rated": false, "params": {"hit_bonus": 1}},
	"Unwieldy": {"primitive": "Unwieldy", "rated": false,
		"params": {"condition": "charging", "strikes_last": true}},
}


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


## One param value against its expectation, typed (the parsed JSON holds floats for numbers).
func _assert_param(where: String, key: String, got: Variant, want: Variant) -> void:
	var msg := "%s: param %s" % [where, key]
	if want is bool:
		assert_bool(got is bool and bool(got) == bool(want)).override_failure_message(msg).is_true()
	elif want is int:
		assert_bool((got is int or got is float) and int(got) == int(want)) \
			.override_failure_message(msg).is_true()
	else:
		assert_str(str(got)).override_failure_message(msg).is_equal(str(want))


func _assert_resolves(system: String, faction: String, rule_name: String) -> void:
	var want: Dictionary = EXPECTED[rule_name]
	var where := "%s/%s/%s" % [system, faction, rule_name]
	var got := RulesRegistry.lookup(system, faction, rule_name)
	assert_str(str(got.get("primitive", ""))) \
		.override_failure_message("%s: the lookup must find an automating entry" % where) \
		.is_equal(str(want["primitive"]))
	assert_bool(bool(got.get("rated", false)) == bool(want["rated"])) \
		.override_failure_message("%s: rated flag" % where).is_true()
	var params: Dictionary = got.get("params", {})
	var want_params: Dictionary = want["params"]
	assert_int(params.size()).override_failure_message("%s: param count" % where) \
		.is_equal(want_params.size())
	for key in want_params:
		_assert_param(where, str(key), params.get(key), want_params[key])


func _unit_with(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t_1"
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func test_gf_gap_books_resolve_heavy_impact_precise_unwieldy() -> void:
	_assert_resolves("gf", "change_disciples", "Heavy Impact")
	_assert_resolves("gf", "orc_marauders", "Heavy Impact")
	_assert_resolves("gf", "dao_union", "Precise")
	_assert_resolves("gf", "alien_hives", "Unwieldy")
	_assert_resolves("gf", "dwarf_guilds", "Unwieldy")


func test_aof_gap_books_resolve_heavy_impact_precise_unwieldy() -> void:
	_assert_resolves("aof", "havoc_warriors", "Heavy Impact")
	_assert_resolves("aof", "wood_elves", "Heavy Impact")
	_assert_resolves("aof", "saurians", "Precise")
	_assert_resolves("aof", "dwarves", "Unwieldy")
	_assert_resolves("aof", "eternal_wardens", "Unwieldy")


func test_unwieldy_carrier_in_a_gap_book_counts_for_the_strike_order() -> void:
	# The registry-gated reader main.gd's charge order uses: a gap-book carrier must count.
	for case in [["gf", "dwarf_guilds"], ["aof", "dwarves"]]:
		var u := _unit_with(["Unwieldy"], str(case[0]), str(case[1]))
		assert_int(RulesRegistry.unit_rules_of_primitive(u, "Unwieldy").size()) \
			.override_failure_message("%s/%s: an Unwieldy carrier must resolve" % case).is_equal(1)


func test_control_books_with_own_entries_resolve_unchanged() -> void:
	_assert_resolves("gf", "saurian_starhost", "Heavy Impact")
	_assert_resolves("gf", "prime_brothers", "Precise")
	_assert_resolves("gf", "high_elf_fleets", "Unwieldy")
	_assert_resolves("aof", "ratmen", "Heavy Impact")
	_assert_resolves("aof", "wood_elves", "Precise")
	_assert_resolves("aof", "ogres", "Unwieldy")
