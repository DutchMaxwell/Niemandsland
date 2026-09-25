extends GdUnitTestSuite
## E2E — a caster's faction spell list through save -> load on the REAL scenes/main.tscn (the player's
## bug: "after loading my save the casts dialog / unit card / unit dock show no spells; a friend joining
## my MP game sees theirs fine"). All three views read OPRArmyManager.get_spells_for_unit(), which for a
## loaded unit (no OPRArmy) is the per-player session cache — filled from the save's player_spells on a
## join, never on a load. And the cache outlived the table: the list of the previous game was served to
## the next table's caster of the same player_id when its save carried none.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const SPELLS: Array = [
	{"name": "Fireball", "threshold": 2, "effect": "Target enemy unit within 12\" takes 6 hits."},
	{"name": "Shield", "threshold": 1, "effect": "Target friendly unit within 12\" gets Regeneration."},
]
const OLD_SPELLS: Array = [{"name": "Stale Bolt", "threshold": 1, "effect": "From the previous game."}]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _tmp_saves: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	for p in _tmp_saves:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p)))
	_tmp_saves.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## What the spell list looks like after the JSON hop of a save file (ints come back as floats).
func _after_json(spells: Array) -> Array:
	return JSON.parse_string(JSON.stringify(spells))


func _caster(pid: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"name": "Mage", "player_id": pid, "special_rules": ["Caster(2)"]}
	return u


func _tmp_save_path() -> String:
	var path := "user://e2e_save_load_spells_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	return path


func test_a_loaded_save_shows_the_casters_spells() -> void:
	var mgr = _main.opr_army_manager
	mgr.merge_player_spells({1: SPELLS})
	var path := _tmp_save_path()
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	# A new app session starts with an empty cache; only the save can bring the list back.
	mgr._session_spells.clear()

	await _main.save_manager.load_game(path)
	await _runner.simulate_frames(2)

	assert_array(mgr.get_spells_for_unit(_caster(1))) \
		.override_failure_message("after the load the caster's spell list is empty — the save carries "
			+ "player_spells but load_game never merges it back (the MP join does)") \
		.is_equal(_after_json(SPELLS))
	await E2EBoot.settle(get_tree())


func test_a_loaded_save_replaces_the_previous_games_spell_lists() -> void:
	var mgr = _main.opr_army_manager
	# The save on disk comes from a game whose player 1 fields no spell book.
	var path := _tmp_save_path()
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	# Meanwhile this session played a game with a caster (its list sits in the cache), then loads it.
	mgr.merge_player_spells({1: OLD_SPELLS})

	await _main.save_manager.load_game(path)
	await _runner.simulate_frames(2)

	assert_array(mgr.get_spells_for_unit(_caster(1))) \
		.override_failure_message("the previous game's spell list survived the load and is served to "
			+ "the loaded table's caster of player 1") \
		.is_empty()
	await E2EBoot.settle(get_tree())
