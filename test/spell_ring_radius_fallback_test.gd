# gdUnit4 tests: the spell range ring radius. With effect text it is parsed from the text exactly as
# before; WITHOUT text (the shipped lesson boards carry none) it comes from the text-free mechanics
# map's range_in for the caster's (system, faction). A spell the map does not know stays "no ring".
extends GdUnitTestSuite


func before_test() -> void:
	SpellsRegistry.reset_cache()


func test_empty_effect_takes_radius_from_mechanics_map() -> void:
	assert_int(OPRApiClient.spell_radius_for("", "gf", "battle_brothers", "Protective Dome")).is_equal(12)
	assert_int(OPRApiClient.spell_radius_for("", "gf", "battle_brothers", "Cerebral Trauma")).is_equal(24)
	assert_int(OPRApiClient.spell_radius_for("", "gf", "robot_legions", "Gauss Bots")).is_equal(6)


func test_whitespace_only_effect_counts_as_no_text() -> void:
	assert_int(OPRApiClient.spell_radius_for("  \n", "gf", "battle_brothers", "Psychic Terror")).is_equal(6)


func test_spell_unknown_to_the_map_yields_no_ring() -> void:
	assert_int(OPRApiClient.spell_radius_for("", "gf", "battle_brothers", "No Such Spell")).is_equal(0)
	assert_int(OPRApiClient.spell_radius_for("", "gf", "no_such_faction", "Protective Dome")).is_equal(0)
	assert_int(OPRApiClient.spell_radius_for("", "gf", "", "Protective Dome")).is_equal(0)
	assert_int(OPRApiClient.spell_radius_for("", "gf", "battle_brothers", "")).is_equal(0)


func test_a_miss_is_quiet_for_the_missing_book_counter() -> void:
	SpellsRegistry.reset_cache()
	OPRApiClient.spell_radius_for("", "gf", "no_such_faction", "Protective Dome")
	assert_int(SpellsRegistry.missing_faction_warnings).is_equal(0)


func test_text_present_is_parsed_from_the_text_as_before() -> void:
	# Own synthetic wording. The map says 6 for this spell; the text wins when there is text.
	assert_int(OPRApiClient.spell_radius_for("Pick a unit within 3\".", "gf", "robot_legions", "Gauss Bots")).is_equal(3)
	assert_int(OPRApiClient.spell_radius_for("Pick a unit within 3\".", "gf", "robot_legions", "Gauss Bots")) \
		.is_equal(OPRApiClient.spell_radius_inches("Pick a unit within 3\"."))


func test_text_present_without_a_range_stays_no_ring() -> void:
	# The map would say 12, but a spell WITH text and no range token is a self/army-wide spell today
	# and must stay one: the fallback is for missing text only.
	assert_int(OPRApiClient.spell_radius_for("The caster gets a bonus.", "gf", "battle_brothers", "Protective Dome")).is_equal(0)
