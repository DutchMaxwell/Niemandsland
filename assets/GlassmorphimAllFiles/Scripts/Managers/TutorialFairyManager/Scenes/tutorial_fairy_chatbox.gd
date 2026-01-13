extends Control
class_name TutorialFairyChatBox

## Parent Control node that contains RichTextLabel nodes as children
@export var rich_text_labels_parent: Control

## Speed for animated text display (characters per second)
@export var text_animation_speed: float = 30.0

## Whether to automatically show text without animation
@export var instant_text: bool = false

## Whether to pause at punctuation marks during text animation
@export var pause_at_punctuation: bool = true

## Duration of pause at punctuation marks in seconds
@export var punctuation_pause_duration: float = 0.3

## Duration for fade-in animation in seconds
@export var fade_in_duration: float = 0.5

## Duration for fade-out animation in seconds  
@export var fade_out_duration: float = 0.5

## Flutter animation settings
@export_group("Hover Animation")
@export var flutter_distance: float = 20.0
@export var animation_duration: float = 2.0
@export var easing_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var transition_type: Tween.TransitionType = Tween.TRANS_SINE

## Array of RichTextLabel nodes found in the container (populated at runtime)
var rich_text_labels: Array[RichTextLabel] = []

## Current rich text label index being displayed
var current_label_index: int = 0

## Tweens
var hover_tween: Tween
var fade_tween: Tween
var text_animation_tween: Tween

## State tracking
var initial_position: Vector2
var is_hover_animating: bool = false
var is_transitioning: bool = false

func _ready() -> void:
	initial_position = position
	
	# Hide this chat box by default
	visible = false
	modulate.a = 0.0
	
	_collect_rich_text_labels()
	_initialize_labels()
	start_hover_animation()

## Collect all RichTextLabel nodes from the parent Control
func _collect_rich_text_labels() -> void:
	rich_text_labels.clear()
	
	if not rich_text_labels_parent:
		push_warning("TutorialFairyChatBox: rich_text_labels_parent is not assigned!")
		return
	
	# Recursively find all RichTextLabel nodes in the parent
	_find_rich_text_labels_recursive(rich_text_labels_parent)
	
	if rich_text_labels.is_empty():
		push_warning("TutorialFairyChatBox: No RichTextLabel nodes found in the rich_text_labels_parent!")


## Recursively find RichTextLabel nodes in the given node and its children
func _find_rich_text_labels_recursive(node: Node) -> void:
	# Check if the current node is a RichTextLabel
	if node is RichTextLabel:
		rich_text_labels.append(node as RichTextLabel)
	
	# Recursively check all children
	for child: Node in node.get_children():
		_find_rich_text_labels_recursive(child)


## Initialize all rich text labels - hide all and show first one
func _initialize_labels() -> void:
	if rich_text_labels.is_empty():
		return
	
	# Hide all labels initially
	for label: RichTextLabel in rich_text_labels:
		if label:
			label.visible = false
			label.modulate.a = 0.0
	
	# Reset index
	current_label_index = 0
	
	# Only show first label if the chat box itself is visible
	# This prevents auto-showing when the chat box is hidden
	if visible and rich_text_labels[0]:
		_fade_in_label(0)


## Show the next rich text label in the sequence
## Returns true if there are more labels to show, false otherwise
func show_next_label() -> bool:
	if rich_text_labels.is_empty():
		return false
	
	# Don't proceed if animation is already running
	if is_transitioning or (text_animation_tween and text_animation_tween.is_running()):
		return current_label_index < rich_text_labels.size() - 1
	
	# Check if we have more labels to show
	if current_label_index < rich_text_labels.size() - 1:
		# Transition to next label
		_transition_labels(current_label_index, current_label_index + 1)
		current_label_index += 1
		return true
	
	return false


## Check if there are more labels to display
func has_more_labels() -> bool:
	return current_label_index < rich_text_labels.size() - 1


## Reset to show the first label again
func reset_labels() -> void:
	# Stop any running animations
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
	if text_animation_tween and text_animation_tween.is_running():
		text_animation_tween.kill()
	
	# Re-collect labels in case they changed
	_collect_rich_text_labels()
	_initialize_labels()


## Start showing content when the chat box becomes visible
func start_showing_content() -> void:
	# Re-collect labels to make sure we have them
	if rich_text_labels.is_empty():
		_collect_rich_text_labels()
	
	# Make sure the parent container is visible too
	if rich_text_labels_parent:
		rich_text_labels_parent.visible = true
		# Also make sure all parent containers are visible
		var parent_node: Node = rich_text_labels_parent.get_parent()
		while parent_node and parent_node != self:
			if parent_node is Control:
				(parent_node as Control).visible = true
			parent_node = parent_node.get_parent()
	
	# Show the first label if it exists
	if not rich_text_labels.is_empty() and rich_text_labels[0]:
		current_label_index = 0
		_fade_in_label(0)
	else:
		push_warning("TutorialFairyChatBox: No labels to show!")


## Transition from one label to another with overlapping fade animations
func _transition_labels(from_index: int, to_index: int) -> void:
	if from_index >= rich_text_labels.size() or to_index >= rich_text_labels.size():
		return
	
	var from_label: RichTextLabel = rich_text_labels[from_index]
	var to_label: RichTextLabel = rich_text_labels[to_index]
	
	if not from_label or not to_label:
		return
	
	is_transitioning = true
	
	# Create tween for the transition
	fade_tween = create_tween()
	fade_tween.set_parallel(true)
	
	# Fade out the current label
	fade_tween.tween_property(from_label, "modulate:a", 0.0, fade_out_duration)
	
	# Fade in the next label at the same time
	to_label.visible = true
	to_label.modulate.a = 0.0
	fade_tween.tween_property(to_label, "modulate:a", 1.0, fade_in_duration)
	
	# Hide the previous label after fade out completes
	fade_tween.chain().tween_callback(func() -> void: 
		from_label.visible = false
		is_transitioning = false
	)
	
	# Animate text if needed
	_animate_text_if_needed(to_label)


## Fade in a specific label
func _fade_in_label(index: int) -> void:
	if index >= rich_text_labels.size():
		return
	
	var label: RichTextLabel = rich_text_labels[index]
	if not label:
		return
	
	# Make it visible and fade in
	label.visible = true
	label.modulate.a = 0.0
	
	# Create fade tween
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
	
	fade_tween = create_tween()
	fade_tween.tween_property(label, "modulate:a", 1.0, fade_in_duration)
	
	# Animate text if needed (after making visible)
	_animate_text_if_needed(label)


## Fade out the current label
func fade_out_current_label() -> void:
	if current_label_index >= rich_text_labels.size():
		return
	
	var label: RichTextLabel = rich_text_labels[current_label_index]
	if not label:
		return
	
	fade_tween = create_tween()
	fade_tween.tween_property(label, "modulate:a", 0.0, fade_out_duration)
	fade_tween.tween_callback(func() -> void: label.visible = false)


## Animate text display for a RichTextLabel
func _animate_text_if_needed(label: RichTextLabel) -> void:
	if not label or instant_text:
		return
	
	# Get the full text
	var full_text: String = label.text
	
	if full_text.length() == 0:
		return
	
	# Get clean text for proper timing
	var clean_text: String = _strip_bbcode(full_text)
	var clean_text_length: int = clean_text.length()
	
	if clean_text_length == 0:
		return
	
	# Start with no visible characters
	label.visible_characters = 0
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	
	# Create tween for text animation
	if text_animation_tween and text_animation_tween.is_running():
		text_animation_tween.kill()
	
	text_animation_tween = create_tween()
	
	# If punctuation pausing is enabled, animate with pauses
	if pause_at_punctuation:
		_animate_text_with_punctuation_pauses(label, full_text, clean_text)
	else:
		# Simple animation without pauses - use clean text length for duration
		var animation_duration_text: float = float(clean_text_length) / text_animation_speed
		# Animate to show all visible characters
		text_animation_tween.tween_property(label, "visible_characters", clean_text_length, animation_duration_text)


## Animate text with pauses at punctuation marks
func _animate_text_with_punctuation_pauses(label: RichTextLabel, _full_text: String, clean_text: String) -> void:
	var punctuation_marks: Array[String] = [".", "!", "?", ",", ";", ":", "…"]
	var clean_text_length: int = clean_text.length()
	
	# If no text after stripping, just show it instantly
	if clean_text_length == 0:
		label.visible_characters = -1  # Show all
		return
	
	# Find punctuation positions in the clean text
	var pause_positions: Array[int] = []
	for i: int in range(clean_text_length):
		var character: String = clean_text[i]
		if character in punctuation_marks:
			# Add pause after punctuation (not at the very end)
			if i < clean_text_length - 1:
				pause_positions.append(i + 1)
	
	# If no punctuation found, just do regular animation
	if pause_positions.is_empty():
		var animation_duration_text: float = float(clean_text_length) / text_animation_speed
		text_animation_tween.tween_property(label, "visible_characters", clean_text_length, animation_duration_text)
		return
	
	# Animate text in segments with pauses
	var last_position: int = 0
	
	for pause_pos: int in pause_positions:
		# Calculate duration based on clean text segment
		var segment_length: int = pause_pos - last_position
		var segment_duration: float = float(segment_length) / text_animation_speed
		
		# Animate to the punctuation mark using visible_characters
		if segment_duration > 0:
			text_animation_tween.tween_property(label, "visible_characters", pause_pos, segment_duration)
		
		# Add pause after punctuation
		text_animation_tween.tween_interval(punctuation_pause_duration)
		
		last_position = pause_pos
	
	# Animate the remaining text after the last punctuation
	if last_position < clean_text_length:
		var remaining_length: int = clean_text_length - last_position
		var remaining_duration: float = float(remaining_length) / text_animation_speed
		if remaining_duration > 0:
			text_animation_tween.tween_property(label, "visible_characters", clean_text_length, remaining_duration)


## Strip BBCode tags from text
func _strip_bbcode(text: String) -> String:
	var result: String = text
	
	# Common BBCode patterns to remove
	var patterns: Array[String] = [
		"\\[/?b\\]",  # Bold
		"\\[/?i\\]",  # Italic
		"\\[/?u\\]",  # Underline
		"\\[/?s\\]",  # Strikethrough
		"\\[/?code\\]",  # Code
		"\\[/?center\\]",  # Center
		"\\[/?right\\]",  # Right align
		"\\[/?left\\]",  # Left align
		"\\[/?fill\\]",  # Fill
		"\\[/?indent\\]",  # Indent
		"\\[/?url(=[^\\]]+)?\\]",  # URL
		"\\[/?img(=[^\\]]+)?\\]",  # Image
		"\\[/?color(=[^\\]]+)?\\]",  # Color
		"\\[/?bgcolor(=[^\\]]+)?\\]",  # Background color
		"\\[/?fgcolor(=[^\\]]+)?\\]",  # Foreground color
		"\\[/?font(=[^\\]]+)?\\]",  # Font
		"\\[/?font_size(=[^\\]]+)?\\]",  # Font size
		"\\[/?outline_size(=[^\\]]+)?\\]",  # Outline size
		"\\[/?outline_color(=[^\\]]+)?\\]",  # Outline color
		"\\[/?table(=[^\\]]+)?\\]",  # Table
		"\\[/?cell(=[^\\]]+)?\\]",  # Table cell
		"\\[/?wave(=[^\\]]+)?\\]",  # Wave effect
		"\\[/?tornado(=[^\\]]+)?\\]",  # Tornado effect
		"\\[/?shake(=[^\\]]+)?\\]",  # Shake effect
		"\\[/?fade(=[^\\]]+)?\\]",  # Fade effect
		"\\[/?rainbow(=[^\\]]+)?\\]",  # Rainbow effect
		"\\[/?pulse(=[^\\]]+)?\\]"  # Pulse effect
	]
	
	# Create a single RegEx object for better performance
	var regex: RegEx = RegEx.new()
	
	# Process each pattern
	for pattern: String in patterns:
		var compile_result: int = regex.compile(pattern)
		if compile_result == OK:
			result = regex.sub(result, "", true)  # true for global replacement
	
	return result




## Start the hover animation
func start_hover_animation() -> void:
	if is_hover_animating:
		return
	
	is_hover_animating = true
	_animate_hover()


## Animate the hover effect
func _animate_hover() -> void:
	if not is_hover_animating:
		return
	
	# Create a new tween
	if hover_tween:
		hover_tween.kill()
	
	hover_tween = create_tween()
	hover_tween.set_loops()  # Make it loop infinitely
	
	# Animate up
	hover_tween.tween_property(
		self,
		"position",
		initial_position + Vector2(0, -flutter_distance),
		animation_duration / 2
	).set_ease(easing_type).set_trans(transition_type)
	
	# Animate down
	hover_tween.tween_property(
		self,
		"position",
		initial_position + Vector2(0, flutter_distance),
		animation_duration / 2
	).set_ease(easing_type).set_trans(transition_type)


## Stop the hover animation
func stop_hover_animation() -> void:
	is_hover_animating = false
	if hover_tween:
		hover_tween.kill()
		hover_tween = null
	
	# Reset to initial position
	position = initial_position

## Set a new flutter distance
func set_flutter_distance(new_distance: float) -> void:
	flutter_distance = new_distance
	if is_hover_animating:
		_animate_hover()  # Restart animation with new distance


## Clean up when node is removed
func _exit_tree() -> void:
	if hover_tween:
		hover_tween.kill()
	if fade_tween:
		fade_tween.kill()
	if text_animation_tween:
		text_animation_tween.kill()
