extends Control

## Background darkened color rectangle that covers the entire screen
@export var background_darkened_color_rect: ColorRect

## Mask panel that highlights the parent area
@export var mask_panel: Panel

## Canvas group for proper positioning relative to global coordinates
@export var canvas_group: CanvasGroup


func _ready() -> void:
	# Validate export variables
	_validate_export_variables()
	
	# Defer setup to next frame to allow containers to compute sizes
	await get_tree().process_frame
	
	# Adjust canvas group position to compensate for global position
	_setup_canvas_group()
	
	# Configure the background and mask panel after container computation
	_setup_background_darkening()
	_setup_mask_panel()
	
	# Connect to viewport size changes to maintain full screen coverage
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _validate_export_variables() -> void:
	if not background_darkened_color_rect:
		push_error("Tutorial Fairy UI Highlight Panel: background_darkened_color_rect is not assigned! Please assign a ColorRect node to the 'Background Darkened Color Rect' export variable in the Inspector.")
	
	if not mask_panel:
		push_error("Tutorial Fairy UI Highlight Panel: mask_panel is not assigned! Please assign a Panel node to the 'Mask Panel' export variable in the Inspector.")
	
	if not canvas_group:
		print("Tutorial Fairy UI Highlight Panel: canvas_group is not assigned - Canvas group positioning disabled")


## Setup the canvas group position to compensate for global position
func _setup_canvas_group() -> void:
	if not canvas_group:
		return
	
	# Set canvas group position to negative of parent's global position
	# This makes the canvas group's content align with screen coordinates
	canvas_group.position = Vector2.ZERO - global_position


## Setup the background darkening to cover the entire screen
func _setup_background_darkening() -> void:
	if not background_darkened_color_rect:
		return
	
	# Get the viewport size
	var viewport_size: Vector2 = get_viewport().size
	
	# Set the ColorRect to cover the entire screen
	background_darkened_color_rect.size = viewport_size
	background_darkened_color_rect.position = Vector2.ZERO


## Setup the mask panel to match the parent's size and global position
func _setup_mask_panel() -> void:
	if not mask_panel:
		return
	
	# Get the parent node (the one this script is attached to)
	var parent_node: Control = self
	
	# Since the mask panel is under a Node2D, we need to handle positioning differently
	# Get the global position and size of the parent control
	var global_pos: Vector2 = parent_node.global_position
	var parent_size: Vector2 = parent_node.size
	
	# Set the mask panel size to match the parent
	mask_panel.size = parent_size
	
	# Set the mask panel position to the global position
	# Since it's under a Node2D, we need to convert from Control's global position
	if mask_panel.get_parent() is Node2D:
		var parent_2d: Node2D = mask_panel.get_parent() as Node2D
		# Convert the Control's global position to the Node2D's local space
		mask_panel.position = parent_2d.to_local(global_pos)
	else:
		# If it's not under a Node2D, just use the global position
		mask_panel.global_position = global_pos


## Update sizes when viewport changes
func _on_viewport_size_changed() -> void:
	_setup_background_darkening()


## Update the mask panel position and size in process to follow the parent
func _process(_delta: float) -> void:
	if not mask_panel:
		return
	
	# Continuously update the mask panel to match parent's global position and size
	var global_pos: Vector2 = global_position
	var parent_size: Vector2 = size
	
	# Update mask panel size
	mask_panel.size = parent_size
	
	# Update mask panel position based on parent type
	if mask_panel.get_parent() is Node2D:
		var parent_2d: Node2D = mask_panel.get_parent() as Node2D
		mask_panel.position = parent_2d.to_local(global_pos)
	else:
		mask_panel.global_position = global_pos


## Show the highlight effect
func show_highlight() -> void:
	show()
	_setup_background_darkening()
	_setup_mask_panel()


## Hide the highlight effect
func hide_highlight() -> void:
	hide()
