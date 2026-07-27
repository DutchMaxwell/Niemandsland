extends GdUnitTestSuite
## E2E — DEFECT 2: clicks on menus fell THROUGH to the 3D battlefield.
##
## The maintainer: "durchklickt auf das Spielfeld … anstatt der Aktivierung des Buttons". World picking
## ran in _input, i.e. BEFORE the GUI got the event, so a click on the menu did both: it worked the
## button AND box-selected the table underneath. The fix moved picking to _unhandled_input, which makes
## occlusion the ENGINE's decision — and therefore only observable by running the engine's real
## dispatch chain (_input -> Control._gui_input -> _unhandled_input) over the REAL live tree.
##
## test/ui_click_ownership_test.gd stays as the cheap first line: it pins mouse_filter on the stored
## scenes/main.tscn. It structurally CANNOT cover this, for two reasons:
##   - it never adds the scene to a tree, so nothing is ever dispatched, and
##   - the controls that matter most are BUILT IN _ready() (AiOpponentBtn at main.gd:606, unit_dock at
##     :597, _terrain_mode_btn at :10071) and so do not exist in the .tscn at all.
##
## WHAT THIS SUITE DRIVES: everything real. The real scene, the real _ready(), the real hamburger
## open/close animation, real InputEventMouseButton/Motion pushed through the real Viewport, the real
## Godot GUI pipeline, the real ObjectManager and its real camera-unproject + physics raycast. Nothing
## is stubbed. Constructed: only the choice of click coordinates, which are derived from the live
## widgets' own rects at runtime rather than hardcoded, so a scene edit moves them with it.
##
## THE OBSERVABLE: ObjectManager._is_box_selecting (object_manager.gd:109). A left press that survives
## to _unhandled_input over open table starts a box selection; if the GUI owned the click it never does.
## Binary, needs no rendering.
##
## COORDINATES: headless the window is 1280x720 while the project stretches to 1920x1080, so Control
## rects (canvas space) and InputEvent positions (screen space) differ by a factor of 1.5. E2EBoot's
## click helper applies get_screen_transform(); without it every click here silently lands on a
## NEIGHBOURING widget and the suite passes while testing nothing.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	# _on_intro_finished is call_deferred by the harness branch and reveals $UI; containers only lay
	# out once they are visible in tree, so the frames here are what makes the rects below real.
	await _runner.simulate_frames(10)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _om() -> Node:
	return _main.object_manager


func _vp() -> Viewport:
	return _main.get_viewport()


## Open the hamburger menu and let its 0.2 s fade-in finish. The panel is deliberately IGNORE while it
## is still transparent (an invisible surface over the table is a click-eater) and only becomes STOP in
## the tween's callback — so a test that clicks too early measures the wrong state.
func _open_menu() -> Control:
	_main._on_hamburger_pressed()
	await get_tree().create_timer(0.35).timeout
	await _runner.simulate_frames(2)
	var scroll: Control = _main.left_panel_scroll
	assert_bool(scroll.visible).is_true()
	assert_int(scroll.mouse_filter) \
		.override_failure_message("the open menu is not MOUSE_FILTER_STOP — every gap and label band in it leaks clicks to the table") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	return scroll


## A full press/release at a canvas point, with the box-selection flag read at the PRESS (the release
## finishes the box, clearing the flag again).
func _click_and_report_box_select(canvas_pos: Vector2) -> bool:
	(_om() as Object).set("_is_box_selecting", false)
	E2EBoot.click_canvas(_vp(), canvas_pos, true)
	var started: bool = bool((_om() as Object).get("_is_box_selecting"))
	E2EBoot.click_canvas(_vp(), canvas_pos, false)
	await _runner.simulate_frames(1)
	return started


func _all_buttons(root: Node, out: Array) -> void:
	if root is Button and (root as Button).is_visible_in_tree():
		out.append(root)
	for c in root.get_children():
		_all_buttons(c, out)


## A canvas point INSIDE the open menu that no Button covers — the padding/label band that used to leak.
## Found at runtime by scanning the panel's own rect, so a menu redesign cannot silently invalidate it.
func _point_in_menu_off_any_button(scroll: Control) -> Vector2:
	var buttons: Array = []
	_all_buttons(scroll, buttons)
	assert_int(buttons.size()) \
		.override_failure_message("the open menu contains no visible Button — the scan below would be meaningless") \
		.is_greater(0)
	var rect := scroll.get_global_rect()
	var y := rect.position.y + 2.0
	while y < rect.end.y - 2.0:
		var p := Vector2(rect.position.x + rect.size.x * 0.5, y)
		var covered := false
		for b in buttons:
			if (b as Button).get_global_rect().has_point(p):
				covered = true
				break
		if not covered and _claims_recursive(scroll.get_node("LeftPanelVBox"), p):
			return p          # a gap/label band INSIDE the button column
		y += 2.0
	return Vector2.INF


## A canvas point that `ctl` ALONE claims — inside its rect, but on none of its descendants. This is the
## only kind of point at which `ctl`'s OWN mouse_filter decides the outcome; anywhere a STOP child
## covers, the child answers and the parent's filter is untestable. Scanned bottom-up because that is
## where a container's empty tail lives.
func _point_owned_only_by(ctl: Control) -> Vector2:
	var rect := ctl.get_global_rect()
	var y := rect.end.y - 4.0
	while y > rect.position.y + 2.0:
		var p := Vector2(rect.position.x + rect.size.x * 0.5, y)
		var covered_by_content := false
		for c in ctl.get_children():
			if _claims_recursive(c, p):
				covered_by_content = true
				break
		if not covered_by_content:
			return p
		y -= 4.0
	return Vector2.INF


## The menu's EMPTY TAIL — the region the fix's own comment names ("the empty tail below the last
## button is menu, not table"). Measured live: 232 x 163 px at 1080p.
func _point_in_menu_tail(scroll: Control) -> Vector2:
	return _point_owned_only_by(scroll)


## Is any click-claiming Control sitting over this canvas point? (Viewport.gui_find_control is not
## exposed to GDScript in 4.6, so the walk is explicit: visible in tree, not MOUSE_FILTER_IGNORE, rect
## contains the point.) Used only to CHOOSE coordinates — never as an assertion, since asserting on it
## would just restate the mouse_filter values the static suite already pins.
func _ui_claims(canvas_pos: Vector2) -> bool:
	# $UI is a CanvasLayer, not a Control — walk from the node itself, not from a cast.
	return _claims_recursive(_main.get_node("UI"), canvas_pos)


func _claims_recursive(node: Node, p: Vector2) -> bool:
	var ctl := node as Control
	if ctl != null:
		if not ctl.is_visible_in_tree():
			return false
		if ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctl.get_global_rect().has_point(p):
			return true
	for c in node.get_children():
		if _claims_recursive(c, p):
			return true
	return false


## A canvas point over OPEN TABLE: inside the HUD's own rect (it spans the whole canvas), outside the
## menu, and clear of every click-claiming Control. Scanned at runtime, not hardcoded.
func _point_on_open_table(scroll: Control) -> Vector2:
	var hud := _main.get_node("UI/HUD") as Control
	var rect := hud.get_global_rect()
	for fy in [0.62, 0.70, 0.52, 0.44, 0.80]:
		for fx in [0.72, 0.62, 0.80, 0.50, 0.88]:
			var p := rect.position + Vector2(rect.size.x * float(fx), rect.size.y * float(fy))
			if scroll.visible and scroll.get_global_rect().has_point(p):
				continue
			if not _ui_claims(p):
				return p
	return Vector2.INF


# ===== The positive control, first =====
# Without it every assertion below would also pass on a scene where input is completely dead — which
# is precisely the state a modal dialog or a full-rect STOP holder produces (URGENT-024).

func test_a_click_on_open_table_reaches_the_battlefield(timeout := 120000) -> void:
	var scroll := await _open_menu()
	var table_pt := _point_on_open_table(scroll)
	assert_vector(table_pt).is_not_equal(Vector2.INF)

	var started: bool = await _click_and_report_box_select(table_pt)

	assert_bool(started) \
		.override_failure_message("a click on OPEN TABLE did not reach the world — something is eating every click before _unhandled_input and nothing in the 3D scene can be selected (URGENT-024). Every other case in this suite would now pass for the wrong reason.") \
		.is_true()


# ===== The defect itself =====

## Two regions, because they are owned by DIFFERENT controls and fail independently:
## the gaps/label bands between buttons (owned by the button column) and the panel's empty tail
## (owned by the ScrollContainer itself — an earlier attempt to make that tail click-through opened a
## measured 200x246 px hole in the middle of the visible menu at 1080p).
func test_a_click_inside_the_open_menu_does_not_reach_the_battlefield(timeout := 120000) -> void:
	var scroll := await _open_menu()
	var gap_pt := _point_in_menu_off_any_button(scroll)
	var tail_pt := _point_in_menu_tail(scroll)
	assert_vector(gap_pt).is_not_equal(Vector2.INF)
	assert_vector(tail_pt).is_not_equal(Vector2.INF)

	var gap_started: bool = await _click_and_report_box_select(gap_pt)
	var tail_started: bool = await _click_and_report_box_select(tail_pt)

	assert_bool(gap_started) \
		.override_failure_message("a click on a gap/label band BETWEEN the menu's buttons ALSO box-selected the battlefield underneath (maintainer: 'durchklickt auf das Spielfeld')") \
		.is_false()
	assert_bool(tail_started) \
		.override_failure_message("a click on the menu's opaque empty tail below the last button ALSO box-selected the battlefield underneath — the panel paints those pixels but no longer owns them") \
		.is_false()


func test_a_click_on_a_menu_button_works_the_button_and_not_the_battlefield(timeout := 120000) -> void:
	var scroll := await _open_menu()
	var buttons: Array = []
	_all_buttons(scroll, buttons)
	var btn := buttons[0] as Button
	btn.disabled = false
	# The menu's real handlers open dialogs and switch modes; an exclusive Window would then eat every
	# later event in this test. Detach them — the ENGINE's delivery of the click to the Button and the
	# Button's own `pressed` emission (what is under test) are untouched.
	for conn in btn.pressed.get_connections():
		btn.pressed.disconnect(conn["callable"] as Callable)
	var fired := [0]
	btn.pressed.connect(func() -> void: fired[0] += 1)
	var center := btn.get_global_rect().get_center()

	var started: bool = await _click_and_report_box_select(center)

	# BOTH halves of the maintainer's complaint, in one case.
	assert_bool(started) \
		.override_failure_message("clicking the '%s' button ALSO box-selected the battlefield behind it" % btn.text) \
		.is_false()
	assert_int(fired[0]) \
		.override_failure_message("clicking the '%s' button did not press it — the click was swallowed before the GUI (a full-rect STOP holder over the HUD does this)" % btn.text) \
		.is_greater_equal(1)


## THE CASE THE STATIC SUITE STRUCTURALLY CANNOT SEE. main.gd builds HUD surfaces in _ready() and adds
## them straight to the IGNORE holder — the battle-log tab at main.gd:8184, the unit dock at :597.
## test/ui_click_ownership_test.gd enumerates UI/HUD's children on the UN-READIED scene, so none of them
## are in its list: a mouse_filter regression on one is invisible to the very file that pins the rule.
##
## The click point is one the panel ALONE claims (no child over it) — that is the only place its own
## filter decides. Deliberately not AiOpponentBtn: that one lives inside the STOP button column, so the
## column would answer for it and its own filter would never be tested.
func test_a_hud_surface_built_at_runtime_owns_its_clicks_too(timeout := 120000) -> void:
	await _open_menu()
	var panel := _main.battle_log_panel as Control
	assert_that(panel) \
		.override_failure_message("the battle-log panel is gone — this test stands in for the runtime-built HUD surfaces the static .tscn test cannot enumerate; retarget it at another one") \
		.is_not_null()
	assert_bool(panel.is_visible_in_tree()).is_true()
	var pt := _point_owned_only_by(panel)
	assert_vector(pt) \
		.override_failure_message("no point on the battle-log panel is claimed by the panel itself (children cover all of it) — its own mouse_filter is untestable here; retarget at another runtime-built surface") \
		.is_not_equal(Vector2.INF)

	var started: bool = await _click_and_report_box_select(pt)

	assert_bool(started) \
		.override_failure_message("a click on the runtime-built battle-log panel fell through to the battlefield — it was inserted into the IGNORE holder without owning the pixels it paints, and no static test can see that") \
		.is_false()


## The motion half (object_manager.gd:323). A drag that STARTS on the table must keep receiving motion
## even when the pointer sweeps across a HUD panel: Godot routes motion to gui_find_control() whenever
## gui.mouse_focus is null — exactly the state during such a drag — and a STOP ancestor then eats it.
## The damage was silent and worst for dragging: the model froze at the panel edge but the RELEASE still
## arrived, committing it somewhere the player never dropped it.
func test_a_gesture_started_on_the_table_keeps_tracking_across_the_hud(timeout := 120000) -> void:
	var scroll := await _open_menu()
	var table_pt := _point_on_open_table(scroll)
	assert_vector(table_pt).is_not_equal(Vector2.INF)
	var menu_pt := _point_in_menu_off_any_button(scroll)
	assert_vector(menu_pt).is_not_equal(Vector2.INF)

	# Start a real box selection on open table.
	(_om() as Object).set("_is_box_selecting", false)
	E2EBoot.click_canvas(_vp(), table_pt, true)
	assert_bool(bool((_om() as Object).get("_is_box_selecting"))).is_true()
	var anchor: Vector2 = (_om() as Object).get("_box_select_start")

	# Sweep the pointer over the menu and check the gesture still follows it.
	E2EBoot.motion_canvas(_vp(), menu_pt, menu_pt - table_pt)
	var tracked: Vector2 = (_om() as Object).get("_box_select_end")

	E2EBoot.click_canvas(_vp(), menu_pt, false)   # release, so no gesture leaks into the next test
	await _runner.simulate_frames(1)

	# Compared against the gesture's own anchor rather than an absolute coordinate: the claim is that
	# the motion ARRIVED, which is space-independent and survives a stretch/resolution change.
	assert_vector(tracked) \
		.override_failure_message("the live box-selection stopped following the cursor the moment it crossed the HUD — the panel ate the motion event, so the rubber band froze at %s. For a DRAG this silently commits the model at the frozen position, because the RELEASE still arrives." % str(anchor)) \
		.is_not_equal(anchor)


## The close animation. The menu fades out over 0.15 s and is still visible and near-solid for most of
## it, so it must keep owning its clicks the whole way down — dropping the filter up front re-created
## this exact bug for 0.15 s.
func test_the_closing_menu_keeps_owning_its_clicks_while_it_fades(timeout := 120000) -> void:
	var scroll := await _open_menu()
	# The tail, not a button gap: left_panel_scroll's own mouse_filter is what the fade toggles, and
	# the tail is the only region where that filter — rather than the button column's — decides.
	var menu_pt := _point_in_menu_tail(scroll)
	assert_vector(menu_pt).is_not_equal(Vector2.INF)

	_main._on_hamburger_pressed()          # start the close fade
	await _runner.simulate_frames(2)       # a couple of frames INTO the fade, panel still visible
	assert_bool(scroll.visible) \
		.override_failure_message("the menu vanished instantly instead of fading — retune this test to the new animation") \
		.is_true()

	var started: bool = await _click_and_report_box_select(menu_pt)

	assert_bool(started) \
		.override_failure_message("a click on the still-visible CLOSING menu fell through to the battlefield — click ownership was dropped at the start of the fade instead of at its end") \
		.is_false()
