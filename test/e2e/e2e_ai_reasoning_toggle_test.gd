extends GdUnitTestSuite
## NML-1084 — the AI log can be switched on from the left menu again.
##
## The toggle used to be hidden behind OS.is_debug_build() / NML_AI_TRACE=1. gdUnit itself runs a
## DEBUG build, so a visibility assertion alone would be green either way; the truth table of the
## predicate is therefore asserted for the case that was broken — a released build with no env var,
## which is exactly what the maintainer plays — plus the real panel, which must offer the entry and
## must actually flip the flag the battle-log rendering reads.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MainScript := preload("res://scripts/main.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The entry is offered in EVERY build, with or without the env var — the released build with neither
## is the case the maintainer hit, where the left menu simply had no such entry.
func test_the_toggle_is_offered_in_a_released_build_without_the_env_var() -> void:
	assert_bool(MainScript.ai_reasoning_toggle_visible(false, "")) \
		.override_failure_message("a released build offers no AI-reasoning toggle — the AI log cannot be switched on at all") \
		.is_true()
	assert_bool(MainScript.ai_reasoning_toggle_visible(false, "1")).is_true()
	assert_bool(MainScript.ai_reasoning_toggle_visible(true, "")).is_true()


func _find_ai_reasoning_toggle() -> CheckButton:
	for c in _main.solo_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text.begins_with("AI reasoning"):
			return c
	return null


## The real left-menu panel: the entry is there, visible, and toggling it arms the AI-log rendering.
func test_the_left_menu_shows_the_entry_and_it_arms_the_ai_log() -> void:
	_main.opr_army_manager.armies = {1: null, 2: null}
	_main._refresh_solo_panel()
	var cb := _find_ai_reasoning_toggle()
	assert_object(cb) \
		.override_failure_message("no AI-reasoning entry in the left menu's solo panel") \
		.is_not_null()
	assert_bool(cb.visible).is_true()
	assert_bool(_main._solo_dev).is_false()   # off by default: rendering costs nothing until asked
	cb.button_pressed = true
	cb.toggled.emit(true)
	assert_bool(_main._solo_dev).is_true()
