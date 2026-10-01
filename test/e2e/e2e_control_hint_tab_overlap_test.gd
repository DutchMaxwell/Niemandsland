extends GdUnitTestSuite
## E2E — uifix2 (30.09.): the contextual hover hint line sat on top of the bottom "Units" tab. The tab
## must stay clickable and readable, so the two rects must not meet — dock closed or open.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _show_hint() -> Control:
	var hints: Node = _main.get_node("ControlHintsController")
	hints._pending_text = ControlHintsController.hint_for("unit")
	hints._on_dwell()
	return hints._panel


func test_hint_line_leaves_the_units_tab_free() -> void:
	var panel := _show_hint()
	await _runner.simulate_frames(6)
	assert_bool(panel.is_visible_in_tree()).is_true()
	var tab: Rect2 = _main.unit_dock.tab_rect()
	var hint := panel.get_global_rect()
	assert_bool(tab.intersects(hint)) \
		.override_failure_message("the hint line %s sits on the Units tab %s" % [hint, tab]) \
		.is_false()


func test_hint_line_leaves_the_tab_free_with_the_dock_open() -> void:
	var panel := _show_hint()
	_main.unit_dock._toggle_dock()
	await _runner.simulate_frames(40)   # the 0.2 s dock tween settles
	var tab: Rect2 = _main.unit_dock.tab_rect()
	var hint := panel.get_global_rect()
	assert_bool(tab.intersects(hint)) \
		.override_failure_message("the hint line %s sits on the open dock's tab %s" % [hint, tab]) \
		.is_false()
