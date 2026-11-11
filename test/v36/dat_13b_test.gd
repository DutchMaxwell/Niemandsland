extends GdUnitTestSuite
## DAT-13b (0.3.15, rules 3.6): the gf and aof spell maps are re-exported from the 3.6 Army Forge data.
## Spell lists keep the book order, thresholds and ranges of the 3.6 books, a spell that needs line of
## sight says so (needs_los true) and one without a sight clause carries no flag, and the Voidspace
## Stalkers book has a list. The skirmish maps (gff, aofs, aofr) stay the 3.5 export (D-SCOPE).
## Every expected value is written out here, never read back from the map under test.


func before_test() -> void:
	SpellsRegistry.reset_cache()


func after_test() -> void:
	SpellsRegistry.reset_cache()


func _list(system: String, book: String) -> Array:
	var out: Array = []
	for e in SpellsRegistry.spells_for(system, book):
		var sp := e as Dictionary
		out.append([str(sp.get("name", "")), int(sp.get("threshold", 0)), int(sp.get("range_in", 0)),
			bool(sp.get("needs_los", false))])
	return out


func test_a_gf_book_lists_its_3_6_spells_in_book_order() -> void:
	assert_array(_list("gf", "battle_brothers")).is_equal([
		["Protective Dome", 1, 12, false], ["Psychic Terror", 1, 6, false],
		["Advanced Sight", 2, 18, true], ["Lightning Fog", 2, 9, false],
		["Blessed Ammo", 3, 18, false], ["Cerebral Trauma", 3, 24, true]])


func test_an_aof_book_lists_its_3_6_spells_in_book_order() -> void:
	assert_array(_list("aof", "orcs")).is_equal([
		["Evil Gaze", 1, 12, false], ["Bone Strike", 1, 6, false],
		["Magic Fists", 2, 18, true], ["Godly Smash", 2, 12, true],
		["Way-Clan Chant", 3, 18, false], ["Iron Burst", 3, 18, true]])


func test_the_voidspace_stalkers_book_has_a_gf_spell_list() -> void:
	var names: Array = []
	for e in SpellsRegistry.spells_for("gf", "voidspace_stalkers"):
		names.append(str((e as Dictionary).get("name", "")))
	assert_array(names).is_equal(["Combat Psychosis", "Cyber Shock", "Synaptic Stims",
		"Overheat Internals", "Optical Malfunction", "System Collapse"])


func test_the_skirmish_maps_keep_the_3_5_export() -> void:
	# Control: gff battle_brothers still starts with the 3.5 order (Advanced Sight at one token).
	var first: Dictionary = SpellsRegistry.spells_for("gff", "battle_brothers")[0]
	assert_str(str(first.get("name", ""))).is_equal("Advanced Sight")
	assert_int(int(first.get("threshold", 0))).is_equal(1)
