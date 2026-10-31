extends GdUnitTestSuite
## DAT-05a (0.3.15, rules 3.6): the Bravery family. Rules 3.6 renamed the Courage mechanic to Bravery
## without changing it, so every 3.6 book that fields it must resolve:
##   - "Bravery Aura": a Banner carrier, +1 to the unit's morale tests;
##   - "Bravery Buff": a once-per-activation friendly Utility Buff, +1 to one morale test within 12";
##   - "Bravery": the base our own aura expansion grants to the aura carrier (no book defines it).
## A 3.6 book that prints the name without a section entry of its own resolves it through the
## system's common fallback instead of leaving the player to apply it by hand. The knobs are
## written out here, never read back from the map under test. Godot's JSON parser reads every
## map number as a float.

const AURA_PARAMS := {"morale_bonus": 1.0}
const BUFF_PARAMS := {"morale_mod": 1.0, "range_in": 12.0, "target": "friendly", "once": true}


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
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


func test_gf_bravery_aura_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("gf", "blessed_sisters", "Bravery Aura", "Banner", AURA_PARAMS, "3.6.0")


func test_gf_bravery_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("gf", "blessed_sisters", "Bravery", "Banner", AURA_PARAMS, "3.6.0")


func test_gf_bravery_buff_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("gf", "blessed_sisters", "Bravery Buff", "Utility Buff", BUFF_PARAMS, "3.6.0")


func test_aof_bravery_aura_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("aof", "ogres", "Bravery Aura", "Banner", AURA_PARAMS, "3.6.0")


func test_aof_bravery_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("aof", "ogres", "Bravery", "Banner", AURA_PARAMS, "3.6.0")


func test_aof_bravery_buff_resolves_in_a_book_without_its_own_entry() -> void:
	_assert_resolves("aof", "chivalrous_kingdoms", "Bravery Buff", "Utility Buff", BUFF_PARAMS,
		"3.6.0")


## CONTROL (passes with and without the change): the old Courage twins keep answering from the
## books' own entries, untouched by the additive Bravery common entries.
func test_control_the_old_courage_twins_keep_their_own_entries() -> void:
	_assert_resolves("gf", "blessed_sisters", "Courage Aura", "Banner", AURA_PARAMS, "3.5.3")
	_assert_resolves("gf", "blessed_sisters", "Courage Buff", "Utility Buff", BUFF_PARAMS, "3.5.3")
	_assert_resolves("aof", "ogres", "Courage Aura", "Banner", AURA_PARAMS, "3.5.3")
	_assert_resolves("aof", "chivalrous_kingdoms", "Courage Buff", "Utility Buff", BUFF_PARAMS,
		"3.5.3")
