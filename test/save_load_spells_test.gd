extends GdUnitTestSuite
## A caster's faction spell list through save -> load (the player's bug: "after loading my save the
## casts dialog / unit card / unit dock show no spells; a friend joining my MP game sees theirs fine").
##
## All three views read ONE seam, OPRArmyManager.get_spells_for_unit(): the unit's OPRArmy.spells,
## else the per-player session cache. A loaded save rebuilds no OPRArmy, so the cache is the only
## source — the save WRITES it (player_spells) and the MP join MERGES it back, but load_game never did.
## The cache also outlived the table: clear_all() (what every load, join and Clear Table runs first)
## dropped the armies but kept the lists, so the NEXT table's caster of the same player_id was served
## the previous game's spells whenever its own save carried none.

const SPELLS: Array = [
	{"name": "Fireball", "threshold": 2, "effect": "Target enemy unit within 12\" takes 6 hits."},
	{"name": "Shield", "threshold": 1, "effect": "Target friendly unit within 12\" gets Regeneration."},
]

var _tmp_saves: Array = []


func after_test() -> void:
	for p in _tmp_saves:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p)))
	_tmp_saves.clear()


## What the spell list looks like after the JSON hop of a save file (ints come back as floats).
func _after_json(spells: Array) -> Array:
	return JSON.parse_string(JSON.stringify(spells))


func _caster(pid: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"name": "Mage", "player_id": pid, "special_rules": ["Caster(2)"]}
	return u


func _save_manager_over(am: OPRArmyManager) -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)
	sm.army_manager = am
	return sm


func test_a_loaded_save_restores_the_casters_spell_list() -> void:
	# Session 1: a caster's faction spell list is on the table (as a load / MP join leaves it), saved.
	var session1: OPRArmyManager = auto_free(OPRArmyManager.new())
	session1.merge_player_spells({1: SPELLS})
	var sm1 := _save_manager_over(session1)
	var path := "user://test_save_load_spells_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(sm1.save_game(path)).is_equal(OK)
	sm1.queue_free()

	# Session 2: a fresh game (new OPRArmyManager, empty caches) loads that save.
	var session2: OPRArmyManager = auto_free(OPRArmyManager.new())
	var sm2 := _save_manager_over(session2)
	var err: Error = await sm2.load_game(path)
	assert_int(err).is_equal(OK)

	assert_array(session2.get_spells_for_unit(_caster(1))) \
		.override_failure_message("after the load the caster's spell list is empty — the save carries "
			+ "player_spells but load_game never merges it back (the MP join does)") \
		.is_equal(_after_json(SPELLS))
	sm2.queue_free()


func test_clearing_the_table_forgets_the_session_spell_lists() -> void:
	var am: OPRArmyManager = auto_free(OPRArmyManager.new())
	am.merge_player_spells({1: SPELLS})

	am.clear_all()

	assert_array(am.get_spells_for_unit(_caster(1))) \
		.override_failure_message("a cleared table still serves the previous game's spell list to the "
			+ "next caster of player 1") \
		.is_empty()
