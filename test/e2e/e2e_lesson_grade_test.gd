extends GdUnitTestSuite
## E2E — lesson grade pin (tutorial D4): a Game School scenario always plays the gentlest ladder
## grade (Dämmerung), pinned in memory only. Booting a chapter must never rewrite the player's
## saved ladder grade.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const GRADE_CFG := "user://test_lesson_grade.cfg"
const PROGRESS_CFG := "user://test_lesson_grade_progress.cfg"
const FLAGS := ["niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/pending_load_path"]

var _saved: Dictionary = {}
var _root_before: Array
var _runner: GdUnitSceneRunner
var _main: Node


func before_test() -> void:
	_root_before = Boot.root_children(get_tree())
	for flag in FLAGS:
		_saved[flag] = ProjectSettings.get_setting(flag)
	var cfg := ConfigFile.new()
	cfg.set_value("solo", "solo_grade", "finsternis")
	cfg.save(GRADE_CFG)
	ProjectSettings.set_setting("niemandsland/solo_cfg_override", GRADE_CFG)
	ProjectSettings.set_setting("niemandsland/scenario_mode", true)
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-03").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-03")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	_main._lesson_progress_path = PROGRESS_CFG
	await _main.save_manager.load_completed


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	ProjectSettings.set_setting("niemandsland/solo_cfg_override", "")
	for path in [GRADE_CFG, PROGRESS_CFG]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_lesson_pins_daemmerung_without_writing_the_saved_grade(timeout := 60000) -> void:
	assert_str(_main._solo_interactive_grade).is_equal("daemmerung")
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	_main._solo_log_grade()
	var text := ""
	for entry in _main.battle_log.entries():
		text += str((entry as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("the lesson grade line must name Dämmerung (log: %s)" % text.strip_edges()) \
		.contains("Dämmerung")
	var cfg := ConfigFile.new()
	cfg.load(GRADE_CFG)
	assert_str(str(cfg.get_value("solo", "solo_grade", ""))).is_equal("finsternis")
	await Boot.settle(get_tree())
