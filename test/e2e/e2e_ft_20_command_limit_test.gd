extends GdUnitTestSuite
## Feature test FT-20: one command upgrade of each kind per AoF: Skirmish army, at import. AS36 p.13 l.1179-1180: each army
## may only have one model with each of Sergeant / Musician / Banner.
## Scene: an aofs table, the own-stats fixture card_list_aofs_own_stats_two_banners.json (two units with a Banner), imported
## through the real import door, then battle start.
## #3862 (fixed, O-FT-1): the import writes one warning line from the core's command limit (a warning, never a refusal).
## Real: the main scene, the table system switch, the import door, battle start and its command picks.

const FIXTURE := "res://test/fixtures/card_list_aofs_own_stats_two_banners.json"

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


## #3862 (O-FT-1): the import warns with one line naming the second Banner and the book page; the list still plays.
func test_a_second_banner_is_named_by_battle_start(timeout := 120000) -> void:
	assert_bool(_t.main.set_table_system("aofs", "P1")).is_true()
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	await _t.import_list(FIXTURE, 1)
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	await _t.runner.simulate_frames(4)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Second Band") != -1 and l.find("only one Banner") != -1)) \
		.override_failure_message("one line names the second Banner: %s" % [_t.lines]).is_true()
