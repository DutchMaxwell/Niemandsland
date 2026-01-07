extends Node

## Node that adds flip functionality to a button when pressed
## This node should be a child of a Button node

@export_group("Flip Settings")
@export_enum("X", "Y") var flip_axis: int = 0 ## Choose whether to flip on X or Y axis
@export var flip_duration: float = 0.3 ## Total duration of the flip animation in seconds
@export var return_on_release: bool = true ## Whether to return to normal when button is released

@export_group("Animation Settings")
@export var tween_type: Tween.TransitionType = Tween.TRANS_CUBIC ## Type of interpolation
@export var tween_ease: Tween.EaseType = Tween.EASE_IN_OUT ## Easing type for the animation

var parent_button: BaseButton
var original_scale: Vector2
var tween: Tween
var is_flipped: bool = false

func _ready() -> void:
	# Check if parent is a button
	var parent: Node = get_parent()
	if not parent or not parent is BaseButton:
		push_error("FlipPressedButtonModule: Parent node must be a Button. Current parent: " + str(parent))
		queue_free()
		return
	
	parent_button = parent as BaseButton
	original_scale = parent_button.scale
	
	# Set initial pivot offset to center
	_update_pivot_offset()
	
	# Connect button signals
	parent_button.button_down.connect(_on_button_down)
	parent_button.button_up.connect(_on_button_up)
	
	# Connect to size changes to update pivot
	if parent_button is Control:
		var control: Control = parent_button as Control
		control.resized.connect(_update_pivot_offset)

func _on_button_down() -> void:
	# Cancel any existing tween
	if tween and tween.is_running():
		tween.kill()
	
	# Create flip animation
	tween = create_tween()
	tween.set_trans(tween_type)
	tween.set_ease(tween_ease)
	
	# Determine target scale based on flip axis
	var target_scale: Vector2 = original_scale
	if flip_axis == 0:  # X axis
		target_scale.x = 0
	else:  # Y axis
		target_scale.y = 0
	
	# Perform the flip animation: shrink to 0, then grow back
	tween.tween_property(parent_button, "scale", target_scale, flip_duration / 2)
	tween.tween_property(parent_button, "scale", original_scale, flip_duration / 2)
	
	is_flipped = true

func _on_button_up() -> void:
	# Only react if return_on_release is enabled
	if not return_on_release:
		return
	
	# Cancel any existing tween
	if tween and tween.is_running():
		tween.kill()
	
	# Return to original scale
	tween = create_tween()
	tween.set_trans(tween_type)
	tween.set_ease(tween_ease)
	tween.tween_property(parent_button, "scale", original_scale, flip_duration / 4)
	
	is_flipped = false

func _update_pivot_offset() -> void:
	# Update pivot offset to center of the button
	if parent_button is Control:
		var control: Control = parent_button as Control
		control.pivot_offset = control.size / 2.0

func _exit_tree() -> void:
	# Clean up connections if parent still exists
	if parent_button and not parent_button.is_queued_for_deletion():
		if parent_button.button_down.is_connected(_on_button_down):
			parent_button.button_down.disconnect(_on_button_down)
		if parent_button.button_up.is_connected(_on_button_up):
			parent_button.button_up.disconnect(_on_button_up)
		
		# Disconnect resized signal if connected
		if parent_button is Control:
			var control: Control = parent_button as Control
			if control.resized.is_connected(_update_pivot_offset):
				control.resized.disconnect(_update_pivot_offset)
