extends GdUnitTestSuite
## v3.6 row DAT-08c: the buff, casting and morale names of group c each resolve ONCE per system from
## the map's "common" section. The 3.6 books spread them to books whose faction section never had
## an entry (gf: voidspace_stalkers Extended Buff Range + Rapid Rush Buff, infected_colonies
## Regeneration Buff; aof: dwarves Spell Accumulator, saurians Spell Conduit, ogres Caster Group,
## havoc_dwarves Steadfast Aura). On main the lookup for such a book finds nothing, so the rule falls
## through to "apply by hand" and a registry-gated reader (Caster Group's caster gate) never fires.
## The control: a book that already had its own entry resolves the same primitive and params before
## and after the change (gf Rapid Rush Buff had no entry anywhere; aof human_empire is its twin).

const EXPECTED := {
	"Extended Buff Range": {"primitive": "Extended Buff Range", "rated": false,
		"params": {"excludes_spells": true, "hero_link_in": 0, "pick_range_in": 12,
			"relay_range_in": 24, "requires_hero": true}},
	"Rapid Rush Buff": {"primitive": "Utility Buff", "rated": false,
		"params": {"grants_rule": "Rapid Rush", "max_targets": 1, "once": true, "range_in": 12,
			"target": "friendly"}},
	"Regeneration Buff": {"primitive": "Regeneration", "rated": false, "params": {"ignore_target": 5}},
	"Spell Accumulator": {"primitive": "Spell Accumulator", "rated": true,
		"params": {"max_tokens": 6, "requires_not_shaken": true, "share_range_in": 12,
			"tokens_per_round": "X"}},
	"Spell Conduit": {"primitive": "Spell Conduit", "rated": false,
		"params": {"casting_mod": 1, "range_in": 12, "requires_not_shaken": true}},
	"Caster Group": {"primitive": "Caster", "rated": false, "params": {"pooled": true}},
	"Steadfast Aura": {"primitive": "Aura Channel", "rated": false, "params": {"grants": "Steadfast"}},
}

## [system, gap book, name]: a 3.6 carrier whose faction section has no entry on main.
const GAPS := [
	["gf", "voidspace_stalkers", "Extended Buff Range"],
	["gf", "voidspace_stalkers", "Rapid Rush Buff"],
	["gf", "infected_colonies", "Regeneration Buff"],
	["aof", "dwarves", "Spell Accumulator"],
	["aof", "saurians", "Spell Conduit"],
	["aof", "ogres", "Caster Group"],
	["aof", "havoc_dwarves", "Steadfast Aura"],
]


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
		assert_bool((got is int or got is float) and is_equal_approx(float(got), float(want))) \
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


func test_gap_books_resolve_group_c_names() -> void:
	for g in GAPS:
		_assert_resolves(str(g[0]), str(g[1]), str(g[2]))


func test_gap_book_carriers_are_no_longer_left_to_the_player() -> void:
	# The "apply manually" inventory and the wave-5 gates read has_primitive / unit_rule_active.
	for g in GAPS:
		var u := _unit_with([str(g[2])], str(g[0]), str(g[1]))
		assert_bool(RulesRegistry.unit_rule_active(u, str(g[2]))) \
			.override_failure_message("%s/%s/%s: a carrier must be automated" % g).is_true()


func test_control_books_with_own_entries_resolve_unchanged() -> void:
	_assert_resolves("gf", "human_defense_force", "Extended Buff Range")
	_assert_resolves("aof", "human_empire", "Rapid Rush Buff")
	_assert_resolves("gf", "dark_elf_raiders", "Regeneration Buff")
	_assert_resolves("aof", "deep_sea_elves", "Spell Accumulator")
	_assert_resolves("aof", "high_elves", "Spell Conduit")
	_assert_resolves("aof", "goblins", "Caster Group")
	_assert_resolves("aof", "havoc_warriors", "Steadfast Aura")
