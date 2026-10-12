extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.10: the Rules-automation switch is now VISIBLE (RulesAutomation.UI_ENABLED
## flipped on), and its wording is honest about the limit the 08.10 condition demands — rules the engine
## does not model are listed at game start under "apply by hand" and stay manual here. Hidden before the
## flip (the flag was off); the switch only appears where the existing rules-automation gates already
## apply (a local, non-multiplayer game).
##
## Real: scenes/main.tscn, the real _init_solo_panel (run at _ready), the real _add_rules_toggle and its
## tooltip, the RulesAutomation.ui_enabled() flag.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_game_finished = false


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _rules_toggle() -> CheckButton:
	if _main.solo_panel_box == null:
		return null
	for c in _main.solo_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text == "Rules automation":
			return c
	return null


func test_the_ui_flag_is_on() -> void:
	assert_bool(RulesAutomation.ui_enabled()) \
		.override_failure_message("step 2.10 — the rules-automation UI flag is still off") \
		.is_true()


func test_the_switch_is_visible_and_names_the_manual_limit() -> void:
	# The solo panel is built at _ready; the Rules-automation checkbox is added only while the flag is on.
	assert_object(_main.solo_panel_box) \
		.override_failure_message("step 2.10 — the solo panel was not built") \
		.is_not_null()
	_main._add_rules_toggle()
	var cb := _rules_toggle()
	assert_object(cb) \
		.override_failure_message("step 2.10 — the Rules automation switch is not visible") \
		.is_not_null()
	if cb != null:
		assert_bool(cb.visible) \
			.override_failure_message("step 2.10 — the Rules automation switch is hidden") \
			.is_true()
		assert_str(cb.tooltip_text) \
			.override_failure_message("step 2.10 — the switch tooltip does not name the 'apply by hand' limit") \
			.contains("apply by hand")
	await E2EBoot.settle(get_tree())
