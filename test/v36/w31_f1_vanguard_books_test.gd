extends GdUnitTestSuite
## W31-F1 (release 0.3.15): a unit that carries Vanguard in a book whose mechanics section has no Vanguard row was
## silently dropped by the table. Its placement is registry-gated PER BOOK (`unit_rule_active` /
## `unit_has_vanguard`), while the "is it automated?" test reads the static `modeled` list for EVERY book, so the
## game neither placed the unit nor told the player to do it by hand. Each case deploys a real Vanguard carrier of
## the book with an objective BEHIND its zone and asks for two things: the placement gate holds, and the free
## placement wrote its battle-log line naming the book rule (the line exists only when the unit was actually
## repositioned; plain zone placement already lands near that objective, so the position proves nothing). The
## control book already had its row; the others are the books that fielded the rule without one. Table twin of
## `core/nml-core/src/tests/unit/v36_data_rows/w31_f1.rs`.

const CONTROL := [["gf", "dark_elf_raiders"]]
const BOOKS_WITHOUT_ROW := [
	["gf", "battle_brothers"], ["gf", "blood_brothers"], ["gf", "blood_prime_brothers"],
	["gf", "dark_prime_brothers"], ["gf", "infected_colonies"], ["gf", "knight_prime_brothers"],
	["gf", "rebel_guerrillas"], ["gf", "saurian_starhosts"],
	["aof", "dwarves"], ["aof", "saurians"],
]

var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()


func _vanguard_carrier(system: String, book: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "w31f1_%s" % book
	u.unit_properties = {"player_id": 2, "name": "Speeder", "quality": 4, "defense": 4,
		"special_rules": ["Vanguard"], "game_system": system, "faction_folder": book}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(0, 0, 0.5)
	m.node = n
	u.models.append(m)
	return u


## Deploy the carrier in a strip at the south edge with an objective behind it; {gate, notes}.
func _deploy(system: String, book: String) -> Dictionary:
	var vg := _vanguard_carrier(system, book)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {vg.unit_id: vg}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var zone := Rect2(Vector2(-0.15, 0.3), Vector2(0.30, 0.3))
	var no_block := func(_p: Vector2) -> bool: return false
	solo.deploy_army(zone, [Vector2(0.0, 0.66)], no_block, no_block, 7)
	return {"notes": solo.vanguard_notes.duplicate(), "gate": SoloController.unit_has_vanguard(vg)}


func _dropped(pairs: Array) -> Array:
	var dropped: Array = []
	for p in pairs:
		var r := _deploy(str(p[0]), str(p[1]))
		var logged := (r["notes"] as Array).size() == 1 and str((r["notes"] as Array)[0]).begins_with("Vanguard:")
		if not (bool(r["gate"]) and logged):
			dropped.append("%s/%s (gate=%s notes=%s)" % [p[0], p[1], r["gate"], r["notes"]])
	return dropped


func test_control_book_with_a_row_places_and_logs() -> void:
	assert_array(_dropped(CONTROL)).is_empty()


func test_books_that_field_vanguard_place_and_log_it() -> void:
	assert_array(_dropped(BOOKS_WITHOUT_ROW)).override_failure_message(
		"Vanguard silently dropped in: %s" % [_dropped(BOOKS_WITHOUT_ROW)]).is_empty()
