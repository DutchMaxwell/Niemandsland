extends GdUnitTestSuite
## W31-F1 follow-up (release 0.3.15): rules the table dropped in books that field them without a mechanics row.
## The placement and the step rules read the registry PER BOOK, while the "is it automated?" test reads the static
## `modeled` list for every book, so the game neither applied the rule nor told the player to do it by hand.
## Every case builds a carrier of the book (system + faction slug, like the army import) and reads the rule through
## the table's own reader: the Vanguard deploy (gate + battle-log line naming the rule), Hit & Run Shooter's step
## pick, the Bounding gate of the activation planner, Quick Throw's lifted Hold need. Each rule has a control book
## that already had its row. The two Aura rules are a not-dropped control: the import expansion grants them by
## name, so they need no row. Rust twin: `core/nml-core/src/tests/unit/v36_data_rows/f1b_rows.rs`.

const VANGUARD_BOOKS := [
	["gf", "prime_brothers"], ["gf", "watch_prime_brothers"], ["gf", "wolf_brothers"], ["gf", "wolf_prime_brothers"],
]

var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()


func _carrier(system: String, book: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "f1b_%s" % book
	u.unit_properties = {"player_id": 2, "name": "Carrier", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": book}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(0, 0, 0.5)
	m.node = n
	u.models.append(m)
	return u


func _solo_for(unit: GameUnit) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {unit.unit_id: unit}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


## Deploy a Vanguard carrier with an objective behind its zone; true when the gate holds and the free placement
## wrote exactly one battle-log line naming the rule (the line exists only when the unit was repositioned).
func _vanguard_logged(system: String, book: String) -> bool:
	var vg := _carrier(system, book, ["Vanguard"])
	var solo := _solo_for(vg)
	var no_block := func(_p: Vector2) -> bool: return false
	solo.deploy_army(Rect2(Vector2(-0.15, 0.3), Vector2(0.30, 0.3)), [Vector2(0.0, 0.66)], no_block, no_block, 7)
	return SoloController.unit_has_vanguard(vg) and solo.vanguard_notes.size() == 1 \
		and str(solo.vanguard_notes[0]).begins_with("Vanguard:")


func test_vanguard_control_book_with_a_row_places_and_logs() -> void:
	assert_bool(_vanguard_logged("gf", "dark_elf_raiders")).is_true()


func test_vanguard_books_without_a_row_place_and_log_it() -> void:
	var dropped: Array = VANGUARD_BOOKS.filter(func(p: Array) -> bool: return not _vanguard_logged(p[0], p[1]))
	assert_array(dropped).override_failure_message("Vanguard silently dropped in: %s" % [dropped]).is_empty()


func test_hit_and_run_shooter_picks_its_step_where_the_book_fields_it() -> void:
	var control := _carrier("gf", "custodian_brothers", ["Hit & Run Shooter"])
	assert_str(_solo_for(control)._hit_and_run_pick(control, true)).is_equal("Hit & Run Shooter")
	var plain := _carrier("gf", "infected_colonies", [])
	assert_str(_solo_for(plain)._hit_and_run_pick(plain, true)).is_equal("")
	var unit := _carrier("gf", "infected_colonies", ["Hit & Run Shooter"])
	assert_str(_solo_for(unit)._hit_and_run_pick(unit, true)).override_failure_message(
		"gf/infected_colonies: Hit & Run Shooter silently dropped").is_equal("Hit & Run Shooter")


func test_bounding_gate_holds_where_the_book_fields_it() -> void:
	assert_bool(RulesRegistry.unit_rule_active(_carrier("aof", "giant_tribes", ["Bounding"]), "Bounding")).is_true()
	assert_bool(RulesRegistry.unit_rule_active(_carrier("aof", "eternal_wardens", []), "Bounding")).is_false()
	assert_bool(RulesRegistry.unit_rule_active(_carrier("aof", "eternal_wardens", ["Bounding"]), "Bounding")) \
		.override_failure_message("aof/eternal_wardens: Bounding silently dropped").is_true()


func test_quick_throw_lifts_the_hold_need_where_the_book_fields_it() -> void:
	assert_str(SoloController.indirect_lift_rule(_carrier("aof", "dragon_empire", ["Quick Throw"]), "los_needs_hold")) \
		.is_equal("Quick Throw")
	assert_str(SoloController.indirect_lift_rule(_carrier("aof", "dwarves", []), "los_needs_hold")).is_equal("")
	for book in ["duchies_of_vinci", "dwarves"]:
		assert_str(SoloController.indirect_lift_rule(_carrier("aof", book, ["Quick Throw"]), "los_needs_hold")) \
			.override_failure_message("aof/%s: Quick Throw silently dropped" % book).is_equal("Quick Throw")


## Not-dropped control: the import expansion grants the aura's base rule by name in a book with no row.
func test_the_two_aura_rules_are_granted_by_name_without_a_row() -> void:
	var jesters := _carrier("gf", "elven_jesters", ["Increased Shooting Range Aura"])
	assert_str(AiEv.aura_granted_rule(jesters, "Increased Shooting Range Aura")).is_equal("Increased Shooting Range")
	var fleets := _carrier("gf", "high_elf_fleets", ["Shred when Shooting Aura"])
	assert_str(AiEv.aura_granted_rule(fleets, "Shred when Shooting Aura")).is_equal("Shred when Shooting")
