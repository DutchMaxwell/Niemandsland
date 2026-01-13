extends Node

## Array of scene paths to generate buttons for. Supports both UIDs (uid://...) and regular paths (res://...).
## Each path will have a corresponding button created in the button container.
@export var scene_paths: Array[String] = []

## Optional custom names for the scene buttons. If provided, these names will be used instead of deriving names from file paths.
## The array indices correspond to the scene_paths array. Leave empty to auto-generate names.
@export var custom_button_names: Array[String] = []

## Array of PackedScenes to instantiate as child modules for each button.
## These modules will be added as children to every generated button, useful for adding visual effects or behaviors.
@export var button_modules: Array[PackedScene] = []

## The container where scene selection buttons will be generated.
## Must be assigned in the editor for the scene manager to create buttons.
@export var button_container: VBoxContainer

## Duration in seconds for the fade-in transition when entering a scene.
## Applied when loading a new scene or returning to the manager.
@export var fade_in_duration: float = 0.5

## Duration in seconds for the fade-out transition when leaving a scene.
## Applied before switching to a new scene or returning to the manager.
@export var fade_out_duration: float = 0.5

## PackedScene for the back button that appears in loaded scenes.
## Only visible on web builds or when debug_mode is enabled. Must have a "pressed" signal.
@export var back_button_scene: PackedScene

## Screen position where the back button will be placed in loaded scenes.
## Only applies if the back button is a Control node.
@export var back_button_position: Vector2 = Vector2(10, 10)

## Enable back button on all platforms for testing purposes.
## When false, back button only appears on web builds. Useful for testing navigation during development.
@export var debug_mode: bool = false

var previous_scene_path: String = ""
var current_loaded_scene: Node = null
var is_return_handler: bool = false
var manager_scene_path: String = ""
var fade_overlay: ColorRect = null

func _ready() -> void:
	# Always create fade overlay and start fade in effect
	_create_fade_overlay()
	_fade_in()
	
	# If we're acting as a return handler, just set up input handling
	if is_return_handler:
		# Ensure this node processes input even when paused
		process_mode = Node.PROCESS_MODE_ALWAYS
		# Generate back button for web builds or debug mode
		_generate_back_button()
		return
	
	# Main scene mode - set up buttons
	if not button_container:
		return
	
	_generate_scene_buttons()

func _generate_back_button() -> void:
	# Only generate back button for web builds or when debug mode is enabled
	if not (OS.get_name() == "Web" or debug_mode):
		return
	
	# Don't add back button to main scene
	if not is_return_handler:
		return
	
	if not back_button_scene:
		push_warning("Back button scene not set in SceneManager")
		return
	
	# Instance the back button
	var back_button_instance: Node = back_button_scene.instantiate()
	back_button_instance.name = "SceneManagerBackButton"
	
	# Set position if it's a Control or Node2D
	if back_button_instance is Control:
		back_button_instance.position = back_button_position
	
	# Connect the back button to return to manager
	if back_button_instance.has_signal("pressed"):
		back_button_instance.pressed.connect(_on_back_button_pressed)
	elif back_button_instance.has_method("_on_pressed"):
		# If it's a custom scene, it might handle its own pressed logic
		back_button_instance.set_meta("scene_manager", self)
	
	# Add to the root node
	add_child(back_button_instance)
	
	# Move behind Color Rect
	if back_button_instance is Control:
		move_child(back_button_instance, 0)

func _generate_scene_buttons() -> void:
	# Clear existing buttons
	for child in button_container.get_children():
		child.queue_free()
	
	# Create a button for each scene
	for i in range(scene_paths.size()):
		var scene_path: String = scene_paths[i]
		if scene_path.is_empty():
			continue
		
		var button: Button = Button.new()
		# Use custom name if available, otherwise derive from path
		if i < custom_button_names.size() and not custom_button_names[i].is_empty():
			button.text = custom_button_names[i]
		else:
			button.text = _get_scene_name_from_path(scene_path)
		button.pressed.connect(_on_scene_button_pressed.bind(scene_path))
		button_container.add_child(button)

		# Instance and add button modules as children of the button
		for module_scene in button_modules:
			var module_instance: Node = module_scene.instantiate()
			button.add_child(module_instance)

func _get_scene_name_from_path(path: String) -> String:
	# Handle both UIDs and regular paths
	if path.begins_with("uid://"):
		# For UIDs, try to load the resource to get its actual path
		var resource: Resource = load(path)
		if resource and resource.resource_path:
			var filename: String = resource.resource_path.get_file()
			return filename.trim_suffix(".tscn")
		else:
			# If can't load, use the UID as display name
			return path.substr(6, 8) + "..." # Show partial UID
	else:
		# Regular path - extract filename without extension
		var filename: String = path.get_file()
		return filename.trim_suffix(".tscn")

func _on_scene_button_pressed(scene_path: String) -> void:
	# Start fade out before loading scene
	_fade_out(scene_path)

func _load_scene(scene_path: String) -> void:
	# Store current scene path before switching
	var current_manager_path: String = get_tree().current_scene.scene_file_path
	
	# Load the new scene (works with both UIDs and regular paths)
	var new_scene: PackedScene = load(scene_path)
	if not new_scene:
		push_error("Failed to load scene: " + scene_path)
		return
	
	# Instance the new scene
	var scene_instance: Node = new_scene.instantiate()
	
	# Create a return handler using the same script
	var return_handler: Node = Node.new()
	return_handler.name = "SceneReturnHandler"
	return_handler.set_script(self.get_script())
	
	# Configure it as a return handler
	return_handler.is_return_handler = true
	return_handler.manager_scene_path = current_manager_path
	return_handler.fade_in_duration = fade_in_duration
	return_handler.fade_out_duration = fade_out_duration
	return_handler.back_button_scene = back_button_scene
	return_handler.back_button_position = back_button_position
	return_handler.debug_mode = debug_mode
	
	# Create a viewport-level fade overlay that persists during scene change
	var viewport_overlay: ColorRect = ColorRect.new()
	viewport_overlay.name = "ViewportFadeOverlay"
	viewport_overlay.color = Color(0, 0, 0, 1)  # Start opaque
	viewport_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(viewport_overlay)
	
	# Inject the return handler into the new scene
	scene_instance.add_child(return_handler)
	
	# Switch to the new scene
	get_tree().root.add_child(scene_instance)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = scene_instance
	
	# Start fade in on the new scene
	var tween: Tween = create_tween()
	tween.tween_property(viewport_overlay, "color:a", 0.0, fade_in_duration)
	tween.tween_callback(viewport_overlay.queue_free)

func _input(event: InputEvent) -> void:
	# Only handle input if we're acting as a return handler
	if is_return_handler and event.is_action_pressed("ui_cancel"):
		# Start fade out before returning
		_fade_out_to_manager()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# Handle mobile back button
	if is_return_handler and what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Start fade out before returning
		_fade_out_to_manager()

func _return_to_manager() -> void:
	if manager_scene_path.is_empty():
		push_error("No manager scene path set!")
		return
	
	var manager_scene: PackedScene = load(manager_scene_path)
	if not manager_scene:
		push_error("Failed to return to manager scene: " + manager_scene_path)
		return
	
	# Create a viewport-level fade overlay that persists during scene change
	var viewport_overlay: ColorRect = ColorRect.new()
	viewport_overlay.name = "ViewportFadeOverlay"
	viewport_overlay.color = Color(0, 0, 0, 1)  # Start opaque
	viewport_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(viewport_overlay)
	
	# Change scene
	get_tree().change_scene_to_packed(manager_scene)
	
	# Start fade in on the manager scene
	var tween: Tween = create_tween()
	tween.bind_node(viewport_overlay)
	tween.tween_property(viewport_overlay, "color:a", 0.0, fade_in_duration)
	tween.tween_callback(viewport_overlay.queue_free)

func _create_fade_overlay() -> void:
	# Create a ColorRect that covers the entire screen
	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color(0, 0, 0, 0)  # Start transparent
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Make it cover the entire viewport
	fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Add it to the current node
	add_child(fade_overlay)
	move_child(fade_overlay, -1)  # Move to end (on top)

func _fade_out(target_scene_path: String = "") -> void:
	if not fade_overlay:
		return
	
	# Create tween for fade out
	var tween: Tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, fade_out_duration)
	
	if not target_scene_path.is_empty():
		# Load scene after fade completes
		tween.tween_callback(_load_scene.bind(target_scene_path))

func _fade_out_to_manager() -> void:
	if not fade_overlay:
		return
	
	# Create tween for fade out
	var tween: Tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, fade_out_duration)
	tween.tween_callback(_return_to_manager)

func _fade_in() -> void:
	if not fade_overlay:
		return
	
	# Make sure it starts opaque
	fade_overlay.color.a = 1.0
	
	# Create tween for fade in
	var tween: Tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 0.0, fade_in_duration)

func _on_back_button_pressed() -> void:
	# Trigger the same behavior as pressing ESC or mobile back
	_fade_out_to_manager()
