extends GdUnitTestSuite
## DAT-09 (0.3.15, rules 3.6): the two Shrouding primitives' own entries carry the 3.6 numbers in
## every GF / AoF book that fields them. Melee Shrouding takes 2" off an enemy charge (was 3"),
## Ranged Shrouding takes 4" off an enemy's shooting range (was 6"); both still stop at the 6" floor.
## The composite names on the same primitive (Shrouded, Shadowborn, Wild Veil, Darkborn) already
## carried 4" / 2" in 3.5 and keep them: they are the controls. The expected numbers are written out
## here, never read back from the map under test; the walk over the books comes from the map, so its
## size is pinned from below and an empty walk cannot pass. Numbers are floats: Godot's JSON parser
## reads every map number as one.

## Minimum number of books per system that hold the entry today (rules 3.6 GF / AoF maps).
const MELEE_BOOKS := {"gf": 15, "aof": 4}
const RANGED_BOOKS := {"gf": 3, "aof": 6}
## One book per system for the seam checks (the table and the AI read the same seam).
const MELEE_SEAM_BOOKS := [["gf", "battle_brothers"], ["aof", "orcs"]]
const RANGED_SEAM_BOOKS := [["gf", "custodian_brothers"], ["aof", "havoc_warriors"]]
## The composite names and a book of each that fields them.
const COMPOSITES := [["gf", "dark_brothers", "Shrouded"], ["gf", "dark_brothers", "Darkborn"],
	["gf", "dark_prime_brothers", "Darkborn"], ["aof", "shadow_stalkers", "Shrouded"],
	["aof", "shadow_stalkers", "Shadowborn"], ["aof", "wood_elves", "Wild Veil"]]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


## A one-model unit of `book` printing `rule` (alive, no attached heroes).
func _carrier(system: String, book: String, rule: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "dat09_%s_%s" % [system, book]
	u.unit_properties = {"player_id": 2, "name": "Carrier", "quality": 4, "defense": 4,
		"game_system": system, "faction_folder": book, "special_rules": [rule]}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## Every book of `system` whose own section holds `rule`.
func _books_with(system: String, rule: String) -> Array:
	var books: Array = []
	var factions: Dictionary = RulesRegistry.map_for(system).get("factions", {})
	for book: String in factions:
		if (factions[book] as Dictionary).has(rule):
			books.append(book)
	return books


func _assert_entry(system: String, book: String, rule: String, key: String, want: float) -> void:
	var entry := RulesRegistry.lookup(system, book, rule)
	assert_str(str(entry.get("primitive", ""))).override_failure_message(
		"%s/%s: %s is not on its own primitive: %s" % [system, book, rule, entry]).is_equal(rule)
	var params: Dictionary = entry.get("params", {})
	assert_float(float(params.get(key, -1.0))).override_failure_message(
		"%s/%s: %s %s is %s, want %s" % [system, book, rule, key, params.get(key), want]) \
		.is_equal_approx(want, 0.001)
	assert_float(float(params.get("floor_in", -1.0))).override_failure_message(
		"%s/%s: %s floor_in moved: %s" % [system, book, rule, params]).is_equal_approx(6.0, 0.001)


func test_every_melee_shrouding_entry_takes_two_inches_off_a_charge() -> void:
	for system: String in MELEE_BOOKS:
		var books := _books_with(system, "Melee Shrouding")
		assert_int(books.size()).override_failure_message(
			"%s: only %d books hold Melee Shrouding" % [system, books.size()]) \
			.is_greater_equal(int(MELEE_BOOKS[system]))
		for book: String in books:
			_assert_entry(system, book, "Melee Shrouding", "move_penalty_in", 2.0)


func test_every_ranged_shrouding_entry_takes_four_inches_off_shooting() -> void:
	for system: String in RANGED_BOOKS:
		var books := _books_with(system, "Ranged Shrouding")
		assert_int(books.size()).override_failure_message(
			"%s: only %d books hold Ranged Shrouding" % [system, books.size()]) \
			.is_greater_equal(int(RANGED_BOOKS[system]))
		for book: String in books:
			_assert_entry(system, book, "Ranged Shrouding", "range_penalty_in", 4.0)


## The seams the table and the AI share read the entry: a 12" charge band against Melee Shrouding
## reaches 10" (and never below 6"), the recorder hands the core [2, 6]; a 24" gun against Ranged
## Shrouding reaches 20" (and never below 6").
func test_the_shared_reach_seams_read_the_new_numbers() -> void:
	for ctx: Array in MELEE_SEAM_BOOKS:
		var ms := _carrier(ctx[0], ctx[1], "Melee Shrouding")
		var where := "%s/%s" % [ctx[0], ctx[1]]
		assert_float(SoloController.melee_shroud_charge_in(12.0, ms)) \
			.override_failure_message("%s: charge band against Melee Shrouding" % where).is_equal_approx(10.0, 0.001)
		assert_float(SoloController.melee_shroud_charge_in(7.0, ms)) \
			.override_failure_message("%s: the 6\" floor" % where).is_equal_approx(6.0, 0.001)
		assert_array(AiActRecorder._melee_shroud_params(ms)) \
			.override_failure_message("%s: recorded shroud pair" % where).is_equal([2.0, 6.0])
	for ctx: Array in RANGED_SEAM_BOOKS:
		var rs := _carrier(ctx[0], ctx[1], "Ranged Shrouding")
		var where := "%s/%s" % [ctx[0], ctx[1]]
		assert_float(SoloController.ranged_shroud_reach_in(24.0, rs)) \
			.override_failure_message("%s: gun reach against Ranged Shrouding" % where).is_equal_approx(20.0, 0.001)
		assert_float(SoloController.effective_shoot_reach_in(9.0, rs)) \
			.override_failure_message("%s: the 6\" floor" % where).is_equal_approx(6.0, 0.001)
		assert_float(float(SoloController.ranged_shroud_spec(rs).get("range_penalty_in", -1.0))) \
			.override_failure_message("%s: the logged penalty" % where).is_equal_approx(4.0, 0.001)


## CONTROL (passes with and without the change): the composite names keep 4" off shooting and 2"
## off a charge, both floored at 6".
func test_control_the_composite_names_keep_four_and_two() -> void:
	for row: Array in COMPOSITES:
		var entry := RulesRegistry.lookup(row[0], row[1], row[2])
		var where := "%s/%s %s" % [row[0], row[1], row[2]]
		assert_str(str(entry.get("primitive", ""))).override_failure_message(where).is_equal("Ranged Shrouding")
		var params: Dictionary = entry.get("params", {})
		for key: String in ["range_penalty_in", "melee_move_penalty_in", "floor_in", "melee_floor_in"]:
			var want := {"range_penalty_in": 4.0, "melee_move_penalty_in": 2.0}.get(key, 6.0) as float
			assert_float(float(params.get(key, -1.0))).override_failure_message(
				"%s: %s = %s" % [where, key, params.get(key)]).is_equal_approx(want, 0.001)
		var u := _carrier(row[0], row[1], row[2])
		assert_float(SoloController.ranged_shroud_reach_in(24.0, u)).override_failure_message(where) \
			.is_equal_approx(20.0, 0.001)
		assert_float(SoloController.melee_shroud_charge_in(12.0, u)).override_failure_message(where) \
			.is_equal_approx(10.0, 0.001)
