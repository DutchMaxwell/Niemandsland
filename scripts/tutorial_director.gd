class_name TutorialDirector
extends Node
## Runs the guided tutorial (T1 tool track W1-W6) on the REAL table inside main.tscn.
## Owns the pure pieces — a TutorialFlow cursor over the lesson track and a
## TutorialProgress cfg — and does the scene work around them: it translates the real
## gameplay seams into TutorialFlow.Events, resolves each step's spotlight target
## (UI Control rects or a live screen-projection of real model AABBs), drives the
## coach-mark overlay, runs the two-question self-assessment, and persists lesson
## completions so the track can be resumed or replayed per chapter.
##
## Steps advance ONLY on real signals / real UI state edges — never a "Next" button:
##   selection_changed / selection_dropped / rotation_committed  (object_manager)
##   action_undone                                               (undo_manager)
##   measurement_finished                                        (object_manager)
##   roll_finnished                                              (dice tray)
##   unit_activated                                              (radial controller)
##   loose_model_dead_changed                                    (army manager)
## plus polled state edges for camera deltas, menu/import-dialog visibility, dock
## open/presented and movement-band activity.

# ===== Constants =====
const BOARD_PATH := "res://assets/tutorial/tutorial_board.nml"
const ORBIT_THRESHOLD_RAD := 0.35    # ~20 degrees of accumulated orbit
const ZOOM_THRESHOLD_RATIO := 0.18   # 18 % zoom distance change
const PAN_THRESHOLD_M := 0.15        # 15 cm of pivot travel
const SPOTLIGHT_MIN_PX := 90.0       # never let a projected 3D spotlight get too small

# ===== Signals =====
signal step_changed(lesson_id: String, step_id: String)
signal lesson_completed(lesson_id: String)
signal tutorial_finished(completed: bool)

# ===== Public state =====
var flow: TutorialFlow = null
var progress: TutorialProgress = null

# ===== Scene refs (injected via setup) =====
var _object_manager: Node = null
var _camera_pivot: Node3D = null
var _camera: Camera3D = null
var _dice_tray: Node = null
var _dice_panel: Control = null
var _hamburger: Control = null
var _left_panel: Control = null
var _import_button: Control = null
var _import_dialog: Window = null
var _unit_dock: Node = null
var _radial_controller: Node = null
var _army_manager: Node = null
var _undo_manager: Node = null

# ===== Private state =====
var _coach: TutorialCoachMark = null
var _target_unit: GameUnit = null
var _target_nodes: Array[Node3D] = []
var _target_visuals: Array[VisualInstance3D] = []
var _parked_node: Node3D = null
var _parked_visuals: Array[VisualInstance3D] = []
# Camera delta accumulators (reset on entering a camera step).
var _prev_yaw: float = 0.0
var _prev_zoom: float = 0.0
var _prev_pivot: Vector3 = Vector3.ZERO
var _orbit_acc: float = 0.0
var _zoom_base: float = 1.0
var _pan_acc: float = 0.0
# Polled UI state edges.
var _prev_menu_open: bool = false
var _prev_import_open: bool = false
var _prev_dock_open: bool = false
var _prev_presented: bool = false
var _prev_bands_active: bool = false
var _assessment_dialog: ConfirmationDialog = null
# Chapter-picker launch: play forward from the chosen lesson WITHOUT skipping lessons
# that are already completed (replaying is the point). Resume launches skip them.
var _replay_mode: bool = false


# ===== Lifecycle =====

func _process(delta: float) -> void:
	if flow == null or flow.finished:
		return
	_poll_camera(delta)
	_poll_ui_edges()
	_track_spotlight()


# ===== Public API =====

## Wire the director to the live scene. `refs` keys (all optional, null-guarded):
## object_manager, camera_pivot, dice_tray, dice_panel, hamburger, left_panel,
## import_button, import_dialog, unit_dock, radial_controller, army_manager, undo_manager.
func setup(refs: Dictionary) -> void:
	_object_manager = refs.get("object_manager", null)
	_camera_pivot = refs.get("camera_pivot", null)
	_dice_tray = refs.get("dice_tray", null)
	_dice_panel = refs.get("dice_panel", null)
	_hamburger = refs.get("hamburger", null)
	_left_panel = refs.get("left_panel", null)
	_import_button = refs.get("import_button", null)
	_import_dialog = refs.get("import_dialog", null)
	_unit_dock = refs.get("unit_dock", null)
	_radial_controller = refs.get("radial_controller", null)
	_army_manager = refs.get("army_manager", null)
	_undo_manager = refs.get("undo_manager", null)
	if _camera_pivot != null:
		_camera = _camera_pivot.get_node_or_null("Camera3D") as Camera3D


## Start the tutorial. With `start_lesson` empty: run the assessment (once), apply the
## skip offer, then resume at the first incomplete lesson. With a lesson id (chapter
## picker): jump straight there, no assessment.
func begin(p_progress: TutorialProgress, start_lesson: String = "") -> void:
	progress = p_progress
	flow = TutorialFlow.new(TutorialFlow.build_tool_track())

	_coach = TutorialCoachMark.new()
	_coach.name = "TutorialCoachMark"
	add_child(_coach)
	_coach.skip_lesson_pressed.connect(_on_skip_lesson)
	_coach.end_pressed.connect(func() -> void: _finish(false))

	_connect_seams()
	_init_ui_edges()
	set_process(true)

	if not start_lesson.is_empty() and flow.start_at(start_lesson):
		_replay_mode = true
		_enter_step()
	elif progress != null and not progress.assessment_answered():
		_show_assessment()
	else:
		_start_from_progress()


# ===== Static helpers (pure, unit-tested) =====

## True when the selection contains any of the target unit's model nodes.
static func selection_hits(selected: Array, target_nodes: Array) -> bool:
	for obj in selected:
		if target_nodes.has(obj):
			return true
	return false


## True when a selection_dropped moves array actually moved a target model (> 0").
static func moves_hit(moves: Array, target_nodes: Array) -> bool:
	for move in moves:
		if move is Dictionary and target_nodes.has(move.get("node", null)) \
				and float(move.get("inches", 0.0)) > 0.0:
			return true
	return false


# ===== Seam wiring =====

func _connect_seams() -> void:
	if _object_manager != null:
		if _object_manager.has_signal("selection_changed"):
			_object_manager.selection_changed.connect(_on_selection_changed)
		if _object_manager.has_signal("selection_dropped"):
			_object_manager.selection_dropped.connect(_on_selection_dropped)
		if _object_manager.has_signal("rotation_committed"):
			_object_manager.rotation_committed.connect(_on_rotation_committed)
		if _object_manager.has_signal("measurement_finished"):
			_object_manager.measurement_finished.connect(_on_measurement_finished)
	if _undo_manager != null and _undo_manager.has_signal("action_undone"):
		_undo_manager.action_undone.connect(_on_action_undone)
	if _dice_tray != null and _dice_tray.has_signal("roll_finnished"):
		_dice_tray.roll_finnished.connect(_on_roll_finnished)
	if _radial_controller != null and _radial_controller.has_signal("unit_activated"):
		_radial_controller.unit_activated.connect(_on_unit_activated)
	if _army_manager != null and _army_manager.has_signal("loose_model_dead_changed"):
		_army_manager.loose_model_dead_changed.connect(_on_loose_model_dead_changed)


func _disconnect_seams() -> void:
	if _object_manager != null:
		_disconnect_if(_object_manager, "selection_changed", _on_selection_changed)
		_disconnect_if(_object_manager, "selection_dropped", _on_selection_dropped)
		_disconnect_if(_object_manager, "rotation_committed", _on_rotation_committed)
		_disconnect_if(_object_manager, "measurement_finished", _on_measurement_finished)
	if _undo_manager != null:
		_disconnect_if(_undo_manager, "action_undone", _on_action_undone)
	if _dice_tray != null:
		_disconnect_if(_dice_tray, "roll_finnished", _on_roll_finnished)
	if _radial_controller != null:
		_disconnect_if(_radial_controller, "unit_activated", _on_unit_activated)
	if _army_manager != null:
		_disconnect_if(_army_manager, "loose_model_dead_changed", _on_loose_model_dead_changed)


func _disconnect_if(source: Object, signal_name: String, callable: Callable) -> void:
	if source.has_signal(signal_name) and source.is_connected(signal_name, callable):
		source.disconnect(signal_name, callable)


# ===== Signal handlers (thin: translate to events) =====

func _on_selection_changed(selected: Array) -> void:
	if selection_hits(selected, _target_nodes):
		_on_event(TutorialFlow.Event.UNIT_SELECTED)


func _on_selection_dropped(moves: Array) -> void:
	if moves_hit(moves, _target_nodes):
		_on_event(TutorialFlow.Event.UNIT_MOVED)


func _on_rotation_committed(_objects: Array[Node3D]) -> void:
	_on_event(TutorialFlow.Event.ROTATED)


func _on_measurement_finished(_distance_inches: float) -> void:
	_on_event(TutorialFlow.Event.MEASURED)


func _on_action_undone(_description: String) -> void:
	_on_event(TutorialFlow.Event.UNDONE)


func _on_roll_finnished(_total: int) -> void:
	_on_event(TutorialFlow.Event.DICE_ROLLED)


func _on_unit_activated(_game_unit) -> void:
	_on_event(TutorialFlow.Event.UNIT_ACTIVATED)


func _on_loose_model_dead_changed(node: Node3D, dead: bool) -> void:
	if dead:
		_parked_node = node
		_parked_visuals = _collect_visuals([node])
		_on_event(TutorialFlow.Event.MODEL_KILLED)
	else:
		_on_event(TutorialFlow.Event.MODEL_REVIVED)


func _on_skip_lesson() -> void:
	if flow == null or flow.finished:
		return
	_apply_result(flow.skip_current_lesson())


# ===== FSM driving =====

func _on_event(event: TutorialFlow.Event) -> void:
	if flow == null or flow.finished:
		return
	_apply_result(flow.consume(event))


func _apply_result(result: Dictionary) -> void:
	if not bool(result.get("advanced", false)):
		return
	var completed_id := String(result.get("lesson_completed", ""))
	if not completed_id.is_empty():
		if progress != null:
			progress.mark_lesson_completed(completed_id)
			progress.save_to_disk()
		lesson_completed.emit(completed_id)
		if not flow.finished:
			_jump_past_completed_forward()
	if flow.finished:
		_finish(true)
	else:
		_enter_step()


## After a lesson boundary, keep moving FORWARD past lessons already completed
## (skipped via the assessment offer or a previous run). No wrap-around: if nothing
## incomplete remains ahead, the track is done. Chapter replays play everything.
func _jump_past_completed_forward() -> void:
	if progress == null or _replay_mode:
		return
	var lesson_ids := TutorialFlow.ids(flow.lessons)
	for i in range(flow.lesson_index, lesson_ids.size()):
		if not progress.is_lesson_completed(lesson_ids[i]):
			flow.start_at(lesson_ids[i])
			return
	flow.finish_track()


func _start_from_progress() -> void:
	var lesson_ids := TutorialFlow.ids(flow.lessons)
	var next := progress.first_incomplete(lesson_ids) if progress != null else ""
	if next.is_empty():
		next = lesson_ids[0] if not lesson_ids.is_empty() else ""  # all done -> replay from the top
	if next.is_empty() or not flow.start_at(next):
		_finish(false)
		return
	_enter_step()


## Everything that happens when the cursor lands on a step: reset detectors, resolve
## the spotlight target, point the camera where it helps, update the coach mark.
func _enter_step() -> void:
	var step := flow.current_step()
	if step.is_empty():
		return
	var event := int(step.get("event", TutorialFlow.Event.NONE)) as TutorialFlow.Event
	var target := String(step.get("target", TutorialFlow.TARGET_NONE))
	var mask := bool(step.get("mask", false))

	if _is_camera_event(event):
		_reset_camera_baselines()
	if target == TutorialFlow.TARGET_UNIT:
		_resolve_target_unit()
		if event == TutorialFlow.Event.UNIT_SELECTED:
			_focus_camera_on_nodes(_target_nodes)
	elif target == TutorialFlow.TARGET_PARKED_MODEL and is_instance_valid(_parked_node):
		_focus_camera_on_nodes([_parked_node])

	if is_instance_valid(_coach):
		var lesson := flow.current_lesson()
		_coach.set_progress_text("LESSON %d/%d · %s — STEP %d/%d" % [
			flow.lesson_index + 1, flow.lesson_count(),
			String(lesson.get("title", "")).to_upper(),
			flow.step_index + 1, flow.step_count()])
		var rect := _resolve_target_rect(target)
		if target == TutorialFlow.TARGET_NONE or rect == Rect2():
			_coach.show_banner(String(step.get("text", "")))
		else:
			_coach.show_step(String(step.get("text", "")), rect, mask)

	step_changed.emit(String(flow.current_lesson().get("id", "")), String(step.get("id", "")))
	# UI-state events may already be satisfied when the step starts (e.g. the menu is
	# already open) — no fresh edge would ever come, so complete such steps directly.
	if _state_already_satisfied(event):
		call_deferred("_on_event", event)


## Tear down cleanly: stop processing, drop the seams, hide the overlay, report.
## main frees the director node (which frees the overlay child).
func _finish(completed: bool) -> void:
	set_process(false)
	_disconnect_seams()
	if is_instance_valid(_assessment_dialog):
		_assessment_dialog.queue_free()
		_assessment_dialog = null
	if is_instance_valid(_coach):
		_coach.hide_overlay()
	tutorial_finished.emit(completed)


## Smoke/test harness ONLY: complete the current step as if its real event had fired.
func _force_complete_current_step() -> void:
	var step := flow.current_step() if flow != null else {}
	if step.is_empty():
		return
	_on_event(int(step.get("event", TutorialFlow.Event.NONE)) as TutorialFlow.Event)


# ===== Assessment (two questions, asked once) =====

func _show_assessment() -> void:
	_assessment_dialog = ConfirmationDialog.new()
	_assessment_dialog.title = "Welcome to the tutorial"
	_assessment_dialog.ok_button_text = "START"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTokens.SECTION_SEP)
	var intro := Label.new()
	intro.text = "Two quick questions so the tutorial fits you:"
	vbox.add_child(intro)
	var rules_check := CheckButton.new()
	rules_check.text = "I know the OnePageRules basics"
	vbox.add_child(rules_check)
	var sim_check := CheckButton.new()
	sim_check.text = "I have used a tabletop simulator before"
	vbox.add_child(sim_check)
	_assessment_dialog.add_child(vbox)
	_assessment_dialog.confirmed.connect(func() -> void:
		_on_assessment_answered(rules_check.button_pressed, sim_check.button_pressed))
	_assessment_dialog.canceled.connect(func() -> void:
		_start_from_progress())  # not answered -> asked again next time
	add_child(_assessment_dialog)
	_assessment_dialog.popup_centered()


func _on_assessment_answered(knows_rules: bool, used_sim: bool) -> void:
	if progress != null:
		progress.set_assessment(knows_rules, used_sim)
		progress.save_to_disk()
	var offer := TutorialProgress.skip_offer_lessons(used_sim)
	if offer.is_empty():
		_start_from_progress()
		return
	var skip_dialog := ConfirmationDialog.new()
	skip_dialog.title = "Skip the basics?"
	skip_dialog.dialog_text = "You already know your way around a simulator.\nSkip the camera and select/move basics and start with importing armies?"
	skip_dialog.ok_button_text = "SKIP THE BASICS"
	skip_dialog.cancel_button_text = "PLAY EVERYTHING"
	skip_dialog.confirmed.connect(func() -> void:
		if progress != null:
			for lesson_id in offer:
				progress.mark_lesson_completed(lesson_id)
			progress.save_to_disk()
		_start_from_progress())
	skip_dialog.canceled.connect(func() -> void: _start_from_progress())
	add_child(skip_dialog)
	skip_dialog.popup_centered()


# ===== Camera delta detection (W1) =====

func _is_camera_event(event: TutorialFlow.Event) -> bool:
	return event == TutorialFlow.Event.CAMERA_ORBIT \
		or event == TutorialFlow.Event.CAMERA_ZOOM \
		or event == TutorialFlow.Event.CAMERA_PAN


func _reset_camera_baselines() -> void:
	_orbit_acc = 0.0
	_pan_acc = 0.0
	if _camera_pivot != null:
		_prev_yaw = _camera_pivot.rotation.y
		_prev_pivot = _camera_pivot.global_position
	if _camera != null:
		_prev_zoom = _camera.position.length()
		_zoom_base = maxf(_prev_zoom, 0.001)


func _poll_camera(_delta: float) -> void:
	var step := flow.current_step()
	var event := int(step.get("event", TutorialFlow.Event.NONE)) as TutorialFlow.Event
	if not _is_camera_event(event) or _camera_pivot == null:
		return
	match event:
		TutorialFlow.Event.CAMERA_ORBIT:
			var yaw := _camera_pivot.rotation.y
			_orbit_acc += absf(angle_difference(_prev_yaw, yaw))
			_prev_yaw = yaw
			if _orbit_acc >= ORBIT_THRESHOLD_RAD:
				_on_event(TutorialFlow.Event.CAMERA_ORBIT)
		TutorialFlow.Event.CAMERA_ZOOM:
			if _camera != null:
				var zoom := _camera.position.length()
				if absf(zoom - _zoom_base) / _zoom_base >= ZOOM_THRESHOLD_RATIO:
					_on_event(TutorialFlow.Event.CAMERA_ZOOM)
		TutorialFlow.Event.CAMERA_PAN:
			var pos := _camera_pivot.global_position
			_pan_acc += pos.distance_to(_prev_pivot)
			_prev_pivot = pos
			if _pan_acc >= PAN_THRESHOLD_M:
				_on_event(TutorialFlow.Event.CAMERA_PAN)
		_:
			pass


# ===== Polled UI state edges =====

func _init_ui_edges() -> void:
	_prev_menu_open = _menu_open()
	_prev_import_open = _import_open()
	_prev_dock_open = _dock_open()
	_prev_presented = _card_presented()
	_prev_bands_active = _bands_active()


func _poll_ui_edges() -> void:
	var menu_open := _menu_open()
	if menu_open and not _prev_menu_open:
		_on_event(TutorialFlow.Event.MENU_OPENED)
	_prev_menu_open = menu_open

	var import_open := _import_open()
	if import_open and not _prev_import_open:
		_on_event(TutorialFlow.Event.IMPORT_OPENED)
	elif _prev_import_open and not import_open:
		_on_event(TutorialFlow.Event.IMPORT_CLOSED)
	_prev_import_open = import_open

	var dock_open := _dock_open()
	if dock_open and not _prev_dock_open:
		_on_event(TutorialFlow.Event.DOCK_OPENED)
	_prev_dock_open = dock_open

	var presented := _card_presented()
	if presented and not _prev_presented:
		_on_event(TutorialFlow.Event.CARD_PRESENTED)
	_prev_presented = presented

	var bands := _bands_active()
	if bands and not _prev_bands_active:
		_on_event(TutorialFlow.Event.BANDS_SHOWN)
	_prev_bands_active = bands


func _menu_open() -> bool:
	return _left_panel != null and _left_panel.visible


func _import_open() -> bool:
	return is_instance_valid(_import_dialog) and _import_dialog.visible


func _dock_open() -> bool:
	return _unit_dock != null and _unit_dock.has_method("is_dock_open") and _unit_dock.is_dock_open()


func _card_presented() -> bool:
	return _unit_dock != null and _unit_dock.has_method("get_presented_unit") \
		and _unit_dock.get_presented_unit() != null


func _bands_active() -> bool:
	if _object_manager == null:
		return false
	var bands_controller = _object_manager.get("movement_range_controller")
	return bands_controller != null and bands_controller.active_count() > 0


## For events that reflect a UI STATE (not a gesture): true when the state is already
## reached at step entry, so the step self-completes instead of waiting for an edge.
func _state_already_satisfied(event: TutorialFlow.Event) -> bool:
	match event:
		TutorialFlow.Event.MENU_OPENED:
			return _menu_open()
		TutorialFlow.Event.IMPORT_OPENED:
			return _import_open()
		TutorialFlow.Event.DOCK_OPENED:
			return _dock_open()
		TutorialFlow.Event.CARD_PRESENTED:
			return _card_presented()
		TutorialFlow.Event.BANDS_SHOWN:
			return _bands_active()
		_:
			return false


# ===== Target resolution / spotlight =====

## Pick the tutorial's highlighted unit: the local player's (player 1) unit with the
## most alive models, so the spotlight always has something real to point at.
func _resolve_target_unit() -> void:
	if _target_unit != null and _target_unit.get_alive_count() > 0 and not _target_nodes.is_empty():
		return
	_target_unit = null
	_target_nodes = []
	if _army_manager == null:
		return
	var units = _army_manager.get("game_units")
	if not units is Dictionary:
		return
	var best: GameUnit = null
	for unit in units.values():
		if not unit is GameUnit:
			continue
		if int(unit.unit_properties.get("player_id", 0)) != 1:
			continue
		if unit.get_alive_count() == 0:
			continue
		if best == null or unit.get_alive_count() > best.get_alive_count():
			best = unit
	if best == null:
		return
	_target_unit = best
	for model in best.models:
		if model != null and is_instance_valid(model.node):
			_target_nodes.append(model.node)
	_target_visuals = _collect_visuals(_target_nodes)


## All VisualInstance3D under the given nodes (cached per step; AABBs are then
## projected per frame without walking the tree again).
func _collect_visuals(nodes: Array) -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var stack: Array[Node] = [node]
		while not stack.is_empty():
			var current: Node = stack.pop_back()
			if current is VisualInstance3D:
				result.append(current)
			for child in current.get_children():
				stack.append(child)
	return result


func _resolve_target_rect(target: String) -> Rect2:
	match target:
		TutorialFlow.TARGET_UNIT:
			return _project_visuals(_target_visuals, _target_nodes)
		TutorialFlow.TARGET_PARKED_MODEL:
			var parked: Array[Node3D] = []
			if is_instance_valid(_parked_node):
				parked.append(_parked_node)
			return _project_visuals(_parked_visuals, parked)
		TutorialFlow.TARGET_HAMBURGER:
			return _control_rect(_hamburger)
		TutorialFlow.TARGET_IMPORT_BUTTON:
			return _control_rect(_import_button)
		TutorialFlow.TARGET_DICE_PANEL:
			return _control_rect(_dice_panel)
		TutorialFlow.TARGET_DOCK_TAB:
			return _dock_rect("tab_rect")
		TutorialFlow.TARGET_DOCK_STRIP:
			return _dock_rect("strip_rect")
		TutorialFlow.TARGET_PRESENTED_CARD:
			return _dock_rect("presented_rect")
		_:
			return Rect2()


func _control_rect(control: Control) -> Rect2:
	return control.get_global_rect() if (control != null and control.visible) else Rect2()


func _dock_rect(method: String) -> Rect2:
	if _unit_dock == null or not _unit_dock.has_method(method):
		return Rect2()
	return _unit_dock.call(method)


## Keep the spotlight glued to a moving/animating target (dragged unit, tweening dock).
func _track_spotlight() -> void:
	if not is_instance_valid(_coach) or not _coach.visible:
		return
	var target := String(flow.current_step().get("target", TutorialFlow.TARGET_NONE))
	if target == TutorialFlow.TARGET_NONE:
		return
	var rect := _resolve_target_rect(target)
	if rect != Rect2():
		_coach.set_target_rect(rect)


## Project the cached model visuals to one merged screen rect (their real AABBs — the
## T0 fixed-extents box is retired). Falls back to the node origins when a model has
## no visuals yet (e.g. its GLB is still streaming in).
func _project_visuals(visuals: Array[VisualInstance3D], fallback_nodes: Array) -> Rect2:
	if _camera == null:
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var found := false
	for vi in visuals:
		if not is_instance_valid(vi):
			continue
		var aabb: AABB = vi.global_transform * vi.get_aabb()
		for i in 8:
			var world := aabb.get_endpoint(i)
			if _camera.is_position_behind(world):
				continue
			var screen := _camera.unproject_position(world)
			mn = mn.min(screen)
			mx = mx.max(screen)
			found = true
	if not found:
		for node in fallback_nodes:
			if not is_instance_valid(node):
				continue
			var world: Vector3 = node.global_position
			if _camera.is_position_behind(world):
				continue
			var screen := _camera.unproject_position(world)
			mn = mn.min(screen - Vector2(SPOTLIGHT_MIN_PX, SPOTLIGHT_MIN_PX) * 0.5)
			mx = mx.max(screen + Vector2(SPOTLIGHT_MIN_PX, SPOTLIGHT_MIN_PX) * 0.5)
			found = true
	if not found:
		return Rect2()
	var rect := Rect2(mn, mx - mn)
	if rect.size.x < SPOTLIGHT_MIN_PX or rect.size.y < SPOTLIGHT_MIN_PX:
		var grow_x := maxf(0.0, (SPOTLIGHT_MIN_PX - rect.size.x) * 0.5)
		var grow_y := maxf(0.0, (SPOTLIGHT_MIN_PX - rect.size.y) * 0.5)
		rect = rect.grow_individual(grow_x, grow_y, grow_x, grow_y)
	return rect


func _focus_camera_on_nodes(nodes: Array) -> void:
	if _camera_pivot == null or not _camera_pivot.has_method("focus_on"):
		return
	var sum := Vector3.ZERO
	var count := 0
	for node in nodes:
		if is_instance_valid(node):
			sum += node.global_position
			count += 1
	if count > 0:
		_camera_pivot.focus_on(sum / count)
