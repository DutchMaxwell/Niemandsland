extends GdUnitTestSuite
## E2E — GH #364 / NML-1079: "half my clicks are being ignored".
##
## THE CLAIM UNDER TEST: a left click that lands on the same spot as the previous one within the
## platform's double-click window carries `InputEventMouseButton.double_click = true` instead of a
## plain press. Godot's DisplayServer flags that second press and then RESETS its state, so a steady
## stream of clicks on one spot is flagged single, double, single, double... — literally every second
## click. Whatever the game does with a flagged press is therefore what the player experiences as
## "half my clicks".
##
## WHAT IS DRIVEN: the real scenes/main.tscn, its real _ready(), the real ObjectManager, the real
## Godot dispatch chain (_input -> Control._gui_input -> _unhandled_input), real
## InputEventMouseButton pushed through the real Viewport, real camera unproject + physics raycast.
## Only the click coordinates are constructed, and those are scanned from the live scene at runtime.
##
## COORDINATES: headless the window is 1280x720 while the project stretches to 1920x1080, so Control
## rects / Camera3D.unproject_position() (canvas space) and InputEvent.position (screen space) differ
## by 1.5x. E2EBoot.click_canvas() applies get_screen_transform(); without it every click lands on a
## neighbouring widget and the suite passes while testing nothing.
##
## TWO OBSERVABLES, both binary and both free of rendering:
##   TABLE — ObjectManager._is_box_selecting, read AT THE PRESS. A press that survives to
##           _unhandled_input over open table starts a rubber band. Same observable as
##           e2e_click_ownership_test.gd.
##   MODEL — ObjectManager._is_dragging, read AT THE PRESS. A press on a selectable model selects it
##           and starts the drag that makes click-and-drag work at all.
##
## FOUR SERIES, 10 click pairs each, pass criterion 10/10:
##   (a) 300 ms apart, no flag                 — the control: slow clicking must always work.
##   (b) 120 ms apart, every 2nd press flagged — what the OS actually sends inside its double-click
##                                               window (~400 ms X11 / the OS setting on Windows).
##   (c) 3 px of hand motion between press and release, no flag — high-DPI mouse jitter.
##   (d) preceded by a ~450 ms busy stall in the same frame, no flag — a frame hitch (the sight-fan
##       build costs ~440 ms, NML-986). The fan itself is F-key toggled, not selection-triggered, so
##       a raw stall is the faithful stand-in for "a click issued around a long frame".

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const SERIES_CLICKS := 10
const STALL_MS := 450

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _om() -> Node:
	return _main.object_manager


func _vp() -> Viewport:
	return _main.get_viewport()


# ===== Click plumbing =====

## One full press/release pair. `flag_double` marks the press exactly as the DisplayServer marks the
## second press of a fast pair. `motion_px` moves the pointer between press and release.
## Returns the observable, read AT THE PRESS (the release finishes/clears the gesture again).
func _click_pair(canvas_pos: Vector2, flag_double: bool, motion_px: float, observable: String) -> bool:
	(_om() as Object).set(observable, false)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = flag_double
	ev.position = _vp().get_screen_transform() * canvas_pos
	ev.global_position = ev.position
	_vp().push_input(ev)
	var registered: bool = bool((_om() as Object).get(observable))

	var release_pos := canvas_pos
	if motion_px > 0.0:
		release_pos = canvas_pos + Vector2(motion_px, 0.0)
		E2EBoot.motion_canvas(_vp(), release_pos, Vector2(motion_px, 0.0))
	E2EBoot.click_canvas(_vp(), release_pos, false)
	await _runner.simulate_frames(1)
	(_om() as Object).call("_deselect_all")
	return registered


## Burn ~STALL_MS of wall clock inside one frame — a frame hitch, not a yield.
func _busy_stall() -> void:
	var until := Time.get_ticks_msec() + STALL_MS
	var sink := 0.0
	while Time.get_ticks_msec() < until:
		sink += sqrt(float(Time.get_ticks_usec() & 0xFFFF))
	assert_float(sink).is_greater_equal(0.0)   # keep the loop from being optimised into nothing


## Run one series and return how many of its SERIES_CLICKS pairs registered.
## `os_flags` reproduces the DisplayServer pattern: it flags the 2nd, 4th, 6th... press, because the
## engine clears its double-click state right after flagging one, so three fast clicks are
## single/double/single — never double/double.
func _run_series(canvas_pos: Vector2, observable: String, gap_s: float, os_flags: bool,
		motion_px: float, stall: bool) -> int:
	var hits := 0
	for i in SERIES_CLICKS:
		if stall:
			_busy_stall()
		var flag := os_flags and (i % 2 == 1)
		if await _click_pair(canvas_pos, flag, motion_px, observable):
			hits += 1
		if gap_s > 0.0:
			await get_tree().create_timer(gap_s).timeout
	return hits


# ===== Click targets, scanned from the live scene =====

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


func _ui_claims(canvas_pos: Vector2) -> bool:
	return _claims_recursive(_main.get_node("UI"), canvas_pos)


## A canvas point over OPEN TABLE, clear of every click-claiming Control.
func _point_on_open_table() -> Vector2:
	var hud := _main.get_node("UI/HUD") as Control
	var rect := hud.get_global_rect()
	for fy in [0.62, 0.70, 0.52, 0.44, 0.80]:
		for fx in [0.72, 0.62, 0.80, 0.50, 0.88]:
			var p := rect.position + Vector2(rect.size.x * float(fx), rect.size.y * float(fy))
			if not _ui_claims(p):
				return p
	return Vector2.INF


## Two real miniatures (StaticBody3D + collider + "selectable", the shipped spawn path) tied together
## as ONE GameUnit of two models — the ordinary case on the table, and the case in which
## _try_select_unit_at_mouse takes its whole-unit branch instead of falling back to a normal click.
## Returns the canvas point over the first one, or Vector2.INF if it is not cleanly clickable.
var _fixture_models: Array[Node3D] = []

func _spawn_two_model_unit() -> Vector2:
	var cam := _vp().get_camera_3d()
	if cam == null:
		return Vector2.INF
	for wz in [0.15, 0.30, 0.0, -0.15]:
		for wx in [0.20, 0.40, 0.0, -0.20]:
			var origin := Vector3(float(wx), 0.0, float(wz))
			var a: Node3D = (_om() as Object).call("spawn_miniature", origin, false)
			var b: Node3D = (_om() as Object).call("spawn_miniature",
				origin + Vector3(0.12, 0.0, 0.0), false)
			var unit := GameUnit.new()
			unit.unit_id = "e2e_click_drop"
			unit.unit_properties = {"player_id": 0, "name": "ClickDrop", "quality": 4, "defense": 4}
			for n in [a, b]:
				var mi := ModelInstance.new()
				mi.is_alive = true
				mi.unit = unit
				mi.node = n
				unit.models.append(mi)
				n.set_meta("game_unit", unit)
			var aim := a.global_position + Vector3(0.0, 0.016, 0.0)   # mid-body, not the base rim
			var p := cam.unproject_position(aim)
			if not _ui_claims(p) and (_om() as Object).call("_get_object_at_position", p) == a:
				_fixture_models = [a, b]
				return p
			a.queue_free()
			b.queue_free()
			await _runner.simulate_frames(1)
	return Vector2.INF


# ===== The positive control, first =====
# Without it every count below could be 0/10 for the trivial reason that nothing in the scene is
# clickable at all, and the suite would still "find" a bug.

func test_a_slow_click_series_on_open_table_registers_every_time(timeout := 300000) -> void:
	var pt := _point_on_open_table()
	assert_vector(pt).is_not_equal(Vector2.INF)

	var hits: int = await _run_series(pt, "_is_box_selecting", 0.30, false, 0.0, false)

	prints("CLICKS table (a) slow, no flag: %d/%d" % [hits, SERIES_CLICKS])
	assert_int(hits) \
		.override_failure_message("even SLOW clicks on open table do not reach the world — the whole suite would now measure nothing (URGENT-024 state)") \
		.is_equal(SERIES_CLICKS)


# ===== The defect =====

func test_fast_click_series_on_open_table_registers_every_time(timeout := 300000) -> void:
	var pt := _point_on_open_table()
	assert_vector(pt).is_not_equal(Vector2.INF)

	var hits: int = await _run_series(pt, "_is_box_selecting", 0.12, true, 0.0, false)

	prints("CLICKS table (b) fast, OS double_click flags: %d/%d" % [hits, SERIES_CLICKS])
	assert_int(hits) \
		.override_failure_message("clicking FAST on open table dropped %d of %d clicks: the presses the DisplayServer flagged as double_click never started a rubber band. object_manager.gd:369 routes a flagged press to _try_select_unit_at_mouse(), which returns after _deselect_all() when the ray hits nothing — the click is gone (GH #364)" % [SERIES_CLICKS - hits, SERIES_CLICKS]) \
		.is_equal(SERIES_CLICKS)


func test_a_click_with_a_few_px_of_hand_motion_registers_every_time(timeout := 300000) -> void:
	var pt := _point_on_open_table()
	assert_vector(pt).is_not_equal(Vector2.INF)

	var hits: int = await _run_series(pt, "_is_box_selecting", 0.05, false, 3.0, false)

	prints("CLICKS table (c) 3 px motion: %d/%d" % [hits, SERIES_CLICKS])
	assert_int(hits) \
		.override_failure_message("3 px of hand motion between press and release lost %d of %d clicks — a click is being classified as a drag" % [SERIES_CLICKS - hits, SERIES_CLICKS]) \
		.is_equal(SERIES_CLICKS)


func test_a_click_around_a_long_frame_registers_every_time(timeout := 300000) -> void:
	var pt := _point_on_open_table()
	assert_vector(pt).is_not_equal(Vector2.INF)

	var hits: int = await _run_series(pt, "_is_box_selecting", 0.0, false, 0.0, true)

	prints("CLICKS table (d) after a %d ms frame hitch: %d/%d" % [STALL_MS, hits, SERIES_CLICKS])
	assert_int(hits) \
		.override_failure_message("a %d ms frame hitch before the click lost %d of %d clicks" % [STALL_MS, SERIES_CLICKS - hits, SERIES_CLICKS]) \
		.is_equal(SERIES_CLICKS)


## The same two series ON A MODEL, where the loss is what the player actually complains about: the
## press neither picks the model up nor lets him drag it.
func test_click_series_on_a_model_starts_the_drag_every_time(timeout := 300000) -> void:
	var pt: Vector2 = await _spawn_two_model_unit()
	assert_vector(pt) \
		.override_failure_message("could not place a cleanly clickable miniature on the table — retarget this test") \
		.is_not_equal(Vector2.INF)

	var slow: int = await _run_series(pt, "_is_dragging", 0.30, false, 0.0, false)
	var fast: int = await _run_series(pt, "_is_dragging", 0.12, true, 0.0, false)

	prints("CLICKS model (a) slow, no flag: %d/%d" % [slow, SERIES_CLICKS])
	prints("CLICKS model (b) fast, OS double_click flags: %d/%d" % [fast, SERIES_CLICKS])
	assert_int(slow) \
		.override_failure_message("slow clicks on a model do not start a drag — the positive control for this case is dead") \
		.is_equal(SERIES_CLICKS)
	assert_int(fast) \
		.override_failure_message("clicking FAST on a model dropped %d of %d grabs: a press flagged double_click takes object_manager.gd:369's whole-unit branch, which selects but never calls _start_dragging() — the model cannot be picked up (GH #364)" % [SERIES_CLICKS - fast, SERIES_CLICKS]) \
		.is_equal(SERIES_CLICKS)
