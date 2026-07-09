class_name TutorialDirector
extends Node
## Event-gated step FSM for the T0 guided-play tutorial. It runs on the REAL table inside
## main.tscn (no separate scene) and advances ONLY on real gameplay signals — the same
## central seams the battle-log collector taps: `object_manager.selection_changed`,
## `object_manager.selection_dropped` and `dice_tray.roll_finnished`. No "Next" buttons.
##
## The step-transition logic is pure and side-effect-free (the `_*_completes` / `next_step`
## helpers) so it is unit-testable without a scene; `_apply_step_visuals` does the scene work
## (coach mark + camera focus) and is fully null-guarded, so the FSM can be driven headless.
## T0 persists nothing.

# ===== Constants =====
# Fixed world half-extents used to project a tight spotlight box around the target unit
# (metres; roughly a 30 mm base, ~55 mm tall — see docs/CLAUDE Scaling section).
const UNIT_HALF_WIDTH := 0.04
const UNIT_HEIGHT := 0.055
const SPOTLIGHT_MIN_PX := 90.0   # never let the projected unit spotlight get too small

enum Step { INACTIVE, SELECT, MOVE, ROLL, DONE }

# ===== Signals =====
signal step_changed(step: Step)
signal tutorial_finished(completed: bool)

# ===== Private state =====
var current_step: Step = Step.INACTIVE

var _object_manager: Node = null
var _camera_pivot: Node3D = null            # camera_controller — for focus_on()
var _camera: Camera3D = null                # for unproject_position()
var _dice_tray: Node = null                 # emits roll_finnished
var _dice_panel: Control = null             # spotlight target for the ROLL step
var _target_unit: Node3D = null
var _coach: TutorialCoachMark = null
var _corner_offsets: PackedVector3Array = PackedVector3Array()


# ===== Lifecycle =====

func _process(_delta: float) -> void:
	# While the unit is the focus, keep its screen-projected spotlight tracking the
	# animating camera. Value-type math only — no per-frame allocations.
	if current_step != Step.SELECT and current_step != Step.MOVE:
		return
	if not is_instance_valid(_coach) or not is_instance_valid(_target_unit) or _camera == null:
		return
	_coach.set_target_rect(_unit_screen_rect())


# ===== Public API =====

## Wire the director to the live scene nodes. Call once before `begin()`.
func setup(object_manager: Node, camera_pivot: Node3D, target_unit: Node3D, dice_tray: Node, dice_panel: Control) -> void:
	_object_manager = object_manager
	_camera_pivot = camera_pivot
	_target_unit = target_unit
	_dice_tray = dice_tray
	_dice_panel = dice_panel
	if camera_pivot != null:
		_camera = camera_pivot.get_node_or_null("Camera3D") as Camera3D
	# Eight corners of the unit box, built once so _process allocates nothing.
	_corner_offsets = PackedVector3Array([
		Vector3(-UNIT_HALF_WIDTH, 0.0, -UNIT_HALF_WIDTH),
		Vector3(UNIT_HALF_WIDTH, 0.0, -UNIT_HALF_WIDTH),
		Vector3(-UNIT_HALF_WIDTH, 0.0, UNIT_HALF_WIDTH),
		Vector3(UNIT_HALF_WIDTH, 0.0, UNIT_HALF_WIDTH),
		Vector3(-UNIT_HALF_WIDTH, UNIT_HEIGHT, -UNIT_HALF_WIDTH),
		Vector3(UNIT_HALF_WIDTH, UNIT_HEIGHT, -UNIT_HALF_WIDTH),
		Vector3(-UNIT_HALF_WIDTH, UNIT_HEIGHT, UNIT_HALF_WIDTH),
		Vector3(UNIT_HALF_WIDTH, UNIT_HEIGHT, UNIT_HALF_WIDTH),
	])


## Build the coach-mark overlay, connect the real seams and enter the first step.
func begin() -> void:
	_coach = TutorialCoachMark.new()
	_coach.name = "TutorialCoachMark"
	add_child(_coach)
	_coach.skip_pressed.connect(_on_skip_pressed)

	if _object_manager != null:
		if _object_manager.has_signal("selection_changed"):
			_object_manager.selection_changed.connect(_on_selection_changed)
		if _object_manager.has_signal("selection_dropped"):
			_object_manager.selection_dropped.connect(_on_selection_dropped)
	if _dice_tray != null and _dice_tray.has_signal("roll_finnished"):
		_dice_tray.roll_finnished.connect(_on_roll_finnished)

	set_process(true)
	_set_step(Step.SELECT)


# ===== Pure step logic (unit-testable, no scene dependencies) =====

## The step that follows `step` in the T0 flow (terminal at DONE).
static func next_step(step: Step) -> Step:
	match step:
		Step.SELECT:
			return Step.MOVE
		Step.MOVE:
			return Step.ROLL
		Step.ROLL:
			return Step.DONE
		_:
			return step


## True when a selection event completes the SELECT step (the target unit is now selected).
static func selection_completes(step: Step, selected: Array, target: Object) -> bool:
	return step == Step.SELECT and target != null and selected.has(target)


## True when a drop event completes the MOVE step (the target unit actually moved).
static func drop_completes(step: Step, moves: Array, target: Object) -> bool:
	if step != Step.MOVE:
		return false
	for move in moves:
		if move is Dictionary and move.get("node", null) == target and float(move.get("inches", 0.0)) > 0.0:
			return true
	return false


## True when a dice roll completes the ROLL step (any roll counts).
static func roll_completes(step: Step) -> bool:
	return step == Step.ROLL


# ===== Signal handlers (thin: pure predicate -> advance) =====

func _on_selection_changed(selected: Array) -> void:
	if selection_completes(current_step, selected, _target_unit):
		_advance()


func _on_selection_dropped(moves: Array) -> void:
	if drop_completes(current_step, moves, _target_unit):
		_advance()


func _on_roll_finnished(_total: int) -> void:
	if roll_completes(current_step):
		_advance()


func _on_skip_pressed() -> void:
	_finish(false)


# ===== FSM driving =====

func _advance() -> void:
	_set_step(next_step(current_step))


func _set_step(step: Step) -> void:
	current_step = step
	step_changed.emit(step)
	_apply_step_visuals(step)


## All scene-touching work for a step. Fully null-guarded so the FSM can run headless
## (a test drives the handlers without ever calling `begin()`/building the overlay).
func _apply_step_visuals(step: Step) -> void:
	match step:
		Step.SELECT:
			if is_instance_valid(_camera_pivot) and is_instance_valid(_target_unit) and _camera_pivot.has_method("focus_on"):
				_camera_pivot.focus_on(_target_unit.global_position)
			if is_instance_valid(_coach):
				_coach.show_step("Click the unit to select it.", _unit_screen_rect())
		Step.MOVE:
			if is_instance_valid(_coach):
				_coach.show_step("Drag the unit across the table, then release.", _unit_screen_rect())
		Step.ROLL:
			if is_instance_valid(_coach):
				var rect := _dice_panel.get_global_rect() if is_instance_valid(_dice_panel) else Rect2()
				_coach.show_step("Roll the dice.", rect)
		Step.DONE:
			_finish(true)


## Tear down the tutorial cleanly: stop tracking, drop the seams, hide the overlay and
## announce the outcome. main frees the director node (which frees the overlay child).
func _finish(completed: bool) -> void:
	set_process(false)
	_disconnect_seams()
	if is_instance_valid(_coach):
		_coach.hide_overlay()
	tutorial_finished.emit(completed)


func _disconnect_seams() -> void:
	if _object_manager != null:
		if _object_manager.has_signal("selection_changed") and _object_manager.selection_changed.is_connected(_on_selection_changed):
			_object_manager.selection_changed.disconnect(_on_selection_changed)
		if _object_manager.has_signal("selection_dropped") and _object_manager.selection_dropped.is_connected(_on_selection_dropped):
			_object_manager.selection_dropped.disconnect(_on_selection_dropped)
	if _dice_tray != null and _dice_tray.has_signal("roll_finnished") and _dice_tray.roll_finnished.is_connected(_on_roll_finnished):
		_dice_tray.roll_finnished.disconnect(_on_roll_finnished)


## Project the target unit's box to a tight screen rectangle (with a minimum size so the
## spotlight is always clearly visible), used as the SELECT/MOVE spotlight.
func _unit_screen_rect() -> Rect2:
	if _camera == null or not is_instance_valid(_target_unit):
		return Rect2()
	var centre := _target_unit.global_position
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for offset in _corner_offsets:
		var world := centre + offset
		if _camera.is_position_behind(world):
			continue
		var screen := _camera.unproject_position(world)
		mn = mn.min(screen)
		mx = mx.max(screen)
	if mn.x == INF:
		return Rect2()
	var rect := Rect2(mn, mx - mn)
	if rect.size.x < SPOTLIGHT_MIN_PX or rect.size.y < SPOTLIGHT_MIN_PX:
		var grow_x := maxf(0.0, (SPOTLIGHT_MIN_PX - rect.size.x) * 0.5)
		var grow_y := maxf(0.0, (SPOTLIGHT_MIN_PX - rect.size.y) * 0.5)
		rect = rect.grow_individual(grow_x, grow_y, grow_x, grow_y)
	return rect
