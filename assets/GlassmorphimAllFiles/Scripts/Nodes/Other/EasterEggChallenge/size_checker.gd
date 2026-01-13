extends Node

enum CheckMode {
	CHECK_X,
	CHECK_Y,
	CHECK_BOTH
}

enum DirectionMode {
	GROWING,  # Trigger when size grows to target
	SHRINKING  # Trigger when size shrinks to target
}

## The mode for checking size - X only, Y only, or both
@export var check_mode: CheckMode = CheckMode.CHECK_BOTH

## The direction to check from - growing or shrinking
@export var direction_mode: DirectionMode = DirectionMode.GROWING

## Target size for both X and Y (used when check_mode is CHECK_BOTH)
@export var target_size_2d: Vector2 = Vector2(100, 100)

## Target size for single axis (used when check_mode is CHECK_X or CHECK_Y)
@export var target_size_float: float = 100.0

## Tolerance for size comparison to avoid floating point issues
@export var tolerance: float = 0.1

## Enable/disable the size checker
@export var enabled: bool = true

## Emitted when the target size is reached
signal size_reached()

## Emitted when size changes with details
signal size_changed(new_size: Vector2, old_size: Vector2)

var _previous_size: Vector2 = Vector2.ZERO
var _has_triggered: bool = false  # Flag to ensure we only trigger once
var _initial_size: Vector2 = Vector2.ZERO
var _parent_control: Control = null


func _ready() -> void:
	# Check if parent is a Control node
	var parent: Node = get_parent()
	if parent and parent is Control:
		_parent_control = parent as Control
		_initial_size = _parent_control.size
		_previous_size = _parent_control.size
	else:
		push_error("SizeChecker: Parent node must be a Control node. Disabling size checker.")
		enabled = false


func _process(_delta: float) -> void:
	if not enabled:
		return
	
	# Safety check
	if not _parent_control:
		return
	
	var current_size: Vector2 = _parent_control.size
	
	# Check if size changed
	if not current_size.is_equal_approx(_previous_size):
		size_changed.emit(current_size, _previous_size)
	
	# Check if we've already triggered
	if _has_triggered:
		_previous_size = current_size
		return
	
	# Simple comparison based on mode
	var should_trigger: bool = false
	
	match check_mode:
		CheckMode.CHECK_X:
			if direction_mode == DirectionMode.GROWING:
				should_trigger = current_size.x > target_size_float
			else:  # SHRINKING
				should_trigger = current_size.x < target_size_float
				
		CheckMode.CHECK_Y:
			if direction_mode == DirectionMode.GROWING:
				should_trigger = current_size.y > target_size_float
			else:  # SHRINKING
				should_trigger = current_size.y < target_size_float
				
		CheckMode.CHECK_BOTH:
			if direction_mode == DirectionMode.GROWING:
				should_trigger = current_size.x > target_size_2d.x and current_size.y > target_size_2d.y
			else:  # SHRINKING
				should_trigger = current_size.x < target_size_2d.x and current_size.y < target_size_2d.y
	
	if should_trigger:
		_has_triggered = true
		size_reached.emit()
		print("Size Reached!")
	
	_previous_size = current_size




## Reset the checker to allow it to trigger again
func reset() -> void:
	_has_triggered = false
	if _parent_control:
		_previous_size = _parent_control.size


## Get the current progress towards the target (0.0 to 1.0)
func get_progress() -> float:
	if not _parent_control:
		return 0.0
	
	var current_size: Vector2 = _parent_control.size
	
	match check_mode:
		CheckMode.CHECK_X:
			if _initial_size.x == target_size_float:
				return 1.0
			return clamp((current_size.x - _initial_size.x) / (target_size_float - _initial_size.x), 0.0, 1.0)
		CheckMode.CHECK_Y:
			if _initial_size.y == target_size_float:
				return 1.0
			return clamp((current_size.y - _initial_size.y) / (target_size_float - _initial_size.y), 0.0, 1.0)
		CheckMode.CHECK_BOTH:
			var x_progress: float = 1.0
			var y_progress: float = 1.0
			
			if _initial_size.x != target_size_2d.x:
				x_progress = clamp((current_size.x - _initial_size.x) / (target_size_2d.x - _initial_size.x), 0.0, 1.0)
			
			if _initial_size.y != target_size_2d.y:
				y_progress = clamp((current_size.y - _initial_size.y) / (target_size_2d.y - _initial_size.y), 0.0, 1.0)
			
			return min(x_progress, y_progress)
	
	return 0.0


## Get the parent control if it exists
func get_parent_control() -> Control:
	return _parent_control


## Check if the size checker is properly configured with a Control parent
func is_valid() -> bool:
	return _parent_control != null


## Get current size of the parent control (returns Vector2.ZERO if no valid parent)
func get_current_size() -> Vector2:
	if _parent_control:
		return _parent_control.size
	return Vector2.ZERO


## Get the target size based on current check mode
func get_target_size() -> Vector2:
	match check_mode:
		CheckMode.CHECK_X:
			return Vector2(target_size_float, get_current_size().y)
		CheckMode.CHECK_Y:
			return Vector2(get_current_size().x, target_size_float)
		CheckMode.CHECK_BOTH:
			return target_size_2d
	return Vector2.ZERO


## Called when parent node changes
func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		# Re-check parent when node is re-parented
		var parent: Node = get_parent()
		if parent and parent is Control:
			_parent_control = parent as Control
			_initial_size = _parent_control.size
			_previous_size = _parent_control.size
			enabled = true
		else:
			push_error("SizeChecker: Parent node must be a Control node. Disabling size checker.")
			_parent_control = null
			enabled = false
