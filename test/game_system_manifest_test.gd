extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 8: GameSystem.manifest_keys picks the AI lists of the EXACT system (no gf / aof family
## folding); an entry without a "system" is a gf list; "" = no system named yet, every list. short() is the crowded-list form.

const MANIFEST := {
	"a": {"system": "gf"}, "b": {}, "c": {"system": "gff"}, "d": {"system": "aof"}, "e": {"system": "aofs"}, "f": {"system": "aofr"},
}


func test_every_system_gets_exactly_its_own_lists() -> void:
	assert_array(GameSystem.manifest_keys(MANIFEST, "gf")).contains_exactly_in_any_order(["a", "b"])
	assert_array(GameSystem.manifest_keys(MANIFEST, "gff")).is_equal(["c"])
	assert_array(GameSystem.manifest_keys(MANIFEST, "aof")).is_equal(["d"])
	assert_array(GameSystem.manifest_keys(MANIFEST, "aofs")).is_equal(["e"])
	assert_array(GameSystem.manifest_keys(MANIFEST, "aofr")).is_equal(["f"])
	assert_array(GameSystem.manifest_keys({"a": {"system": "gf"}}, "aofs")).is_empty()


func test_no_system_named_offers_every_list() -> void:
	assert_int(GameSystem.manifest_keys(MANIFEST, "").size()).is_equal(6)


func test_short_forms() -> void:
	var shorts := GameSystem.IDS.map(func(id: String) -> String: return GameSystem.short(id))
	assert_array(shorts).is_equal(["GF", "GFF", "AoF", "AoFS", "AoFR"])
