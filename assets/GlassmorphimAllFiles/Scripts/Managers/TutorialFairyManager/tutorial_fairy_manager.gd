extends Control

## Tutorial fairy sprite control node
@export var tutorial_fairy_sprite: Control

## Fairy navigation path line
@export var fairy_navigation: Line2D

## Array of UI highlight reference rectangles
@export var ui_highlights: Array[ReferenceRect] = []

## Packed scene to instantiate as child of UI highlights
@export var highlight_effect_scene: PackedScene

## Background darkening ColorRect that gets removed on first fairy click
@export var background_darken_rect: ColorRect

## Container node that holds all TutorialFairyChatBoxParent nodes
@export var chat_boxes_container: Control

## Duration for the final fade-out animation in seconds
@export var fade_out_duration: float = 1.0

## Control node that appears when hovering over the fairy sprite
@export var fairy_sprite_hover_effect: Control

## Color to temporarily apply to fairy when clicked
@export var fairy_click_color: Color = Color.WHITE

## Duration for hover effect fade in/out
@export var hover_fade_duration: float = 0.3

## Minimum time between fairy clicks in seconds
@export var click_cooldown_duration: float = 0.5

## Button that allows the user to skip the tutorial
@export var skip_button: Button

## Array of controls to fade out immediately when fairy starts fading
@export var early_fade_controls: Array[Control] = []

## Duration for the early fade controls in seconds
@export var early_fade_duration: float = 0.5

## Current navigation point index
var current_navigation_index: int = 0

## Note: Chat box parents are indexed by navigation point, not separately tracked

## Duration of the tween animation in seconds
@export var tween_duration: float = 0.8

## Tween for fairy movement
var movement_tween: Tween

## Node to control X-axis idle animation
@export var idle_x_axis_node: Control

## Node to control Y-axis idle animation
@export var idle_y_axis_node: Control

## Distance for X-axis idle movement
@export var idle_x_distance: float = 10.0

## Distance for Y-axis idle movement
@export var idle_y_distance: float = 15.0

## Duration for X-axis idle animation cycle
@export var idle_x_duration: float = 2.0

## Duration for Y-axis idle animation cycle
@export var idle_y_duration: float = 1.5

## Tween for X-axis idle animation
var idle_x_tween: Tween

## Tween for Y-axis idle animation
var idle_y_tween: Tween

## Whether idle animation is currently active
var idle_animation_active: bool = false

## Track if this is the first fairy click
var is_first_click: bool = true

## Tween for final fade-out animation
var fade_out_tween: Tween

## Track if we're waiting for chat box parent to finish
var waiting_for_chat_box_parent: bool = false

## Array of chat box parents found in the container (populated at runtime)
var chat_box_parents: Array[TutorialFairyChatBoxParent] = []

## Tween for color flash effect when fairy is clicked
var color_flash_tween: Tween

## Original modulate color of the fairy sprite
var original_fairy_color: Color = Color.WHITE

## Tween for hover effect fade animation
var hover_fade_tween: Tween

## State management for preventing conflicting operations
enum FairyState {
	IDLE,
	MOVING,
	SHOWING_CHAT,
	FADING_OUT
}

## Current state of the fairy system
var current_state: FairyState = FairyState.IDLE

## Flag to prevent rapid clicking
var can_click: bool = true

## Timer for click cooldown
var click_cooldown_timer: float = 0.0

## Flag to indicate if we're in a transition
var is_transitioning: bool = false


func _ready() -> void:
	# Check for required export variables and provide helpful error messages
	_validate_export_variables()
	
	# Connect the fairy sprite's gui_input signal for click detection
	if tutorial_fairy_sprite and not tutorial_fairy_sprite.gui_input.is_connected(_on_fairy_gui_input):
		tutorial_fairy_sprite.gui_input.connect(_on_fairy_gui_input)
		# Store original color
		original_fairy_color = tutorial_fairy_sprite.modulate
	
	# Setup hover functionality
	_setup_hover_functionality()
	
	# Setup skip button functionality
	_setup_skip_button()
	
	# Collect chat box parents from container
	_collect_chat_box_parents()
	
	# Hide all chat box parents first (in case they're visible in the editor)
	_hide_all_chat_box_parents()
	
	# Initialize chat box parents (show first one if it exists)
	_initialize_chat_box_parents()
	
	# Start idle animation if nodes are assigned
	start_idle_animation()


## Process function to handle click cooldown
func _process(delta: float) -> void:
	if click_cooldown_timer > 0:
		click_cooldown_timer -= delta
		if click_cooldown_timer <= 0:
			can_click = true


## Move the fairy to the next navigation point
func go_to_next_navigation() -> void:
	if not tutorial_fairy_sprite:
		push_error("Tutorial Fairy Manager: tutorial_fairy_sprite is not assigned! Please assign a Control node to the 'Tutorial Fairy Sprite' export variable in the Inspector.")
		return
	
	if not fairy_navigation:
		push_error("Tutorial Fairy Manager: fairy_navigation is not assigned! Please assign a Line2D node to the 'Fairy Navigation' export variable in the Inspector.")
		return
	
	# Check if we're already in a transition
	if is_transitioning:
		return
	
	# Check if we're in a valid state to move
	if current_state != FairyState.IDLE and current_state != FairyState.SHOWING_CHAT:
		return
	
	# Check if tween is already running
	if movement_tween and movement_tween.is_running():
		return
	
	# Check if fade out is already running
	if fade_out_tween and fade_out_tween.is_running():
		return
	
	if current_navigation_index >= fairy_navigation.get_point_count():
		# No more navigation points - trigger fade out and cleanup
		_start_fade_out_and_cleanup()
		return
	
	# Set transitioning flag and state
	is_transitioning = true
	current_state = FairyState.MOVING
	
	# Remove background darkening when first navigation happens
	if is_first_click and background_darken_rect:
		background_darken_rect.queue_free()
		is_first_click = false
	
	# Stop idle animation during movement
	stop_idle_animation()
	
	# Remove highlight from previous UI element if it exists
	if current_navigation_index > 0:
		_remove_highlight_from_ui_element(current_navigation_index - 1)
	
	# Add highlight effect to the current UI element BEFORE moving
	_add_highlight_to_ui_element(current_navigation_index)
	
	# Reset idle animation nodes to neutral position before movement
	if idle_x_axis_node:
		idle_x_axis_node.position.x = 0
	if idle_y_axis_node:
		idle_y_axis_node.position.y = 0
	
	# Get target position for next navigation point
	var navigation_point: Vector2 = fairy_navigation.to_global(fairy_navigation.get_point_position(current_navigation_index))
	# Adjust position so fairy's center lands on the point
	var target_position: Vector2 = navigation_point - (tutorial_fairy_sprite.size / 2.0)
	
	# Simultaneously start showing the next chat box parent (if it exists)
	# This happens at the same time as the fairy movement
	var next_index: int = current_navigation_index + 1
	if next_index < chat_box_parents.size():
		var next_parent: TutorialFairyChatBoxParent = chat_box_parents[next_index]
		if next_parent:
			# Hide all other parents first
			for i: int in chat_box_parents.size():
				if i != next_index and chat_box_parents[i] and chat_box_parents[i].visible:
					# Keep fading if already fading, otherwise hide immediately
					if chat_box_parents[i].modulate.a < 1.0:
						continue  # Let existing fade continue
					chat_box_parents[i].visible = false
					chat_box_parents[i].modulate.a = 0.0
			
			# Reset and start fading in the next parent
			next_parent.reset()
			next_parent.visible = true
			next_parent.modulate.a = 0.0
			
			# Set the waiting flag immediately to prevent double-showing
			waiting_for_chat_box_parent = true
			
			# Create fade in tween for next parent
			var fade_in_tween: Tween = create_tween()
			fade_in_tween.tween_property(next_parent, "modulate:a", 1.0, 0.5)
			fade_in_tween.tween_callback(func() -> void:
				# Only show the chat box if we haven't already shown it
				if next_parent.visible and not next_parent.get_child_count() > 0:
					next_parent.show_chat_box(0)
			)
	
	# Create and configure tween with elastic interpolation for fairy movement
	movement_tween = create_tween()
	movement_tween.set_ease(Tween.EASE_OUT)
	movement_tween.set_trans(Tween.TRANS_ELASTIC)
	
	# Animate the fairy sprite to the target position
	movement_tween.tween_property(tutorial_fairy_sprite, "global_position", target_position, tween_duration)
	
	# Connect to finished signal to handle completion
	movement_tween.finished.connect(_on_tween_finished)


## Called when tween animation finishes
func _on_tween_finished() -> void:
	# Move to next navigation point index
	current_navigation_index += 1
	
	# Clear transitioning flag and update state
	is_transitioning = false
	current_state = FairyState.IDLE
	
	# Resume idle animation after movement
	start_idle_animation()
	
	# Wait for user to click fairy to continue


## Add highlight effect to UI element at given index
func _add_highlight_to_ui_element(index: int) -> void:
	if not highlight_effect_scene:
		push_error("Tutorial Fairy Manager: highlight_effect_scene is not assigned! Please assign a PackedScene to the 'Highlight Effect Scene' export variable in the Inspector.")
		return
	
	if index >= ui_highlights.size():
		return # No corresponding UI highlight for this navigation point
	
	var ui_element: ReferenceRect = ui_highlights[index]
	if not ui_element:
		return
	
	# Instantiate and add highlight effect as child
	var highlight_instance: Node = highlight_effect_scene.instantiate()
	ui_element.add_child(highlight_instance)


## Remove highlight effect from UI element at given index
func _remove_highlight_from_ui_element(index: int) -> void:
	if index >= ui_highlights.size() or index < 0:
		return
	
	var ui_element: ReferenceRect = ui_highlights[index]
	if not ui_element:
		return
	
	# Remove all children (highlight effects) from this UI element
	for child: Node in ui_element.get_children():
		child.queue_free()


## Reset the fairy navigation to start from the beginning
func reset_navigation() -> void:
	current_navigation_index = 0
	waiting_for_chat_box_parent = false
	
	# Reset state flags
	is_first_click = true
	is_transitioning = false
	current_state = FairyState.IDLE
	can_click = true
	click_cooldown_timer = 0.0
	
	# Stop any running tween
	if movement_tween and movement_tween.is_running():
		movement_tween.kill()
	
	# Stop idle animation
	stop_idle_animation()
	
	# Clear all highlight effects from UI elements
	for ui_element: ReferenceRect in ui_highlights:
		if ui_element:
			for child: Node in ui_element.get_children():
				child.queue_free()
	
	# Reset chat box parents - recollect, hide all, then initialize
	_collect_chat_box_parents()
	_hide_all_chat_box_parents()
	_initialize_chat_box_parents()
	
	# Reset fairy position to first navigation point
	if tutorial_fairy_sprite and fairy_navigation and fairy_navigation.get_point_count() > 0:
		var initial_position: Vector2 = fairy_navigation.to_global(fairy_navigation.get_point_position(0))
		# Center the fairy sprite on the point
		tutorial_fairy_sprite.global_position = initial_position - (tutorial_fairy_sprite.size / 2.0)
	
	# Reset idle animation nodes
	if idle_x_axis_node:
		idle_x_axis_node.position.x = 0
	if idle_y_axis_node:
		idle_y_axis_node.position.y = 0
	
	# Restart idle animation
	start_idle_animation()


## Handle input events on the fairy sprite
func _on_fairy_gui_input(event: InputEvent) -> void:
	# Check for left mouse button click
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# Check if we can process the click
			if not can_click:
				return
			
			# Check if we're in a valid state to handle clicks
			if current_state == FairyState.FADING_OUT:
				return
			
			# Check if we're already transitioning
			if is_transitioning and current_state == FairyState.MOVING:
				return
			
			# Start click cooldown
			can_click = false
			click_cooldown_timer = click_cooldown_duration
			
			# Flash the fairy with the click color
			_flash_fairy_color()
			# Handle chat box progression
			_handle_chat_box_progression()


## Validate that all required export variables are assigned
func _validate_export_variables() -> void:
	if not tutorial_fairy_sprite:
		push_error("Tutorial Fairy Manager: tutorial_fairy_sprite is not assigned! Please assign a Control node to the 'Tutorial Fairy Sprite' export variable in the Inspector.")
	
	if not fairy_navigation:
		push_error("Tutorial Fairy Manager: fairy_navigation is not assigned! Please assign a Line2D node to the 'Fairy Navigation' export variable in the Inspector.")
	else:
		if fairy_navigation.get_point_count() == 0:
			push_error("Tutorial Fairy Manager: fairy_navigation Line2D has no points! Please add navigation points to the Line2D node.")
	
	if ui_highlights.is_empty():
		push_error("Tutorial Fairy Manager: ui_highlights array is empty! Please add ReferenceRect nodes to the 'UI Highlights' export variable array in the Inspector.")
	else:
		# Check for null entries in the array
		for i: int in ui_highlights.size():
			if not ui_highlights[i]:
				push_error("Tutorial Fairy Manager: ui_highlights[%d] is null! Please assign a ReferenceRect node to this array element in the Inspector." % i)
	
	if not highlight_effect_scene:
		push_error("Tutorial Fairy Manager: highlight_effect_scene is not assigned! Please assign a PackedScene to the 'Highlight Effect Scene' export variable in the Inspector.")
	
	# Optional nodes - validation complete, no debug prints needed


## Start the idle floating animation
func start_idle_animation() -> void:
	if idle_animation_active:
		return
	
	idle_animation_active = true
	
	# Start X-axis idle animation
	if idle_x_axis_node and idle_x_distance > 0:
		_create_x_axis_idle_tween()
	
	# Start Y-axis idle animation
	if idle_y_axis_node and idle_y_distance > 0:
		_create_y_axis_idle_tween()


## Stop the idle floating animation
func stop_idle_animation() -> void:
	idle_animation_active = false
	
	# Stop X-axis tween
	if idle_x_tween and idle_x_tween.is_running():
		idle_x_tween.kill()
		idle_x_tween = null
	
	# Stop Y-axis tween
	if idle_y_tween and idle_y_tween.is_running():
		idle_y_tween.kill()
		idle_y_tween = null


## Create and start X-axis idle tween
func _create_x_axis_idle_tween() -> void:
	if not idle_animation_active or not idle_x_axis_node:
		return
	
	idle_x_tween = create_tween()
	idle_x_tween.set_loops()
	idle_x_tween.set_trans(Tween.TRANS_SINE)
	idle_x_tween.set_ease(Tween.EASE_IN_OUT)
	
	# Animate from current position to positive distance
	idle_x_tween.tween_property(idle_x_axis_node, "position:x", idle_x_distance, idle_x_duration / 2.0)
	# Then back to negative distance
	idle_x_tween.tween_property(idle_x_axis_node, "position:x", -idle_x_distance, idle_x_duration / 2.0)


## Create and start Y-axis idle tween
func _create_y_axis_idle_tween() -> void:
	if not idle_animation_active or not idle_y_axis_node:
		return
	
	idle_y_tween = create_tween()
	idle_y_tween.set_loops()
	idle_y_tween.set_trans(Tween.TRANS_SINE)
	idle_y_tween.set_ease(Tween.EASE_IN_OUT)
	
	# Animate from current position to positive distance
	idle_y_tween.tween_property(idle_y_axis_node, "position:y", idle_y_distance, idle_y_duration / 2.0)
	# Then back to negative distance
	idle_y_tween.tween_property(idle_y_axis_node, "position:y", -idle_y_distance, idle_y_duration / 2.0)


## Start fade out animation and cleanup when complete
func _start_fade_out_and_cleanup() -> void:
	# Set state to fading out
	current_state = FairyState.FADING_OUT
	is_transitioning = true
	
	# Set mouse filter to ignore so clicks pass through during fade-out
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Fade out all early fade controls immediately
	for control: Control in early_fade_controls:
		if control:
			var control_fade: Tween = create_tween()
			control_fade.set_ease(Tween.EASE_IN_OUT)
			control_fade.set_trans(Tween.TRANS_CUBIC)
			control_fade.tween_property(control, "modulate:a", 0.0, early_fade_duration)
			control_fade.tween_callback(func() -> void: 
				if control:
					control.visible = false
			)
	
	# Stop idle animation during fade out
	stop_idle_animation()
	
	# Stop any movement tween
	if movement_tween and movement_tween.is_running():
		movement_tween.kill()
	
	# Remove highlight from last UI element if it exists
	if current_navigation_index > 0:
		_remove_highlight_from_ui_element(current_navigation_index - 1)
	
	# Create fade out tween
	fade_out_tween = create_tween()
	
	# First, tween idle animation nodes back to zero position with elastic easing
	var reset_duration: float = 0.8  # Duration for resetting positions (slightly longer for elastic effect)
	
	# Set elastic easing for the return-to-zero animation
	fade_out_tween.set_ease(Tween.EASE_OUT)
	fade_out_tween.set_trans(Tween.TRANS_ELASTIC)
	
	if idle_x_axis_node and idle_x_axis_node.position.x != 0:
		fade_out_tween.parallel().tween_property(idle_x_axis_node, "position:x", 0.0, reset_duration)
	
	if idle_y_axis_node and idle_y_axis_node.position.y != 0:
		fade_out_tween.parallel().tween_property(idle_y_axis_node, "position:y", 0.0, reset_duration)
	
	# Then fade out by modulating alpha to 0 (this happens after the position reset)
	# Switch to cubic easing for the fade-out
	fade_out_tween.set_ease(Tween.EASE_IN_OUT)
	fade_out_tween.set_trans(Tween.TRANS_CUBIC)
	fade_out_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	
	# Queue free when fade out is complete
	fade_out_tween.finished.connect(_on_fade_out_finished)


## Called when fade out animation finishes
func _on_fade_out_finished() -> void:
	# Queue free this entire control and all its children
	queue_free()


## Collect all TutorialFairyChatBoxParent nodes from the container
func _collect_chat_box_parents() -> void:
	chat_box_parents.clear()
	
	if not chat_boxes_container:
		push_warning("Tutorial Fairy Manager: chat_boxes_container is not assigned!")
		return
	
	# Find all TutorialFairyChatBoxParent children in the container
	for child: Node in chat_boxes_container.get_children():
		if child is TutorialFairyChatBoxParent:
			chat_box_parents.append(child as TutorialFairyChatBoxParent)
	
	if chat_box_parents.is_empty():
		push_warning("Tutorial Fairy Manager: No TutorialFairyChatBoxParent nodes found in chat_boxes_container!")


## Initialize chat box parents - show first one if it exists
func _initialize_chat_box_parents() -> void:
	if chat_box_parents.is_empty():
		return
	
	# Reset waiting state
	waiting_for_chat_box_parent = false
	
	# Check if there's a chat box parent for the first navigation point (index 0)
	if chat_box_parents.size() > 0 and chat_box_parents[0]:
		# Ensure the parent is properly reset first
		chat_box_parents[0].reset()
		chat_box_parents[0].visible = true
		chat_box_parents[0].modulate.a = 1.0
		# Manually trigger showing the first chat box
		chat_box_parents[0].show_chat_box(0)
		if chat_box_parents[0].has_more_content():
			waiting_for_chat_box_parent = true


## Hide all chat box parents immediately
func _hide_all_chat_box_parents() -> void:
	for parent: TutorialFairyChatBoxParent in chat_box_parents:
		if parent:
			parent.visible = false
			parent.modulate.a = 0.0
			parent.reset()


## Handle chat box progression when fairy is clicked
func _handle_chat_box_progression() -> void:
	# Don't process if we're transitioning
	if is_transitioning:
		return
	
	# Check if we should show a chat box parent for the current navigation point
	if current_navigation_index < chat_box_parents.size():
		var current_parent: TutorialFairyChatBoxParent = chat_box_parents[current_navigation_index]
		if not current_parent:
			go_to_next_navigation()
			return
		
		# Check if the parent is visible, if not make it visible first
		if not current_parent.visible:
			current_state = FairyState.SHOWING_CHAT
			current_parent.visible = true
			current_parent.modulate.a = 1.0
			current_parent.show_chat_box(0)
			if current_parent.has_more_content():
				waiting_for_chat_box_parent = true
			return
		
		# If we're waiting for this parent to finish showing all its chat boxes
		if waiting_for_chat_box_parent:
			current_state = FairyState.SHOWING_CHAT
			# Try to show the next content in the current parent
			if current_parent.show_next_chat_box():
				# Still has more content to show
				return
			else:
				# No more content in this parent
				waiting_for_chat_box_parent = false
				current_state = FairyState.IDLE
				
				# Start fade out of current parent
				var fade_tween: Tween = create_tween()
				fade_tween.tween_property(current_parent, "modulate:a", 0.0, 0.5)
				fade_tween.tween_callback(func() -> void: current_parent.visible = false)
				
				# Simultaneously start moving to next navigation
				go_to_next_navigation()
		else:
			# Not waiting for parent, just go to next navigation
			go_to_next_navigation()
	else:
		# No chat box parent for this navigation point, just move
		go_to_next_navigation()


## Setup hover functionality for the fairy sprite
func _setup_hover_functionality() -> void:
	if not tutorial_fairy_sprite or not fairy_sprite_hover_effect:
		return
	
	# Initially hide the hover effect and set alpha to 0
	fairy_sprite_hover_effect.visible = false
	fairy_sprite_hover_effect.modulate.a = 0.0
	
	# Connect mouse entered/exited signals from the fairy sprite
	if not tutorial_fairy_sprite.mouse_entered.is_connected(_on_mouse_hover_entered):
		tutorial_fairy_sprite.mouse_entered.connect(_on_mouse_hover_entered)
	
	if not tutorial_fairy_sprite.mouse_exited.is_connected(_on_mouse_hover_exited):
		tutorial_fairy_sprite.mouse_exited.connect(_on_mouse_hover_exited)


## Called when mouse enters the fairy sprite
func _on_mouse_hover_entered() -> void:
	if not fairy_sprite_hover_effect:
		return
	
	# Kill any existing hover tween
	if hover_fade_tween and hover_fade_tween.is_running():
		hover_fade_tween.kill()
	
	# Make visible and fade in
	fairy_sprite_hover_effect.visible = true
	
	# Create fade in tween
	hover_fade_tween = create_tween()
	hover_fade_tween.set_ease(Tween.EASE_IN_OUT)
	hover_fade_tween.set_trans(Tween.TRANS_CUBIC)
	hover_fade_tween.tween_property(fairy_sprite_hover_effect, "modulate:a", 1.0, hover_fade_duration)


## Called when mouse exits the fairy sprite
func _on_mouse_hover_exited() -> void:
	if not fairy_sprite_hover_effect:
		return
	
	# Kill any existing hover tween
	if hover_fade_tween and hover_fade_tween.is_running():
		hover_fade_tween.kill()
	
	# Create fade out tween
	hover_fade_tween = create_tween()
	hover_fade_tween.set_ease(Tween.EASE_IN_OUT)
	hover_fade_tween.set_trans(Tween.TRANS_CUBIC)
	hover_fade_tween.tween_property(fairy_sprite_hover_effect, "modulate:a", 0.0, hover_fade_duration)
	# Hide completely when fade is done
	hover_fade_tween.tween_callback(func() -> void: fairy_sprite_hover_effect.visible = false)


## Flash the fairy sprite with the click color
func _flash_fairy_color() -> void:
	if not tutorial_fairy_sprite:
		return
	
	# Kill any existing color tween and reset to original color first
	if color_flash_tween and color_flash_tween.is_running():
		color_flash_tween.kill()
		# Ensure we start from the original color
		tutorial_fairy_sprite.modulate = original_fairy_color
	
	# Create new tween for color flash
	color_flash_tween = create_tween()
	color_flash_tween.set_ease(Tween.EASE_IN_OUT)
	color_flash_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Flash to the click color
	color_flash_tween.tween_property(tutorial_fairy_sprite, "modulate", fairy_click_color, 0.1)
	# Then back to original color
	color_flash_tween.tween_property(tutorial_fairy_sprite, "modulate", original_fairy_color, 0.3)


## Setup skip button functionality
func _setup_skip_button() -> void:
	if not skip_button:
		return
	
	# Connect the pressed signal if not already connected
	if not skip_button.pressed.is_connected(_on_skip_button_pressed):
		skip_button.pressed.connect(_on_skip_button_pressed)


## Handle skip button press - move fairy to final point and start fade out
func _on_skip_button_pressed() -> void:
	# Check if we're already fading out
	if current_state == FairyState.FADING_OUT:
		return

	# Stop any ongoing operations
	if movement_tween and movement_tween.is_running():
		movement_tween.kill()

	if hover_fade_tween and hover_fade_tween.is_running():
		hover_fade_tween.kill()

	if color_flash_tween and color_flash_tween.is_running():
		color_flash_tween.kill()

	# Stop idle animation
	stop_idle_animation()
	
	# Hide all chat box parents immediately
	_hide_all_chat_box_parents()
	
	# Remove all UI highlights
	for i: int in ui_highlights.size():
		_remove_highlight_from_ui_element(i)
	
	# Remove background darkening if it still exists
	if background_darken_rect:
		background_darken_rect.queue_free()
	
	# Move fairy to final navigation point if it exists
	if tutorial_fairy_sprite and fairy_navigation and fairy_navigation.get_point_count() > 0:
		# Get the last navigation point
		var final_point_index: int = fairy_navigation.get_point_count() - 1
		var final_position: Vector2 = fairy_navigation.to_global(fairy_navigation.get_point_position(final_point_index))
		# Center the fairy sprite on the point
		var target_position: Vector2 = final_position - (tutorial_fairy_sprite.size / 2.0)
		
		# Create tween to move fairy to final position quickly
		var skip_tween: Tween = create_tween()
		skip_tween.set_ease(Tween.EASE_IN_OUT)
		skip_tween.set_trans(Tween.TRANS_CUBIC)
		skip_tween.tween_property(tutorial_fairy_sprite, "global_position", target_position, 0.5)
		
		# When movement is done, start fade out
		skip_tween.finished.connect(_start_fade_out_and_cleanup)
	else:
		# If no navigation points or fairy sprite, just start fade out immediately
		_start_fade_out_and_cleanup()
