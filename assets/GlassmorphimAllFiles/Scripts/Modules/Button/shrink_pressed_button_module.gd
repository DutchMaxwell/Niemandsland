extends Node

## Node that adds shrinking functionality to a button when pressed
## This node should be a child of a Button node

@export_group("Shrink Settings")
## The scale factor to apply when the button is pressed.
## Values less than 1.0 will shrink the button, creating a pressed effect.
@export var shrink_scale: Vector2 = Vector2(0.95, 0.95)

## Duration in seconds for the shrink animation when button is pressed.
## Lower values create snappier animations.
@export var shrink_duration: float = 0.1

## If enabled, modifies custom_minimum_size instead of scale property.
## Useful when scale changes would affect child nodes undesirably.
@export var use_minimum_size: bool = false

## Duration in seconds for the return animation when button is released.
## Lower values create snappier animations.
@export var return_duration: float = 0.1

@export_group("Animation Settings")
## The transition curve type for the animation.
## Determines how the animation accelerates and decelerates.
@export var tween_type: Tween.TransitionType = Tween.TRANS_EXPO

## The easing direction for the transition.
## Controls whether the transition eases in, out, or both.
@export var tween_ease: Tween.EaseType = Tween.EASE_OUT

var parent_button: BaseButton
var original_scale: Vector2
var original_min_size: Vector2
var original_size: Vector2
var tween: Tween

func _ready() -> void:
	# Check if parent is a button
	var parent: Node = get_parent()
	if not parent or not parent is BaseButton:
		push_error("ShrinkPressedButtonModule: Parent node must be a Button. Current parent: " + str(parent))
		queue_free()
		return
	
	parent_button = parent as BaseButton
	original_scale = parent_button.scale
	if parent_button is Control:
		original_min_size = (parent_button as Control).custom_minimum_size
		original_size = (parent_button as Control).size
	
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
	
	# Create shrink animation
	tween = create_tween()
	tween.set_trans(tween_type)
	tween.set_ease(tween_ease)
	if use_minimum_size and parent_button is Control:
		var control: Control = parent_button as Control
		var current_size: Vector2 = control.size
		var target_size: Vector2 = current_size * shrink_scale
		var target_min_size: Vector2 = control.custom_minimum_size * shrink_scale
		# Tween both minimum size and actual size
		tween.tween_property(control, "custom_minimum_size", target_min_size, shrink_duration)
		tween.parallel().tween_property(control, "size", target_size, shrink_duration)
	else:
		tween.tween_property(parent_button, "scale", shrink_scale, shrink_duration)

func _on_button_up() -> void:
	# Cancel any existing tween
	if tween and tween.is_running():
		tween.kill()
	
	# Create return animation
	tween = create_tween()
	tween.set_trans(tween_type)
	tween.set_ease(tween_ease)
	if use_minimum_size and parent_button is Control:
		var control: Control = parent_button as Control
		# Tween both minimum size and actual size back to original
		tween.tween_property(control, "custom_minimum_size", original_min_size, return_duration)
		tween.parallel().tween_property(control, "size", original_size, return_duration)
	else:
		tween.tween_property(parent_button, "scale", original_scale, return_duration)

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
