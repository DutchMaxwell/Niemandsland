extends GdUnitTestSuite
## DAT-08a (0.3.15, rules 3.6): melee names that some 3.6 books field without an entry of their own
## in the GF / AoF rule maps. Each name has one 3.6 description and one set of parameters across its
## system, so it lives ONCE in the system's common section and every book that fields it resolves it.
## Every case reads the real maps through RulesRegistry.lookup (faction first, then common); the
## expected primitive and knobs are written out here, never read back from the map under test.
## Numbers are floats: Godot's JSON parser reads every map number as one.

const MARK_PARAMS := {"beneficiary": "attackers", "grants_rule": "Unpredictable Fighter",
	"max_targets": 1.0, "needs_los": true, "once": true, "range_in": 18.0, "target": "enemy",
	"vs_target": true}


func before_test() -> void:
	RulesRegistry.reset_cache()


func _assert_resolves(system: String, book: String, rule: String, primitive: String,
		params: Dictionary, version: String) -> void:
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))).override_failure_message(
		"%s/%s does not resolve %s to %s: %s" % [system, book, rule, primitive, entry]).is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary).override_failure_message(
		"%s/%s resolves %s with other knobs: %s" % [system, book, rule, entry]).is_equal(params)
	assert_str(str(entry.get("book_version", ""))).override_failure_message(
		"%s/%s answers %s from the wrong entry: %s" % [system, book, rule, entry]).is_equal(version)


func test_gf_crossing_attack_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("gf", "alien_hives", "Crossing Attack", "Crossing Attack",
		{"rating": "X", "wound_target": 6.0}, "3.6.0")


func test_gf_unpredictable_fighter_resolves_in_books_without_their_own_entry() -> void:
	for book: String in ["daemons_of_lust", "infected_colonies"]:
		_assert_resolves("gf", book, "Unpredictable Fighter", "Unpredictable Fighter", {}, "3.6.0")


func test_gf_unpredictable_fighter_mark_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("gf", "voidspace_stalkers", "Unpredictable Fighter Mark", "Utility Buff",
		MARK_PARAMS, "3.6.0")


func test_aof_crossing_attack_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("aof", "goblins", "Crossing Attack", "Crossing Attack",
		{"rating": "X", "wound_target": 6.0}, "3.6.0")


func test_aof_unpredictable_fighter_resolves_in_books_without_their_own_entry() -> void:
	for book: String in ["daemons_of_lust", "daemons_of_war"]:
		_assert_resolves("aof", book, "Unpredictable Fighter", "Unpredictable Fighter", {}, "3.6.0")


func test_aof_unpredictable_fighter_aura_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("aof", "daemons_of_war", "Unpredictable Fighter Aura", "Aura Channel",
		{"grants": "Unpredictable Fighter"}, "3.6.0")


func test_aof_melee_slayer_aura_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("aof", "duchies_of_vinci", "Melee Slayer Aura", "Aura Channel",
		{"grants": "Melee Slayer"}, "3.6.0")


## CONTROL (passes with and without the change): a book that already had its own entry keeps
## answering from it, with the same knobs the common entry carries.
func test_control_books_with_their_own_entry_keep_it() -> void:
	_assert_resolves("gf", "high_elf_fleets", "Crossing Attack", "Crossing Attack",
		{"rating": "X", "wound_target": 6.0}, "3.5.3")
	_assert_resolves("gf", "alien_hives", "Unpredictable Fighter Mark", "Utility Buff",
		MARK_PARAMS, "3.5.3")
	_assert_resolves("gf", "machine_cults", "Unpredictable Fighter", "Unpredictable Fighter", {}, "3.5.3")
	_assert_resolves("aof", "ghostly_undead", "Crossing Attack", "Crossing Attack",
		{"rating": "X", "wound_target": 6.0}, "3.5.3")
	_assert_resolves("aof", "goblins", "Unpredictable Fighter", "Unpredictable Fighter", {}, "3.5.3")
	_assert_resolves("aof", "ogres", "Unpredictable Fighter Aura", "Aura Channel",
		{"grants": "Unpredictable Fighter"}, "3.5.3")
	_assert_resolves("aof", "dragon_empire", "Melee Slayer Aura", "Aura Channel",
		{"grants": "Melee Slayer"}, "3.5.3")
