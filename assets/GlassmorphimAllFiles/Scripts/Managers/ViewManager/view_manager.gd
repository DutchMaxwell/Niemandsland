## A navigation system that switches between different views/controls using buttons.
## Features smooth fade transitions, dynamic title updates, and automatic detection of initially visible views.
## Place this on an HBoxContainer node and configure the arrays to set up your navigation.
class_name ViewNavigation
extends Node


## Array of buttons that will trigger view changes. Each button corresponds to a control at the same index.
@export var buttons: Array[Button]
## Array of controls (views) to switch between. Only one will be visible at a time.
@export var controls: Array[Control]
## Optional Label node to display the title text for the current view.
@export var title_label: Label
## Optional RichTextLabel node to display the title text for the current view (supports BBCode formatting).
@export var title_rich_text_label: RichTextLabel
## Array of title strings corresponding to each view. The text at index[i] will be shown when control[i] is visible.
@export var title_texts: Array[String]
## Duration in seconds for the fade-out animation when hiding the current view.
@export var fade_out_duration: float = 0.3
## Duration in seconds for the fade-in animation when showing the new view.
@export var fade_in_duration: float = 0.3
## Enable HDR glow effect on the current view's button.
@export var enable_button_glow: bool = false
## HDR glow intensity multiplier for the current view's button (values above 1.0 create HDR glow).
@export var button_glow_intensity: float = 2.0

var current_index: int = -1
var tween: Tween


func _ready() -> void:
	# Connect button signals
	for i: int in buttons.size():
		if i < buttons.size() and buttons[i] != null:
			buttons[i].pressed.connect(_on_button_pressed.bind(i))
	
	# Find the first visible control and set it as active
	var initial_index: int = -1
	for i: int in controls.size():
		if controls[i] != null and controls[i].visible:
			initial_index = i
			break
	
	# If no control is visible, use the first one
	if initial_index == -1 and controls.size() > 0 and controls[0] != null:
		initial_index = 0
	
	# Show the initial control
	if initial_index >= 0:
		_show_control(initial_index)


func _on_button_pressed(index: int) -> void:
	_show_control(index)


func _show_control(index: int) -> void:
	# Don't do anything if trying to show the same control
	if index == current_index:
		return
	
	# Validate index
	if index < 0 or index >= controls.size() or controls[index] == null:
		return
	
	# Kill any existing tween
	if tween != null and tween.is_valid():
		tween.kill()
	
	# If this is the first time showing a control (no animation needed)
	if current_index == -1:
		_show_control_immediately(index)
		return
	
	# Disable all buttons during transition
	_set_buttons_enabled(false)
	
	# Create new tween
	tween = create_tween()
	
	# Fade out current control
	if current_index >= 0 and current_index < controls.size() and controls[current_index] != null:
		var current_control: Control = controls[current_index]
		tween.tween_property(current_control, "modulate:a", 0.0, fade_out_duration)
		tween.tween_callback(func() -> void: current_control.visible = false)
	
	# Re-enable buttons after fade out
	tween.tween_callback(_set_buttons_enabled.bind(true))
	
	# Hide all controls to ensure consistency (even if already hidden)
	tween.tween_callback(func() -> void:
		for i: int in controls.size():
			if controls[i] != null:
				controls[i].visible = false
	)
	
	# Prepare and fade in new control
	tween.tween_callback(func() -> void:
		controls[index].modulate.a = 0.0
		controls[index].visible = true
		_update_title_text(index)
	)
	tween.tween_property(controls[index], "modulate:a", 1.0, fade_in_duration)
	
	# Update current index after animation completes
	tween.tween_callback(func() -> void:
		current_index = index
		_update_button_glow(index)
	)


func _show_control_immediately(index: int) -> void:
	# Hide all controls
	for i: int in controls.size():
		if controls[i] != null:
			controls[i].visible = false
			controls[i].modulate.a = 1.0
	
	# Show the selected control
	controls[index].visible = true
	controls[index].modulate.a = 1.0
	
	# Update title text
	_update_title_text(index)
	
	# Apply button glow if enabled
	_update_button_glow(index)
	
	# Set current index
	current_index = index


func _update_title_text(index: int) -> void:
	if index >= 0 and index < title_texts.size():
		if title_label != null:
			title_label.text = title_texts[index]
		if title_rich_text_label != null:
			title_rich_text_label.clear()
			title_rich_text_label.append_text(title_texts[index])


func _set_buttons_enabled(enabled: bool) -> void:
	for button in buttons:
		if button != null:
			button.disabled = not enabled


func _update_button_glow(index: int) -> void:
	# Only apply glow if the feature is enabled
	if not enable_button_glow:
		return
	
	# Reset all button modulations to default
	for i: int in buttons.size():
		if buttons[i] != null:
			buttons[i].modulate = Color.WHITE
	
	# Apply HDR glow to the current view's button
	if index >= 0 and index < buttons.size() and buttons[index] != null:
		var glow_color: Color = Color.WHITE * button_glow_intensity
		buttons[index].modulate = glow_color
