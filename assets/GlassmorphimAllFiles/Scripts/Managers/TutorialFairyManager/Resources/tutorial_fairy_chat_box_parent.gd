extends Control
class_name TutorialFairyChatBoxParent

## Current chat box index being displayed
var current_chat_box_index: int = 0

## Array of chat boxes found as children (populated at runtime)
var chat_boxes: Array[TutorialFairyChatBox] = []

## Transition duration between chat boxes
@export var transition_duration: float = 0.5

## Whether to automatically show the first chat box
@export var auto_show_first: bool = true


func _ready() -> void:
	_collect_chat_boxes()
	_initialize_chat_boxes()


## Collect all TutorialFairyChatBox nodes from children
func _collect_chat_boxes() -> void:
	chat_boxes.clear()
	
	# Find all TutorialFairyChatBox children
	for child: Node in get_children():
		if child is TutorialFairyChatBox:
			chat_boxes.append(child as TutorialFairyChatBox)
	
	if chat_boxes.is_empty():
		push_warning("TutorialFairyChatBoxParent: No TutorialFairyChatBox children found!")


## Initialize all chat boxes - hide all and optionally show first
func _initialize_chat_boxes() -> void:
	if chat_boxes.is_empty():
		return
	
	# Hide all chat boxes initially
	for chat_box: TutorialFairyChatBox in chat_boxes:
		if chat_box:
			chat_box.visible = false
			chat_box.modulate.a = 0.0
	
	# Reset index
	current_chat_box_index = 0
	
	# Show the first chat box if auto_show_first is enabled
	if auto_show_first and chat_boxes[0]:
		show_chat_box(0)


## Show a specific chat box with fade-in
func show_chat_box(index: int) -> void:
	if index >= chat_boxes.size():
		push_warning("TutorialFairyChatBoxParent: Trying to show chat box at index %d but only have %d boxes" % [index, chat_boxes.size()])
		return
	
	var chat_box: TutorialFairyChatBox = chat_boxes[index]
	if not chat_box:
		push_warning("TutorialFairyChatBoxParent: Chat box at index %d is null" % index)
		return
	
	# Make sure the chat box is visible and at full opacity first
	chat_box.visible = true
	chat_box.modulate.a = 0.0
	
	# Reset the chat box to ensure it starts fresh
	chat_box.reset_labels()
	
	# Start showing the chat box content (triggers text animation)
	chat_box.start_showing_content()
	
	# Fade in the chat box
	var tween: Tween = create_tween()
	tween.tween_property(chat_box, "modulate:a", 1.0, transition_duration)
func hide_chat_box(index: int) -> void:
	if index >= chat_boxes.size():
		return
	
	var chat_box: TutorialFairyChatBox = chat_boxes[index]
	if not chat_box:
		return
	
	var tween: Tween = create_tween()
	tween.tween_property(chat_box, "modulate:a", 0.0, transition_duration)
	tween.tween_callback(func() -> void: chat_box.visible = false)


## Show the next chat box in sequence
## Returns true if there are more chat boxes to show, false if this was the last one
func show_next_chat_box() -> bool:
	if chat_boxes.is_empty():
		return false
	
	# Check if current chat box still has labels to show
	if current_chat_box_index < chat_boxes.size():
		var current_box: TutorialFairyChatBox = chat_boxes[current_chat_box_index]
		if current_box and current_box.has_more_labels():
			current_box.show_next_label()
			return true
	
	# Check if we have more chat boxes to show
	if current_chat_box_index < chat_boxes.size() - 1:
		# Hide current chat box
		hide_chat_box(current_chat_box_index)
		
		# Move to next chat box
		current_chat_box_index += 1
		
		# Show next chat box
		show_chat_box(current_chat_box_index)
		
		return true
	
	# No more chat boxes
	return false


## Check if there are more chat boxes or labels to display
func has_more_content() -> bool:
	if current_chat_box_index < chat_boxes.size():
		var current_box: TutorialFairyChatBox = chat_boxes[current_chat_box_index]
		if current_box and current_box.has_more_labels():
			return true
	
	return current_chat_box_index < chat_boxes.size() - 1


## Reset all chat boxes to initial state
func reset() -> void:
	current_chat_box_index = 0
	_collect_chat_boxes()
	_initialize_chat_boxes()


## Get the current active chat box
func get_current_chat_box() -> TutorialFairyChatBox:
	if current_chat_box_index < chat_boxes.size():
		return chat_boxes[current_chat_box_index]
	return null
