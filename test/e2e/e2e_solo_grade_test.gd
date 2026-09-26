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
	await _mount()


## Mount a fresh scenes/main.tscn — the second call in one test is a game RESTART (same saved file).
func _mount() -> void:
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


## Start Game without the guided deployment: NACHTMAHR takes its seat at the first activation, and the
## line comes the moment it does (not never, not twice).
func test_a_game_started_before_nachtmahr_sits_down_logs_it_on_arrival(timeout := 120000) -> void:
	await _boot("finsternis")
	_main.solo_ai_slots = {2: true}
	_main.opr_army_manager.start_game()
	await E2EBoot.settle(get_tree())
	assert_array(_grade_lines()).is_empty()
	_main._ensure_solo_controller()
	assert_array(_grade_lines()).contains_exactly(["NACHTMAHR — Finsternis (decision tree)"])


# === Step 2 — the picker in the AI row of the real left-menu solo panel ===

func _ai_checkbox(pid: int) -> CheckButton:
	for c in _main.solo_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text.begins_with("AI plays P%d" % pid):
			return c
	return null


func _grade_option() -> OptionButton:
	for c in _main.solo_panel_box.get_children():
		if c is OptionButton and (c as OptionButton).item_count > 0 and str((c as OptionButton).get_item_metadata(0)) == "daemmerung":
			return c
	return null


## Two imported armies, the player ticks "AI plays P2" (the panel rebuilds deferred).
func _panel_with_ai_on_p2() -> void:
	_main.opr_army_manager.armies = {1: null, 2: null}
	_main._refresh_solo_panel()
	var cb := _ai_checkbox(2)
	if cb != null:
		cb.button_pressed = true
	await E2EBoot.settle(get_tree())


func test_the_ai_row_offers_the_five_grades_with_descriptions(timeout := 120000) -> void:
	await _boot("")
	await _panel_with_ai_on_p2()
	var opt := _grade_option()
	assert_object(opt).override_failure_message("no grade picker in the solo panel").is_not_null()
	if opt == null:
		return
	assert_int(opt.get_index()).override_failure_message("the picker is not in P2's AI row").is_equal(_ai_checkbox(2).get_index() + 1)
	var texts: Array = []
	for i in opt.item_count:
		texts.append(opt.get_item_text(i))
	assert_array(texts).contains_exactly([
		"Dämmerung — still learning; makes visible mistakes",
		"Zwielicht — plays solidly, misses some chances",
		"Finsternis — plays the rules hard and punishes mistakes",
		"Albtraum — " + ("on macOS still without Erlkönig" if OS.get_name() == "macOS" else "Erlkönig: thinks several moves ahead"),
		"NACHTMAHR — coming"])
	assert_bool(opt.is_item_disabled(4)).override_failure_message("NACHTMAHR is selectable").is_true()
	assert_bool(opt.is_item_disabled(3)).is_false()
	assert_int(opt.selected).override_failure_message("the default is not Albtraum").is_equal(3)


## Picker polish (maintainer 26.09.2026): closed, the dropdown shows ONLY the grade name; the one-line
## description lives in the opened list and in the tooltip.
func test_the_closed_picker_shows_only_the_grade_name(timeout := 120000) -> void:
	await _boot("")
	await _panel_with_ai_on_p2()
	var opt := _grade_option()
	assert_object(opt).override_failure_message("no grade picker in the solo panel").is_not_null()
	if opt == null:
		return
	var albtraum := SoloGrade.description("albtraum", OS.get_name() == "macOS")
	assert_str(opt.text).is_equal("Albtraum")
	assert_str(opt.tooltip_text).contains(albtraum)
	assert_str(opt.get_item_text(3)).is_equal("Albtraum — " + albtraum)   # the opened list keeps the line
	opt.select(1)
	opt.item_selected.emit(1)   # the player picks Zwielicht
	assert_str(opt.text).is_equal("Zwielicht")
	assert_str(opt.tooltip_text).contains("plays solidly, misses some chances")


func test_a_picked_grade_plays_logs_and_survives_a_restart(timeout := 180000) -> void:
	await _boot("")
	await _panel_with_ai_on_p2()
	var opt := _grade_option()
	assert_object(opt).override_failure_message("no grade picker in the solo panel").is_not_null()
	if opt == null:
		return
	opt.select(1)
	opt.item_selected.emit(1)   # the player picks Zwielicht
	# "Start Deployment" seats NACHTMAHR first (main.gd _on_solo_deploy_pressed -> _ensure_solo_controller);
	# the end of the deployment flips the game to PLAYING.
	_main._ensure_solo_controller()
	var d: SoloDifficulty = _main.solo_controller.difficulty_by_slot.get(2, null)
	assert_str(d.grade_name if d != null else "none").is_equal("zwielicht")
	_main.opr_army_manager.start_game()
	await E2EBoot.settle(get_tree())
	assert_array(_grade_lines()).contains_exactly(["NACHTMAHR — Zwielicht (decision tree)"])
	# Restart: a fresh main.tscn on the same saved file shows the downshift still selected.
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	await _mount()
	assert_str(_main._solo_interactive_grade).is_equal("zwielicht")
	await _panel_with_ai_on_p2()
	var again := _grade_option()
	assert_int(again.selected if again != null else -1).override_failure_message("Zwielicht was not remembered").is_equal(1)
