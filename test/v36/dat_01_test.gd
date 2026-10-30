extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-01: Shred and Surge are core rules in both 3.6 systems, so the gf and aof
## mechanics maps carry them as common entries. A 3.6 book with no faction entry of its own then
## resolves them through the common fallback instead of leaving the player to apply them by hand.
## The params are the ones every faction entry already carries (one extra wound per unsaved 1, one
## bonus hit per 6), so a book that had its own entry resolves exactly as before.

const SHRED_PARAMS := {"extra_wound_per_save_one": 1}
const SURGE_PARAMS := {"bonus_hits_per_six": 1}


func before_test() -> void:
	RulesRegistry.reset_cache()


func _assert_resolves(system: String, book: String, rule: String, params: Dictionary) -> void:
	assert_bool(RulesRegistry.has_primitive(system, book, rule)) \
		.override_failure_message("%s / %s: %s must resolve to a primitive, not 'apply manually'" % [system, book, rule]) \
		.is_true()
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))).is_equal(rule)
	assert_dict(entry.get("params", {}) as Dictionary).is_equal(params)


func test_a_gf_book_without_its_own_entry_resolves_shred_and_surge() -> void:
	_assert_resolves("gf", "human_defense_force", "Shred", SHRED_PARAMS)
	_assert_resolves("gf", "human_defense_force", "Surge", SURGE_PARAMS)


func test_an_aof_book_without_its_own_entry_resolves_shred_and_surge() -> void:
	_assert_resolves("aof", "orcs", "Shred", SHRED_PARAMS)
	_assert_resolves("aof", "orcs", "Surge", SURGE_PARAMS)


## Control: books that already carried their own entries resolve to the same primitive and params,
## with and without the common entries.
func test_books_with_their_own_entry_resolve_shred_and_surge_unchanged() -> void:
	_assert_resolves("gf", "alien_hives", "Shred", SHRED_PARAMS)
	_assert_resolves("gf", "alien_hives", "Surge", SURGE_PARAMS)
	_assert_resolves("aof", "beastmen", "Shred", SHRED_PARAMS)
	_assert_resolves("aof", "beastmen", "Surge", SURGE_PARAMS)


## The scoped forms stay as they are: the common base names do not replace them.
func test_the_scoped_shred_form_keeps_its_own_entry() -> void:
	assert_bool(RulesRegistry.has_primitive("gf", "human_defense_force", "Shred when Shooting")).is_true()
