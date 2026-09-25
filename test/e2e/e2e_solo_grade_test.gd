extends GdUnitTestSuite
## E2E — the NACHTMAHR difficulty ladder (grill 25.09.2026, NML-1018): the saved `solo_grade` setting
## decides the grade the real scenes/main.tscn plays, the game start logs ONE battle-log line naming
## grade + brain, and without a saved setting the game plays exactly today's Albtraum.
##
## Real: scenes/main.tscn with its real _ready(), the real SoloController and BattleLog, the real
## game-phase seam (OPRArmyManager.start_game -> game_phase_changed). Constructed: the saved setting
## file, under a test path (never the player's own user://solo.cfg).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const CFG := "user://e2e_solo_grade_test.cfg"
const OVERRIDE := "niemandsland/solo_cfg_override"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func _boot(saved_grade: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	if not saved_grade.is_empty():
		var cfg := ConfigFile.new()
		cfg.set_value("solo", "solo_grade", saved_grade)
		cfg.save(CFG)
	ProjectSettings.set_setting(OVERRIDE, CFG)
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	ProjectSettings.set_setting(OVERRIDE, "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	_main = null
	_runner = null


func _grade_lines() -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.begins_with("NACHTMAHR — "):
			out.append(t)
	return out


func _seat_ai() -> SoloDifficulty:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	return _main.solo_controller.difficulty_by_slot.get(2, null)


## Today's behaviour pinned (control, green before the ladder): no saved setting -> the "nachtmahr"
## pin, resolved to Erlkönig with core + brain up, else the tree ceiling.
func test_without_a_saved_grade_the_game_plays_todays_albtraum(timeout := 120000) -> void:
	await _boot("")
	assert_str(_main._solo_interactive_grade).is_equal("nachtmahr")
	var d := _seat_ai()
	var ran := SoloDifficulty.preset_for_nachtmahr(BattleSim.core_enabled(), _main.solo_controller.shipped_brain_ready())
	assert_str(d.grade_name).is_equal(ran)
	await E2EBoot.settle(get_tree())


func test_game_start_logs_albtraum_and_its_brain_once(timeout := 120000) -> void:
	await _boot("")
	var d := _seat_ai()
	var want := "NACHTMAHR — Albtraum (Erlkönig)" if d.planner else "NACHTMAHR — Albtraum (decision tree%s)" % (
		" — on macOS still without Erlkönig" if OS.get_name() == "macOS" else "")
	_main.opr_army_manager.start_game()
	await E2EBoot.settle(get_tree())
	assert_array(_grade_lines()).contains_exactly([want])


func test_a_saved_grade_decides_the_game_and_its_start_line(timeout := 120000) -> void:
	await _boot("zwielicht")
	assert_str(_main._solo_interactive_grade).is_equal("zwielicht")
	var d := _seat_ai()
	assert_str(d.grade_name if d != null else "none").is_equal("zwielicht")
	assert_bool(d != null and d.planner).override_failure_message("Zwielicht routed through the planner").is_false()
	assert_array(_grade_lines()).override_failure_message("logged before the game started").is_empty()
	_main.opr_army_manager.start_game()
	await E2EBoot.settle(get_tree())
	assert_array(_grade_lines()).contains_exactly(["NACHTMAHR — Zwielicht (decision tree)"])
	_main._solo_apply_difficulty()   # a mid-game re-apply (controller rebuild) does not repeat it
	assert_int(_grade_lines().size()).is_equal(1)
