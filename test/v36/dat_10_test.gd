extends GdUnitTestSuite
## DAT-10 (0.3.15, rules 3.6): three movement names change their numbers in the 3.6 books.
## Scurry keeps its shape and drops to +1" Advance / +2" Rush and Charge. Lustbound stops being a
## range-and-charge rule and becomes the same +1" / +2" movement as Agile. Highborn stops being a
## movement rule and becomes +4" shooting range and +2" charge, the Royal Legion shape.
## Every case reads the real maps through RulesRegistry.lookup and the table's own band and range
## readers (MovementRangeController.move_bands_for_props, SoloController.shooting_range_bonus).
## The expected numbers are written out here, never read back from the map under test.
## Numbers are floats in the params: Godot's JSON parser reads every map number as one.

const AGILE_SHAPE := {"advance_mod": 1.0, "rush_mod": 2.0}
const RANGE_CHARGE_SHAPE := {"range_bonus_in": 4.0, "charge_mod": 2.0}

## Every book in the two maps that carries an entry of its own for each name.
const BOOKS := {
	"Scurry": [["gf", "ratmen_clans"], ["aof", "ratmen"]],
	"Lustbound": [["gf", "lust_disciples"], ["gf", "titan_lords_lust_disciples"],
		["gf", "wormhole_daemons_of_lust"], ["aof", "giant_tribes_lust_disciples"],
		["aof", "lust_disciples"], ["aof", "rift_daemons_of_lust"]],
	"Highborn": [["gf", "high_elf_fleets"], ["aof", "high_elves"]],
}


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _unit_with(rules: Array, system: String, book: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "dat10"
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": book}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _assert_entry(system: String, book: String, rule: String, primitive: String,
		params: Dictionary, version: String) -> void:
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))).override_failure_message(
		"%s/%s files %s under the wrong primitive: %s" % [system, book, rule, entry]).is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary).override_failure_message(
		"%s/%s still holds other numbers for %s: %s" % [system, book, rule, entry]).is_equal(params)
	assert_str(str(entry.get("book_version", ""))).override_failure_message(
		"%s/%s answers %s from an older book: %s" % [system, book, rule, entry]).is_equal(version)


func _assert_bands(system: String, book: String, rules: Array, advance: int, rush: int,
		charge: int) -> void:
	var b := MovementRangeController.move_bands_for_props(
		{"game_system": system, "faction_folder": book, "special_rules": rules})
	assert_array([b["advance"], b["rush"], b["charge"]]).override_failure_message(
		"%s/%s %s moves %s, not %s" % [system, book, rules, b, [advance, rush, charge]]) \
		.is_equal([advance, rush, charge])


func test_scurry_entries_hold_the_smaller_advance_bonus() -> void:
	for pair: Array in BOOKS["Scurry"]:
		_assert_entry(pair[0], pair[1], "Scurry", "Quick", AGILE_SHAPE, "3.6.0")


func test_lustbound_entries_hold_the_agile_movement() -> void:
	for pair: Array in BOOKS["Lustbound"]:
		_assert_entry(pair[0], pair[1], "Lustbound", "Quick", AGILE_SHAPE, "3.6.0")


func test_highborn_entries_hold_the_range_and_charge_bonus() -> void:
	for pair: Array in BOOKS["Highborn"]:
		_assert_entry(pair[0], pair[1], "Highborn", "Royal Legion", RANGE_CHARGE_SHAPE, "3.6.0")


func test_the_table_moves_scurry_and_lustbound_one_and_two_inches_further() -> void:
	for rule: String in ["Scurry", "Lustbound"]:
		for pair: Array in BOOKS[rule]:
			_assert_bands(pair[0], pair[1], [rule], 7, 14, 14)


func test_the_table_gives_highborn_only_the_longer_charge() -> void:
	for pair: Array in BOOKS["Highborn"]:
		_assert_bands(pair[0], pair[1], ["Highborn"], 6, 12, 14)


func test_highborn_shoots_further_and_lustbound_does_not() -> void:
	for pair: Array in BOOKS["Highborn"]:
		assert_int(SoloController.shooting_range_bonus(_unit_with(["Highborn"], pair[0], pair[1]))) \
			.override_failure_message("%s/%s: Highborn shoots at printed range" % pair).is_equal(4)
	for pair: Array in BOOKS["Lustbound"]:
		assert_int(SoloController.shooting_range_bonus(_unit_with(["Lustbound"], pair[0], pair[1]))) \
			.override_failure_message("%s/%s: Lustbound still lends shooting range" % pair).is_equal(0)


## CONTROL (passes with and without the change): the two shapes the three names now borrow keep
## their own numbers and bands, so the readers above are the real ones and read correctly.
func test_control_agile_and_royal_legion_keep_their_numbers() -> void:
	_assert_entry("gf", "high_elf_fleets", "Agile", "Quick", AGILE_SHAPE, "3.5.3")
	_assert_entry("aof", "mummified_undead", "Royal Legion", "Royal Legion", RANGE_CHARGE_SHAPE, "3.5.3")
	_assert_bands("gf", "high_elf_fleets", ["Agile"], 7, 14, 14)
	_assert_bands("aof", "mummified_undead", ["Royal Legion"], 6, 12, 14)
	assert_int(SoloController.shooting_range_bonus(
		_unit_with(["Royal Legion"], "aof", "mummified_undead"))).is_equal(4)
