extends Node

## Node that adds expanding functionality to a control when hovered
## This node should be a child of a Control node
## 
## The parent control will be used to detect mouse enter/exit events.
## By default, the parent control will also be the one that expands.
## You can optionally set target_control to expand a different control instead.

@export_group("Expand Settings")
## The scale factor to apply when the control is hovered.
## Values greater than 1.0 will expand the control, creating a zoom-in effect.
@export var expand_scale: Vector2 = Vector2(1.05, 1.05)

## Duration in seconds for the expand animation when mouse enters.
## Lower values create snappier animations.
@export var expand_duration: float = 0.2

## If enabled, modifies custom_minimum_size instead of scale property.
## Useful when scale changes would affect child nodes undesirably.
@export var use_minimum_size: bool = false

## Duration in seconds for the return animation when mouse exits.
## Lower values create snappier animations.
@export var return_duration: float = 0.2

@export_group("Animation Settings")
## The transition curve type for the animation.
## Determines how the animation accelerates and decelerates.
@export var tween_type: Tween.TransitionType = Tween.TRANS_CUBIC

## The easing direction for the transition.
## Controls whether the transition eases in, out, or both.
@export var tween_ease: Tween.EaseType = Tween.EASE_OUT

## Optional control to animate instead of the parent.
## If not set, the parent control will be animated.
@export var target_control: Control
var parent_control: Control
var active_control: Control
var original_scale: Vector2
var original_min_size: Vector2
var tween: Tween
var is_hovered: bool = false

func _ready() -> void:
	# Check if parent is a control
	var parent: Node = get_parent()
	if not parent or not parent is Control:
		push_error("ExpandHoveredControlModule: Parent node must be a Control. Current parent: " + str(parent))
		queue_free()
		return
	
	parent_control = parent as Control
	
	# Determine which control to use
	if target_control and target_control is Control:
		active_control = target_control
	else:
		active_control = parent_control
	
	original_scale = active_control.scale
	
	if use_minimum_size:
		active_control.custom_minimum_size = active_control.size
	
	original_min_size = active_control.custom_minimum_size
	
	# Set initial pivot offset to center
	_update_pivot_offset()
	
	# Connect control signals
	parent_control.mouse_entered.connect(_on_mouse_entered)
	parent_control.mouse_exited.connect(_on_mouse_exited)
	
	# Connect to size changes to update pivot
	active_control.resized.connect(_update_pivot_offset)

func _on_mouse_entered() -> void:
	is_hovered = true
	
	# Cancel any existing tween
	if tween and tween.is_running():
		tween.kill()
	
	# Create expand animation
	tween = create_tween()
	tween.set_trans(tween_type)
	tween.set_ease(tween_ease)
	if use_minimum_size:
		var current_min_size: Vector2 = active_control.size
		var target_min_size: Vector2 = current_min_size * expand_scale
		tween.tween_property(active_control, "custom_minimum_size", target_min_size, expand_duration)
	else:
		tween.tween_property(active_control, "scale", expand_scale, expand_duration)

func _on_mouse_exited() -> void:
	is_hovered = false
	
	# Cancel any existing tween
	if tween and tween.is_running():
		tween.kill()
	
	# Create return animation
	tween = create_tween()
	tween.set_trans(tween_type)
	tween.set_ease(tween_ease)
	if use_minimum_size:
		tween.tween_property(active_control, "custom_minimum_size", original_min_size, return_duration)
	else:
		tween.tween_property(active_control, "scale", original_scale, return_duration)

func _update_pivot_offset() -> void:
	# Update pivot offset to center of the control
	if active_control:
		active_control.pivot_offset = active_control.size / 2.0

func _exit_tree() -> void:
	# Clean up connections if parent still exists
	if parent_control and not parent_control.is_queued_for_deletion():
		if parent_control.mouse_entered.is_connected(_on_mouse_entered):
			parent_control.mouse_entered.disconnect(_on_mouse_entered)
		if parent_control.mouse_exited.is_connected(_on_mouse_exited):
			parent_control.mouse_exited.disconnect(_on_mouse_exited)
	
	# Clean up active control connections
	if active_control and not active_control.is_queued_for_deletion():
		# Disconnect resized signal if connected
		if active_control.resized.is_connected(_update_pivot_offset):
			active_control.resized.disconnect(_update_pivot_offset)
