extends GdUnitTestSuite
## Feature test FT-20: one command upgrade of each kind per AoF: Skirmish army, at import. AS36 p.13 l.1179-1180: each army
## may only have one model with each of Sergeant / Musician / Banner.
## Scene: an aofs table, the own-stats fixture card_list_aofs_own_stats_two_banners.json (two units with a Banner), imported
## through the real import door, then battle start.
## FINDING #3862 (R-FT2): no line at import or at battle start; both Banners get command picks. The book case stays here,
## skipped with that issue; its red state unskipped is the proof it can fail (there is no table check to plant against).
## Real: the main scene, the table system switch, the import door, battle start and its command picks.

const FIXTURE := "res://test/fixtures/card_list_aofs_own_stats_two_banners.json"

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


@warning_ignore("unused_parameter")
func test_a_second_banner_is_named_by_battle_start(timeout := 120000, do_skip := true,
		skip_reason := "FINDING #3862: a second Banner in an aofs list imports and plays silently") -> void:
	assert_bool(_t.main.set_table_system("aofs", "P1")).is_true()
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	await _t.import_list(FIXTURE, 1)
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	await _t.runner.simulate_frames(4)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Second Band") != -1 and l.find("only one Banner") != -1)) \
		.override_failure_message("one line names the second Banner: %s" % [_t.lines]).is_true()
