extends GdUnitTestSuite
## v3.6 row DAT-06: rules 3.6 renamed the Piercing Assault family and Reach Hunt without changing
## their mechanic, and added Extra Reach. A 3.6 book that prints the new name had no map entry, so
## the lookup came back empty and the rule fell through to "apply by hand". The map's "common"
## section now carries one entry per system for every new name, built from the 3.5 twin's
## primitive and params; the aura/buff entries grant the NEW base name. The control: an old-name
## entry still resolves the old primitive and params, so the change stays add-only.

const EXPECTED := {
	"gf": {
		"Piercing Charge": {"primitive": "Piercing Assault", "rated": false,
			"params": {"ap_bonus": 1, "condition": "on_charge"}},
		"Piercing Charge Aura": {"primitive": "Aura Channel", "rated": false,
			"params": {"grants": "Piercing Charge"}},
		"Extra Reach": {"primitive": "Royal Legion", "rated": false,
			"params": {"range_bonus_in": 4, "charge_mod": 2}},
		"Piercing Marksman Aura": {"primitive": "Aura Channel", "rated": false,
			"params": {"grants": "Piercing Marksman"}},
	},
	"aof": {
		"Piercing Charge": {"primitive": "Piercing Assault", "rated": false,
			"params": {"ap_bonus": 1, "condition": "on_charge"}},
		"Piercing Charge Aura": {"primitive": "Aura Channel", "rated": false,
			"params": {"grants": "Piercing Charge"}},
		"Piercing Charge Buff": {"primitive": "Utility Buff", "rated": false,
			"params": {"grants_rule": "Piercing Charge", "target": "friendly",
				"max_targets": 1, "range_in": 12, "once": true}},
		"Extra Reach": {"primitive": "Royal Legion", "rated": false,
			"params": {"range_bonus_in": 4, "charge_mod": 2}},
	},
}

## One gap book per system and name: a 3.6 book that prints the name but has no section entry.
const GAP_CASES := [
	["gf", "ratmen_clans", "Piercing Charge"],
	["gf", "ratmen_clans", "Piercing Charge Aura"],
	["gf", "high_elf_fleets", "Extra Reach"],
	["gf", "blessed_sisters", "Piercing Marksman Aura"],
	["aof", "beastmen", "Piercing Charge"],
	["aof", "beastmen", "Piercing Charge Aura"],
	["aof", "dark_elves", "Piercing Charge Buff"],
	["aof", "high_elves", "Extra Reach"],
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
		assert_bool((got is int or got is float) and int(got) == int(want)) \
			.override_failure_message(msg).is_true()
	else:
		assert_str(str(got)).override_failure_message(msg).is_equal(str(want))


func _assert_entry(where: String, got: Dictionary, want: Dictionary) -> void:
	assert_str(str(got.get("primitive", ""))) \
		.override_failure_message("%s: the lookup must find an automating entry" % where) \
		.is_equal(str(want["primitive"]))
	assert_bool(bool(got.get("rated", false)) == bool(want["rated"])) \
		.override_failure_message("%s: rated flag" % where).is_true()
	assert_str(str(got.get("book_version", ""))) \
		.override_failure_message("%s: book_version" % where).is_equal("3.6.0")
	var params: Dictionary = got.get("params", {})
	var want_params: Dictionary = want["params"]
	assert_int(params.size()).override_failure_message("%s: param count" % where) \
		.is_equal(want_params.size())
	for key in want_params:
		_assert_param(where, str(key), params.get(key), want_params[key])


func _assert_resolves(system: String, faction: String, rule_name: String) -> void:
	var want: Dictionary = EXPECTED[system][rule_name]
	var where := "%s/%s/%s" % [system, faction, rule_name]
	_assert_entry(where, RulesRegistry.lookup(system, faction, rule_name), want)


func test_gap_books_resolve_the_new_piercing_and_extra_reach_names() -> void:
	for case in GAP_CASES:
		_assert_resolves(str(case[0]), str(case[1]), str(case[2]))


func test_control_old_name_entries_are_unchanged() -> void:
	var gf_assault := RulesRegistry.lookup("gf", "ratmen_clans", "Piercing Assault")
	assert_str(str(gf_assault.get("primitive", ""))) \
		.override_failure_message("gf/ratmen_clans/Piercing Assault: primitive") \
		.is_equal("Piercing Assault")
	assert_int(int(gf_assault.get("params", {}).get("ap_bonus", 0))) \
		.override_failure_message("gf/ratmen_clans/Piercing Assault: ap_bonus").is_equal(1)
	assert_str(str(gf_assault.get("book_version", ""))) \
		.override_failure_message("gf/ratmen_clans/Piercing Assault: book_version") \
		.is_equal("3.5.3")

	var aof_buff := RulesRegistry.lookup("aof", "dark_elves", "Piercing Assault Buff")
	assert_str(str(aof_buff.get("primitive", ""))) \
		.override_failure_message("aof/dark_elves/Piercing Assault Buff: primitive") \
		.is_equal("Utility Buff")
	assert_str(str(aof_buff.get("params", {}).get("grants_rule", ""))) \
		.override_failure_message("aof/dark_elves/Piercing Assault Buff: grants_rule") \
		.is_equal("Piercing Assault")
	assert_str(str(aof_buff.get("book_version", ""))) \
		.override_failure_message("aof/dark_elves/Piercing Assault Buff: book_version") \
		.is_equal("3.5.3")
