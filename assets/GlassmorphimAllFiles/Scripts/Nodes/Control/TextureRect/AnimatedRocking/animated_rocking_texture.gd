extends Control

## The horizontal distance in pixels the texture will move from its starting position during the rocking animation.
## Higher values create wider rocking movements.
## More rock distance means more stretch textures.
@export var rock_distance: float = 50.0

## The duration in seconds for one complete movement from left to right or right to left.
## A full rocking cycle (left to right and back) takes twice this duration.
@export var rock_duration: float = 2.0

## If enabled, the rocking animation will start automatically when the scene is ready.
## Disable this if you want to control when the animation starts via code.
@export var auto_start: bool = true

## If enabled, automatically resizes the control to accommodate the rocking distance.
## This ensures the texture has enough space to move without being clipped.
@export var auto_resize: bool = true

# Interpolation settings
@export_group("Interpolation")
## The transition curve type for the rocking animation.
## Determines how the movement accelerates and decelerates.
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic", "Cubic", "Circ", "Bounce", "Back", "Spring") var transition_type: int = 1  # Default to Sine

## The easing direction for the transition.
## Controls whether the transition eases in, out, or both.
@export_enum("In", "Out", "In Out", "Out In") var ease_type: int = 2  # Default to In Out

var tween: Tween
var original_size: Vector2
var original_position: Vector2

func _ready() -> void:
	call_deferred(&"_deferred_ready")


func _deferred_ready() -> void:
	# Store the current size before changing layout mode
	var preserved_size: Vector2 = size
	
	# Change layout mode to position (0 = PRESET_TOP_LEFT, which is position mode)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	
	# Apply the preserved size after changing to position mode
	custom_minimum_size = preserved_size
	
	# Store original size and position
	original_size = custom_minimum_size
	original_position = position
	
	# Auto-resize if enabled
	if auto_resize:
		_resize_for_rocking()
	
	if auto_start:
		start_rocking()

func _resize_for_rocking() -> void:
	# Use the control's current size instead of viewport
	var control_size: Vector2 = original_size
	
	# Calculate the new expanded width
	var new_width: float = control_size.x + (rock_distance * 2)
	size.x = new_width
	
	# Calculate leftmost position: original_size - new_size
	# This will be negative since new_size > original_size
	position.x = control_size.x - new_width
	
	# Keep the height the same as the original control height
	size.y = control_size.y

func _get_transition_type() -> int:
	# Convert enum index to Tween transition constant
	var transitions: Array[int] = [
		Tween.TRANS_LINEAR,
		Tween.TRANS_SINE,
		Tween.TRANS_QUINT,
		Tween.TRANS_QUART,
		Tween.TRANS_QUAD,
		Tween.TRANS_EXPO,
		Tween.TRANS_ELASTIC,
		Tween.TRANS_CUBIC,
		Tween.TRANS_CIRC,
		Tween.TRANS_BOUNCE,
		Tween.TRANS_BACK,
		Tween.TRANS_SPRING
	]
	return transitions[transition_type]

func _get_ease_type() -> int:
	# Convert enum index to Tween ease constant
	var eases: Array[int] = [
		Tween.EASE_IN,
		Tween.EASE_OUT,
		Tween.EASE_IN_OUT,
		Tween.EASE_OUT_IN
	]
	return eases[ease_type]

func start_rocking() -> void:
	# Kill any existing tween
	if tween:
		tween.kill()
	
	# Create a new tween that loops forever
	tween = create_tween()
	tween.set_loops()
	
	# Define positions:
	# Left position = original_size - new_size (negative value)
	# Right position = 0 (far right of the panel)
	var left_position: float = position.x  # This is already set in _resize_for_rocking
	var right_position: float = 0
	
	# Get the selected interpolation settings
	var trans: int = _get_transition_type()
	var easing_mode: int = _get_ease_type()
	
	# Rock from left to right with selected interpolation
	tween.tween_property(self, "position:x", right_position, rock_duration).set_trans(trans).set_ease(easing_mode)
	
	# Rock from right back to left with selected interpolation
	tween.tween_property(self, "position:x", left_position, rock_duration).set_trans(trans).set_ease(easing_mode)
	
func stop_rocking() -> void:
	if tween:
		tween.kill()
		tween = null

func _exit_tree() -> void:
	stop_rocking()
