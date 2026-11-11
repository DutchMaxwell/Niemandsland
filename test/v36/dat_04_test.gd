extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-04: rules 3.6 renames Ignores Cover to Anti-Cover and Ignores Regeneration to
## Anti-Regen (the same mechanics, checked against the 3.6 descriptions), and gf renames the Ignores Cover
## family forms the same way. The gf and aof mechanics maps carry the new names with the old entries'
## primitive and params, so a 3.6 book that fields them resolves them instead of leaving the player to
## apply them by hand. The weapon-printed cover flag is a name read in both engines (row AI-08).

const COVER_PARAMS := {"ignores_cover": true, "cover_only": true}
const COVER_SHOOTING_PARAMS := {"ignores_cover": true, "cover_only": true, "shooting_only": true}
const REGEN_PARAMS := {"bypass_regen": true}


func before_test() -> void:
	RulesRegistry.reset_cache()


func _assert_resolves(system: String, book: String, rule: String, primitive: String, params: Dictionary) -> void:
	assert_bool(RulesRegistry.has_primitive(system, book, rule)) \
		.override_failure_message("%s / %s: %s must resolve to a primitive, not 'apply manually'" % [system, book, rule]) \
		.is_true()
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))).is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary).is_equal(params)


func _gf_unit(book: String, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_properties = {"game_system": "gf", "faction_folder": book, "special_rules": rules}
	return u


func test_a_gf_book_resolves_anti_cover_and_anti_regen() -> void:
	_assert_resolves("gf", "alien_hives", "Anti-Cover", "Indirect", COVER_PARAMS)
	_assert_resolves("gf", "alien_hives", "Anti-Regen", "Lacerate", REGEN_PARAMS)


func test_an_aof_book_resolves_anti_cover_and_anti_regen() -> void:
	_assert_resolves("aof", "dragon_empire", "Anti-Cover", "Indirect", COVER_PARAMS)
	_assert_resolves("aof", "dragon_empire", "Anti-Regen", "Lacerate", REGEN_PARAMS)


func test_gf_resolves_the_anti_cover_family_forms() -> void:
	_assert_resolves("gf", "dwarf_guilds", "Anti-Cover when Shooting", "Indirect", COVER_SHOOTING_PARAMS)
	_assert_resolves("gf", "eternal_dynasty", "Anti-Cover Aura", "Aura Channel", {"grants": "Anti-Cover"})
	_assert_resolves("gf", "dwarf_guilds", "Anti-Cover when Shooting Aura", "Aura Channel",
		{"grants": "Anti-Cover when Shooting"})


## The table's map-driven cover leg (no name literal): a unit-level Anti-Cover when Shooting stamps the
## ranged profiles to skip cover (the stamp the dice path and the AI estimate both read); melee stays.
func test_a_unit_with_anti_cover_when_shooting_skips_cover_with_its_ranged_weapons() -> void:
	var profiles: Array = [{"range": 24, "rules": []}, {"range": 0, "rules": []}]
	AiEv.stamp_sergeant(profiles, _gf_unit("dwarf_guilds", ["Anti-Cover when Shooting"]))
	assert_bool(bool((profiles[0] as Dictionary).get("ignores_cover", false))) \
		.override_failure_message("the ranged profile must skip cover") \
		.is_true()
	assert_bool(bool((profiles[1] as Dictionary).get("ignores_cover", false))).is_false()


## The table's map-driven Regeneration leg: a weapon that prints Anti-Regen is looked up in the map by
## the dice path's Regeneration check, so its wounds skip the Regeneration roll.
func test_a_weapon_with_anti_regen_ignores_regeneration_on_the_table() -> void:
	var main: Node = auto_free(load("res://scripts/main.gd").new())
	var ignores: bool = main.call("_solo_ignores_regen", _gf_unit("alien_hives", []),
		{"range": 24, "rules": ["Anti-Regen"]})
	assert_bool(ignores) \
		.override_failure_message("an Anti-Regen weapon must ignore Regeneration") \
		.is_true()


## Control: the 3.5 names stay (row DAT-14 removes them later) and resolve exactly as before.
func test_the_old_names_resolve_unchanged() -> void:
	_assert_resolves("gf", "alien_hives", "Ignores Cover", "Indirect", COVER_PARAMS)
	_assert_resolves("aof", "dragon_empire", "Ignores Cover", "Indirect", COVER_PARAMS)
	_assert_resolves("gf", "alien_hives", "Ignores Regeneration", "Lacerate", REGEN_PARAMS)
	_assert_resolves("aof", "dragon_empire", "Ignores Regeneration", "Lacerate", REGEN_PARAMS)
	_assert_resolves("gf", "eternal_dynasty", "Ignores Cover Aura", "Aura Channel", {"grants": "Ignores Cover"})
