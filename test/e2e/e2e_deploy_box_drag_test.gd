extends GdUnitTestSuite
## Community #159: the deployment control box covered the unit cards with no way to move
## it. It is now DRAGGABLE. This suite boots the REAL scenes/main.tscn, shows the real
## hand-over panel and drags it with synthetic events, asserting: (1) the default spot is
## the familiar bottom-centre (NML-226 clearance), (2) a drag moves it and the player's
## spot survives the next hand-over (the panel is reused, never rebuilt), (3) the clamp
## keeps it fully on-screen no matter how far the drag overshoots.

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


## One synthetic press → motion → release through the panel's real drag handler.
func _drag(dx: float, dy: float) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_main._solo_deploy_ui_drag(press)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(dx, dy)
	_main._solo_deploy_ui_drag(move)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_main._solo_deploy_ui_drag(release)


func test_deploy_box_is_draggable_and_keeps_its_spot() -> void:
	_main._solo_deploy_ui_show("Deploy a unit", "OK", Callable())
	await _runner.simulate_frames(2)   # the deferred relayout has run
	var panel: PanelContainer = _main._solo_deploy_ui_panel
	assert_object(panel).is_not_null()
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size
	# Default spot: bottom-centre, 54 px above the Units tab (NML-226 clearance).
	assert_float(panel.position.x).is_equal_approx((vp.x - panel.size.x) * 0.5, 2.0)
	assert_float(panel.position.y).is_equal_approx(vp.y - panel.size.y - 54.0, 2.0)
	var before: Vector2 = panel.position
	_drag(-120.0, -200.0)
	assert_float(panel.position.x).is_equal_approx(before.x - 120.0, 2.0)
	assert_float(panel.position.y).is_equal_approx(before.y - 200.0, 2.0)
	# The player's spot SURVIVES the next hand-over text (panel reuse, no rebuild).
	var moved: Vector2 = panel.position
	_main._solo_deploy_ui_show("Next unit — a longer two-line hand-over text for re-min-size", "OK", Callable())
	await _runner.simulate_frames(2)
	assert_float(panel.position.x).is_equal_approx(moved.x, 2.0)
	assert_float(panel.position.y).is_equal_approx(moved.y, 2.0)


func test_deploy_box_clamps_to_the_screen() -> void:
	_main._solo_deploy_ui_show("Deploy a unit", "OK", Callable())
	await _runner.simulate_frames(2)
	var panel: PanelContainer = _main._solo_deploy_ui_panel
	_drag(-99999.0, -99999.0)
	assert_float(panel.position.x).is_equal_approx(0.0, 0.5)
	assert_float(panel.position.y).is_equal_approx(0.0, 0.5)
