extends Control

## Simple SVG Editor that can both edit SVG properties and display raw XML content

class_name SimpleSVGEditor

# UI References
@export var svg_input_field: LineEdit
@export var svg_preview_label: RichTextLabel
@export var convert_color_button: Button
@export var target_color_picker: ColorPickerButton
@export var save_replace_button: Button
@export var save_dupe_button: Button
@export var canvas_width_spinbox: SpinBox
@export var canvas_height_spinbox: SpinBox
@export var change_canvas_size_button: Button
@export var change_opacity_button: Button
@export var change_opacity_label: Label
@export var change_opacity_hslider: HSlider
@export var file_count_label: Label  # Label to show how many SVG files are being edited
@export var file_dialog_button: Button  # Button to open file dialog
@export var file_dialog: FileDialog  # File dialog for selecting SVG files
@export var opacity_presets: OptionButton  # OptionButton for opacity presets

# SVG content storage
var svg_contents: PackedStringArray = []  # Store content of all loaded SVGs
var show_formatted: bool = false
var current_svg_paths: PackedStringArray = []  # Store paths of the currently loaded SVGs
var has_changes: bool = false  # Track changes to the SVG content

func _ready() -> void:
	# Connect to the input field for both file paths and direct SVG content
	if svg_input_field:
		svg_input_field.text_changed.connect(_on_svg_input_changed)
	
	# Connect to convert color button
	if convert_color_button:
		convert_color_button.pressed.connect(_on_convert_color_pressed)
	
	# Connect to save buttons
	if save_replace_button:
		save_replace_button.pressed.connect(_on_save_replace_pressed)
	
	if save_dupe_button:
		save_dupe_button.pressed.connect(_on_save_dupe_pressed)
	
	# Connect to change canvas size button
	if change_canvas_size_button:
		change_canvas_size_button.pressed.connect(_on_change_canvas_size_pressed)
	
	# Connect to change opacity button
	if change_opacity_button:
		change_opacity_button.pressed.connect(_on_change_opacity_pressed)
	
	# Connect to opacity slider
	if change_opacity_hslider:
		change_opacity_hslider.value_changed.connect(_on_opacity_slider_changed)
	
	# Populate Opacity Presets OptionButton
	if opacity_presets:
		var opacity_values: Array[int] = [100, 95, 90, 85, 80, 70, 60, 50, 40, 30, 25, 20, 10, 5, 0]
		for value: int in opacity_values:
			opacity_presets.add_item(str(value) + "%", value)
		# Connect the selection signal
		opacity_presets.item_selected.connect(_on_opacity_preset_selected)
	
	# Connect to Window's file drop signal
	var window: Window = get_window()
	if window:
		window.files_dropped.connect(_on_files_dropped)

	# Connect to file dialog button
	if file_dialog_button:
		file_dialog_button.pressed.connect(_on_file_dialog_button_pressed)
	
	# Connect to file dialog
	if file_dialog:
		# Set up file dialog for SVG files
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES  # Allow multiple file selection
		file_dialog.add_filter("*.svg", "SVG Files")
		file_dialog.files_selected.connect(_on_file_dialog_files_selected)

# Handle SVG input - either file paths or direct content
func _on_svg_input_changed(new_text: String) -> void:
	if new_text.is_empty():
		return
	
	# Strip quotation marks if present
	new_text = new_text.strip_edges()
	if new_text.begins_with('"') and new_text.ends_with('"'):
		new_text = new_text.substr(1, new_text.length() - 2)
	elif new_text.begins_with("'") and new_text.ends_with("'"):
		new_text = new_text.substr(1, new_text.length() - 2)
	
	# Check if it's SVG content
	if new_text.begins_with("<svg") or new_text.contains("<path"):
		# Direct SVG content
		svg_contents.clear()
		svg_contents.append(new_text)
		current_svg_paths.clear()  # Clear paths since this is direct content
		update_file_count_display()  # Update count to show "No files"
		_display_svg_content()
	else:
		# Try to parse as file paths (comma separated)
		var paths: PackedStringArray = new_text.split(",")
		var valid_paths: PackedStringArray = []
		
		for path in paths:
			path = path.strip_edges()
			if path.ends_with(".svg") and FileAccess.file_exists(path):
				valid_paths.append(path)
		
		if valid_paths.size() > 0:
			load_svg_files(valid_paths)

# Load multiple SVG files
func load_svg_files(paths: PackedStringArray) -> void:
	current_svg_paths = paths
	svg_contents.clear()
	
	# Load all files into memory
	for path in paths:
		var content: String = get_svg_content(path)
		if not content.is_empty():
			svg_contents.append(content)
		else:
			# Add empty string to maintain index alignment with paths
			svg_contents.append("")
	
	# Set up controls based on first file
	if svg_contents.size() > 0 and not svg_contents[0].is_empty():
		_update_canvas_size_from_svg(svg_contents[0])
		_check_and_update_opacity_button()
		_check_and_update_size_button()
	
	# Display all files
	_display_all_svg_files()
	
	# Update the display to show file count
	update_file_count_display()
	
	# Update input field to show all paths
	if svg_input_field:
		svg_input_field.text = ", ".join(paths)
	
	has_changes = false  # Reset changes when loading new files

func update_file_count_display() -> void:
	var count: int = current_svg_paths.size()
	
	# Update the file count label if available
	if file_count_label:
		if count > 1:
			file_count_label.text = str(count) + " files"
		elif count == 1:
			file_count_label.text = "1 file"
		else:
			file_count_label.text = "No files"

func load_svg_file(path: String) -> void:
	# Check if file exists
	if not FileAccess.file_exists(path):
		push_error("File does not exist: " + path)
		_show_error("Error: File does not exist at path: " + path)
		return
	
	# Check if it's an SVG file
	if not path.to_lower().ends_with(".svg"):
		push_error("File is not an SVG: " + path)
		_show_error("Error: File is not an SVG file: " + path)
		return
	
	# Read the file
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open file: " + path)
		_show_error("Error: Could not open file: " + path)
		return
	
	var content: String = file.get_as_text()
	file.close()
	
	# This function is now primarily for single file loading
	# Store as array with single element
	svg_contents.clear()
	svg_contents.append(content)
	current_svg_paths.clear()
	current_svg_paths.append(path)
	has_changes = false  # Reset changes when loading new content
	
	# Display in the preview area
	_display_all_svg_files()
	
	# Parse and update canvas size
	_update_canvas_size_from_svg(content)
	
	# Check if SVG has opacity attribute and update button accordingly
	_check_and_update_opacity_button()
	_check_and_update_size_button()
	
	print("SVG content loaded from: ", path)
	print("Content length: ", content.length(), " characters")

func _display_svg_content() -> void:
	if svg_preview_label and svg_contents.size() > 0:
		if show_formatted:
			var formatted: String = format_svg(svg_contents[0])
			svg_preview_label.text = "[b]SVG Content[/b]:\n\n" + formatted
		else:
			# Show raw content
			svg_preview_label.text = "[b]SVG Content[/b]:\n\n" + svg_contents[0]

# Display all SVG files when multiple are loaded
func _display_all_svg_files() -> void:
	if svg_preview_label:
		var combined_content: String = "[b]SVG content[/b]\n\n"
		
		# Handle direct SVG content (no paths)
		if current_svg_paths.is_empty() and svg_contents.size() > 0:
			combined_content += _colorize_svg_attributes(svg_contents[0]) + "\n\n"
		else:
			# Handle file-based content
			for i in range(current_svg_paths.size()):
				if i < svg_contents.size() and not svg_contents[i].is_empty():
					# Add yellow color to file path
					combined_content += "[color=yellow]" + current_svg_paths[i] + "[/color]\n"
					# Colorize the attribute names in the content
					combined_content += _colorize_svg_attributes(svg_contents[i]) + "\n\n"
		
		svg_preview_label.text = combined_content.strip_edges()

func _show_error(error_msg: String) -> void:
	if svg_preview_label:
		svg_preview_label.text = "[color=red]" + error_msg + "[/color]"


func toggle_format() -> void:
	show_formatted = !show_formatted
	if svg_contents.size() > 0:
		_display_svg_content()

## Utility function to get SVG content as string
func get_svg_content(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("File does not exist: " + path)
		return ""
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open file: " + path)
		return ""
	
	var content: String = file.get_as_text()
	file.close()
	
	return content

## Pretty print SVG with indentation
func format_svg(svg_str: String) -> String:
	# Basic formatting - add newlines and indentation
	var formatted: String = svg_str
	
	# Replace > with >\n for readability
	formatted = formatted.replace("><", ">\n<")
	
	# Add indentation
	var lines: PackedStringArray = formatted.split("\n")
	var result: String = ""
	var indent_level: int = 0
	
	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			continue
		
		# Decrease indent for closing tags
		if line.begins_with("</"):
			indent_level = max(0, indent_level - 1)
		
		# Add indentation
		result += "\t".repeat(indent_level) + line + "\n"
		
		# Increase indent for opening tags (not self-closing)
		if line.begins_with("<") and not line.begins_with("</") and not line.ends_with("/>"):
			indent_level += 1
	
	return result.strip_edges()

# Override the built-in _input to handle keyboard shortcuts
func _input(_event: InputEvent) -> void:
	pass
	## Ctrl+F to toggle format
	#if event.ctrl_pressed and event.keycode == KEY_F:
		#toggle_format()
		#get_viewport().set_input_as_handled()
	## Ctrl+S to save/replace
	#elif event.ctrl_pressed and event.keycode == KEY_S:
		#_on_save_replace_pressed()
		#get_viewport().set_input_as_handled()
	## Ctrl+Shift+S to save as dupe
	#elif event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_S:
		#_on_save_dupe_pressed()
		#get_viewport().set_input_as_handled()

# Handle color conversion button press
func _on_convert_color_pressed() -> void:
	if svg_contents.is_empty():
		var dialog: AcceptDialog = AcceptDialog.new()
		dialog.dialog_text = "No SVG content to convert colors!"
		dialog.title = "Warning"
		get_viewport().add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(func() -> void: dialog.queue_free())
		dialog.canceled.connect(func() -> void: dialog.queue_free())
		return
	
	if not target_color_picker:
		push_error("No color picker assigned for target color!")
		return
	
	var target_color: Color = target_color_picker.color
	var hex_color: String = "#" + target_color.to_html(false)
	
	print("Converting SVG colors to: ", hex_color)
	
	# If we have multiple files loaded, convert all of them
	if current_svg_paths.size() > 1:
		var confirmation_dialog: ConfirmationDialog = ConfirmationDialog.new()
		confirmation_dialog.dialog_text = "Convert colors in all " + str(current_svg_paths.size()) + " loaded SVG files?"
		confirmation_dialog.title = "Convert All Files"
		get_viewport().add_child(confirmation_dialog)
		confirmation_dialog.popup_centered()
		
		confirmation_dialog.confirmed.connect(func() -> void:
			# Convert all files in memory only
			var converted_count: int = 0
			
			for i in range(svg_contents.size()):
				if i < svg_contents.size() and not svg_contents[i].is_empty():
					var converted: String = convert_svg_colors(svg_contents[i], hex_color)
					# Update the content in memory
					svg_contents[i] = converted
					converted_count += 1
			
			# Display the updated content without reloading from disk
			_display_all_svg_files()
			
			has_changes = true
			_show_success("Converted colors in " + str(converted_count) + " SVG files (not saved yet)!")
			confirmation_dialog.queue_free()
		)
	
		confirmation_dialog.canceled.connect(func() -> void:
			confirmation_dialog.queue_free()
		)
	else:
		# Single file or direct content
		if svg_contents.size() > 0 and not svg_contents[0].is_empty():
			var converted_svg: String = convert_svg_colors(svg_contents[0], hex_color)
			
			# Update the stored content
			svg_contents[0] = converted_svg
			has_changes = true
			
			# Don't save automatically - just update in memory
			
			# Display the updated content
			_display_all_svg_files()
			
			print("SVG colors converted (not saved yet)!")

# Convert all color attributes in SVG to the target color
func convert_svg_colors(svg_str: String, target_hex: String) -> String:
	var result: String = svg_str
	
	# Replace fill colors
	var regex: RegEx = RegEx.new()
	regex.compile('fill="[^"]+"')
	result = regex.sub(result, 'fill="' + target_hex + '"', true)
	
	# Replace stroke colors
	regex.compile('stroke="[^"]+"')
	result = regex.sub(result, 'stroke="' + target_hex + '"', true)
	
	# Replace style attribute colors
	regex.compile('fill:\\s*[^;]+;')
	result = regex.sub(result, 'fill: ' + target_hex + ';', true)
	
	regex.compile('stroke:\\s*[^;]+;')
	result = regex.sub(result, 'stroke: ' + target_hex + ';', true)
	
	return result


# Save SVG content to file
func save_svg_file(svg_content_to_save: String, file_path: String, show_dialog: bool = true) -> bool:
	if svg_content_to_save.is_empty():
		push_warning("No SVG content to save!")
		if show_dialog:
			_show_error("Error: No SVG content to save!")
		return false
	
	# Ensure the file has .svg extension
	if not file_path.ends_with(".svg"):
		file_path += ".svg"
	
	# Handle different path types
	var absolute_path: String = file_path
	
	# If it's a res:// path, convert to absolute
	if file_path.begins_with("res://"):
		absolute_path = ProjectSettings.globalize_path(file_path)
	elif file_path.begins_with("user://"):
		# For user:// paths, use Godot's file system
		var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_string(svg_content_to_save)
			file.close()
			if show_dialog:
				_show_success("SVG file saved to: " + file_path)
			print("SVG file saved to user directory: ", OS.get_user_data_dir() + "/" + file_path.replace("user://", ""))
			return true
		else:
			if show_dialog:
				_show_error("Error: Failed to create SVG file at: " + file_path)
			return false
	
	# For res:// and absolute paths, write directly
	var abs_file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if abs_file:
		abs_file.store_string(svg_content_to_save)
		abs_file.close()
		if show_dialog:
			_show_success("SVG file saved to: " + absolute_path)
		print("SVG file created at: ", absolute_path)
		return true
	else:
		if show_dialog:
			_show_error("Error: Failed to create SVG file at: " + absolute_path)
		return false

# Handle save/replace button press
func _on_save_replace_pressed() -> void:
	if not has_changes:
		var dialog: AcceptDialog = AcceptDialog.new()
		dialog.dialog_text = "No changes made to save!"
		dialog.title = "Warning"
		get_viewport().add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(func() -> void: dialog.queue_free())
		return
	
	if current_svg_paths.is_empty():
		var dialog: AcceptDialog = AcceptDialog.new()
		if svg_contents.is_empty():
			dialog.dialog_text = "No SVG content to save!"
		else:
			dialog.dialog_text = "No original file to replace! This SVG was created from direct content."
		dialog.title = "Warning"
		get_viewport().add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(func() -> void: dialog.queue_free())
		return
	
	# If we have multiple files loaded, ask whether to save all
	if current_svg_paths.size() > 1:
		var confirmation_dialog: ConfirmationDialog = ConfirmationDialog.new()
		confirmation_dialog.dialog_text = "Save and replace all " + str(current_svg_paths.size()) + " loaded SVG files?"
		confirmation_dialog.title = "Save All Files"
		get_viewport().add_child(confirmation_dialog)
		confirmation_dialog.popup_centered()
		
		confirmation_dialog.confirmed.connect(func() -> void:
			# Save all files
			var saved_count: int = 0
			for i in range(current_svg_paths.size()):
				if i < svg_contents.size() and not svg_contents[i].is_empty():
					if save_svg_file(svg_contents[i], current_svg_paths[i], false):
						saved_count += 1
			
			has_changes = false  # Reset changes after saving
			_show_success("Saved " + str(saved_count) + " SVG files!")
			confirmation_dialog.queue_free()
		)
		
		confirmation_dialog.canceled.connect(func() -> void:
			confirmation_dialog.queue_free()
		)
	
	else:
		# Single file
		if svg_contents.size() > 0 and not svg_contents[0].is_empty():
			save_svg_file(svg_contents[0], current_svg_paths[0])
			has_changes = false  # Reset changes after saving

# Handle save as dupe button press
func _on_save_dupe_pressed() -> void:
	if current_svg_paths.is_empty():
		if svg_contents.is_empty():
			var dialog: AcceptDialog = AcceptDialog.new()
			dialog.dialog_text = "No SVG content to save!"
			dialog.title = "Warning"
			get_viewport().add_child(dialog)
			dialog.popup_centered()
			dialog.confirmed.connect(func() -> void: dialog.queue_free())
			return
		else:
			var dialog: AcceptDialog = AcceptDialog.new()
			dialog.dialog_text = "No original file to duplicate! This SVG was created from direct content."
			dialog.title = "Warning"
			get_viewport().add_child(dialog)
			dialog.popup_centered()
			dialog.confirmed.connect(func() -> void: dialog.queue_free())
			return
	
	# If we have multiple files loaded, ask whether to duplicate all
	if current_svg_paths.size() > 1:
		var confirmation_dialog: ConfirmationDialog = ConfirmationDialog.new()
		confirmation_dialog.dialog_text = "Create duplicates of all " + str(current_svg_paths.size()) + " loaded SVG files?"
		confirmation_dialog.title = "Duplicate All Files"
		get_viewport().add_child(confirmation_dialog)
		confirmation_dialog.popup_centered()
		
		confirmation_dialog.confirmed.connect(func() -> void:
			# Duplicate all files
			var duped_count: int = 0
			var new_paths: PackedStringArray = []
			for i in range(current_svg_paths.size()):
				if i < svg_contents.size() and not svg_contents[i].is_empty():
					var dupe_path: String = _create_dupe_filename(current_svg_paths[i])
					if save_svg_file(svg_contents[i], dupe_path, false):
						duped_count += 1
						new_paths.append(dupe_path)
			
			# Show success message about created duplicates
			var success_dialog: AcceptDialog = AcceptDialog.new()
			success_dialog.dialog_text = "Created " + str(duped_count) + " duplicate SVG files!"
			success_dialog.title = "Success"
			get_viewport().add_child(success_dialog)
			success_dialog.popup_centered()
			
			success_dialog.confirmed.connect(func() -> void:
				success_dialog.queue_free()
				
				# After success confirmation, optionally load the duplicated files
				if new_paths.size() > 0:
					var load_dialog: ConfirmationDialog = ConfirmationDialog.new()
					load_dialog.dialog_text = "Do you want to load the duplicates for editing?"
					load_dialog.title = "Load Duplicates?"
					get_viewport().add_child(load_dialog)
					load_dialog.popup_centered()
					
					load_dialog.confirmed.connect(func() -> void:
						load_svg_files(new_paths)
						load_dialog.queue_free()
						# Show warning that user is now editing duplicates
						_show_duplicate_warning()
					)
					
					load_dialog.canceled.connect(func() -> void:
						load_dialog.queue_free()
					)
			)
			
			confirmation_dialog.queue_free()
		)
		
		confirmation_dialog.canceled.connect(func() -> void:
			confirmation_dialog.queue_free()
		)
	else:
		# Single file
		if svg_contents.size() > 0 and not svg_contents[0].is_empty():
			var dupe_path: String = _create_dupe_filename(current_svg_paths[0])
			# Save without showing dialog since we'll show our own
			if save_svg_file(svg_contents[0], dupe_path, false):
				# Show success dialog
				var success_dialog: AcceptDialog = AcceptDialog.new()
				success_dialog.dialog_text = "SVG file saved to: " + dupe_path
				success_dialog.title = "Success"
				get_viewport().add_child(success_dialog)
				success_dialog.popup_centered()
				
				success_dialog.confirmed.connect(func() -> void:
					success_dialog.queue_free()
					
					# After success confirmation, optionally load the duplicated file
					var load_dialog: ConfirmationDialog = ConfirmationDialog.new()
					load_dialog.dialog_text = "Do you want to load the duplicate for editing?"
					load_dialog.title = "Load Duplicate?"
					get_viewport().add_child(load_dialog)
					load_dialog.popup_centered()
					
					load_dialog.confirmed.connect(func() -> void:
						load_svg_file(dupe_path)
						load_dialog.queue_free()
						# Show warning that user is now editing duplicate
						_show_duplicate_warning()
					)
					
					load_dialog.canceled.connect(func() -> void:
						load_dialog.queue_free()
					)
				)
			else:
				_show_error("Failed to save duplicate file!")

# Create a duplicate filename by adding "_dupe" before the extension
func _create_dupe_filename(original_path: String) -> String:
	var base_name: String = original_path.get_file().get_basename()
	var extension: String = original_path.get_extension()
	var directory: String = original_path.get_base_dir()
	
	# Create the new filename with "_dupe" suffix
	var dupe_filename: String = base_name + "_dupe." + extension
	var dupe_path: String = directory + "/" + dupe_filename
	
	# If file already exists, add a number
	var counter: int = 2
	while FileAccess.file_exists(dupe_path):
		dupe_filename = base_name + "_dupe" + str(counter) + "." + extension
		dupe_path = directory + "/" + dupe_filename
		counter += 1
	
	return dupe_path

# Show success message
func _show_success(success_msg: String) -> void:
	# Defer the dialog creation to avoid conflicts with other dialogs
	call_deferred("_create_success_dialog", success_msg)

func _create_success_dialog(success_msg: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.dialog_text = success_msg
	dialog.title = "Success"
	get_viewport().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	# Also free on close
	dialog.close_requested.connect(func() -> void: dialog.queue_free())

# Show warning when editing duplicate files
func _show_duplicate_warning() -> void:
	var warning_dialog: AcceptDialog = AcceptDialog.new()
	warning_dialog.dialog_text = "⚠️ IMPORTANT: You are now editing the DUPLICATE files!\n\nThe original files remain unchanged. Any further edits will be made to the duplicate files.\n\nIf you save changes, they will overwrite the duplicates, not the originals."
	warning_dialog.title = "Now Editing Duplicates"
	get_viewport().add_child(warning_dialog)
	warning_dialog.popup_centered(Vector2(450, 200))
	warning_dialog.confirmed.connect(func() -> void: warning_dialog.queue_free())
	warning_dialog.close_requested.connect(func() -> void: warning_dialog.queue_free())

# Handle dropped files from Window signal
func _on_files_dropped(files: PackedStringArray) -> void:
	var svg_paths: PackedStringArray = []
	for file_path in files:
		# Check if it's an SVG file
		if file_path.to_lower().ends_with(".svg"):
			svg_paths.append(file_path)
	
	if svg_paths.size() > 0:
		if current_svg_paths.size() > 0:
			# We already have files loaded, ask what to do
			var dialog: ConfirmationDialog = ConfirmationDialog.new()
			dialog.dialog_text = "You have " + str(current_svg_paths.size()) + " file(s) already loaded.\nDo you want to add the new file(s) or start fresh?"
			dialog.add_button("Add to existing", false, "add")
			dialog.add_button("Start fresh", false, "fresh")
			get_viewport().add_child(dialog)
			dialog.popup_centered()
			
			# Store svg_paths in a way we can access them
			dialog.set_meta("svg_paths", svg_paths)
			
			dialog.confirmed.connect(func() -> void:
				# Default confirm button - add to existing
				var new_paths: PackedStringArray = dialog.get_meta("svg_paths") as PackedStringArray
				for path: String in new_paths:
					if not path in current_svg_paths:
						current_svg_paths.append(path)
				load_svg_files(current_svg_paths)
				dialog.queue_free()
			)
			
			dialog.custom_action.connect(func(action: String) -> void:
				var new_paths: PackedStringArray = dialog.get_meta("svg_paths") as PackedStringArray
				if action == "add":
					# Add to existing
					for path: String in new_paths:
						if not path in current_svg_paths:
							current_svg_paths.append(path)
					load_svg_files(current_svg_paths)
				elif action == "fresh":
					# Start fresh
					load_svg_files(new_paths)
				dialog.queue_free()
			)
			
			dialog.canceled.connect(func() -> void:
				dialog.queue_free()
			)
		else:
			# No files loaded, just load the new ones
			load_svg_files(svg_paths)

# Handle change canvas size button press
func _on_change_canvas_size_pressed() -> void:
	if svg_contents.is_empty():
		var dialog: AcceptDialog = AcceptDialog.new()
		dialog.dialog_text = "No SVG content to update!"
		dialog.title = "Warning"
		get_viewport().add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(func() -> void: dialog.queue_free())
		return

	if not canvas_width_spinbox or not canvas_height_spinbox:
		push_error("Canvas size spin boxes not assigned!")
		return

	var new_width: float = canvas_width_spinbox.value
	var new_height: float = canvas_height_spinbox.value

	# If we have multiple files loaded, handle them as a batch
	if current_svg_paths.size() > 1:
		var is_adding: bool = (change_canvas_size_button.text == "Add Size Attributes")
		
		var dialog_text: String
		if is_adding:
			dialog_text = "Some files are missing size attributes. Add width/height to all SVGs that need them?\nNew size: " + str(new_width) + "x" + str(new_height)
		else: # is updating
			dialog_text = "Update canvas size in all " + str(current_svg_paths.size()) + " loaded SVG files?\nNew size: " + str(new_width) + "x" + str(new_height)
		
		var confirmation_dialog: ConfirmationDialog = ConfirmationDialog.new()
		confirmation_dialog.dialog_text = dialog_text
		confirmation_dialog.title = "Update All Files"
		get_viewport().add_child(confirmation_dialog)
		confirmation_dialog.popup_centered()

		confirmation_dialog.confirmed.connect(func() -> void:
			var modified_count: int = 0
			for i in range(svg_contents.size()):
				var content: String = svg_contents[i]
				if content.is_empty(): continue
				
				var was_modified: bool = false

				# If in "add" mode, only touch files that are missing attributes
				if is_adding:
					var has_width: bool = content.contains("width=")
					var has_height: bool = content.contains("height=")
					
					if not has_width or not has_height:
						if not has_width:
							content = _add_width_attribute(content, new_width)
						if not has_height:
							content = _add_height_attribute(content, new_height)
						# Now that attributes are added, update them to the correct value
						content = _update_svg_canvas_size(content, new_width, new_height)
						was_modified = true
				else: # is updating, so update all files
					content = _update_svg_canvas_size(content, new_width, new_height)
					was_modified = true

				if was_modified:
					svg_contents[i] = content
					modified_count += 1
			
			if modified_count > 0:
				has_changes = true
				_display_all_svg_files()
				_show_success("Updated " + str(modified_count) + " SVG files (not saved yet)!")
			
			# Reset button text after operation
			change_canvas_size_button.text = "Change Canvas Size"
			confirmation_dialog.queue_free()
		)
		confirmation_dialog.canceled.connect(func() -> void: confirmation_dialog.queue_free())

	else:
		# Single file or direct content
		if svg_contents.size() > 0 and not svg_contents[0].is_empty():
			var width_value: float = canvas_width_spinbox.value
			var height_value: float = canvas_height_spinbox.value
			var message: String

			var updated_svg: String = svg_contents[0]
			var has_width: bool = updated_svg.contains("width=")
			var has_height: bool = updated_svg.contains("height=")

			if not has_width:
				updated_svg = _add_width_attribute(updated_svg, width_value)
				message = "Added width attribute."
			if not has_height:
				updated_svg = _add_height_attribute(updated_svg, height_value)
				if not message.is_empty():
					message += " Added height attribute."
				else:
					message = "Added height attribute."

			# Always run update to ensure values are set correctly, even after adding
			updated_svg = _update_svg_canvas_size(updated_svg, width_value, height_value)

			if has_width and has_height:
				message = "Canvas size updated."
			
			# Update the stored content
			svg_contents[0] = updated_svg
			has_changes = true
			
			# Display the updated content
			_display_all_svg_files()
			
			_show_success(message + " (Not saved yet!)")
			# Reset button text after operation
			change_canvas_size_button.text = "Change Canvas Size"

# Update SVG canvas size using regex
func _update_svg_canvas_size(svg_str: String, new_width: float, new_height: float) -> String:
	var result: String = svg_str
	
	# Format width and height without unnecessary decimals
	var width_str: String = _format_number(new_width)
	var height_str: String = _format_number(new_height)

	# Replace width attribute
	var width_regex: RegEx = RegEx.new()
	width_regex.compile('width="[^"]+"')
	result = width_regex.sub(result, 'width="' + width_str + '"', true)
	
	# Replace height attribute
	var height_regex: RegEx = RegEx.new()
	height_regex.compile('height="[^"]+"')
	result = height_regex.sub(result, 'height="' + height_str + '"', true)
	
	# Note: We intentionally do NOT update the viewBox attribute
	# The viewBox defines the coordinate system and should remain unchanged
	# Only the width and height (display size) are updated
	
	return result

# Add width attribute to SVG root if it doesn't exist
func _add_width_attribute(svg_str: String, width_value: float) -> String:
	var result: String = svg_str
	
	# Find the <svg tag
	var svg_tag_regex: RegEx = RegEx.new()
	svg_tag_regex.compile("<svg[^>]*>")
	var match: RegExMatch = svg_tag_regex.search(result)
	
	if match:
		var svg_tag: String = match.get_string(0)
		# Check if width attribute already exists
		if not "width=" in svg_tag:
			var new_svg_tag: String = svg_tag.left(svg_tag.length() - 1) + ' width="' + str(width_value) + '"' + ">"
			result = result.replace(svg_tag, new_svg_tag)
			
	return result

# Add height attribute to SVG root if it doesn't exist
func _add_height_attribute(svg_str: String, height_value: float) -> String:
	var result: String = svg_str
	
	# Find the <svg tag
	var svg_tag_regex: RegEx = RegEx.new()
	svg_tag_regex.compile("<svg[^>]*>")
	var match: RegExMatch = svg_tag_regex.search(result)
	
	if match:
		var svg_tag: String = match.get_string(0)
		# Check if height attribute already exists
		if not "height=" in svg_tag:
			var new_svg_tag: String = svg_tag.left(svg_tag.length() - 1) + ' height="' + str(height_value) + '"' + ">"
			result = result.replace(svg_tag, new_svg_tag)
			
	return result

# Check if SVG has width and height attributes and update button accordingly
func _check_and_update_size_button() -> void:
	if not change_canvas_size_button:
		return

	var needs_size_attributes: bool = false
	# Check all loaded SVGs
	for content in svg_contents:
		if content.is_empty():
			continue
		var has_width: bool = content.contains("width=")
		var has_height: bool = content.contains("height=")
		if not has_width or not has_height:
			needs_size_attributes = true
			break # Found one, no need to check the rest

	if needs_size_attributes:
		change_canvas_size_button.text = "Add Size Attributes"
	else:
		change_canvas_size_button.text = "Change Canvas Size"

# Parse SVG content and update canvas size spin boxes
func _update_canvas_size_from_svg(svg_content_to_parse: String) -> void:
	# Parse width from SVG
	var width_regex: RegEx = RegEx.new()
	width_regex.compile('width="([0-9.]+)"')
	var width_match: RegExMatch = width_regex.search(svg_content_to_parse)
	
	# Parse height from SVG
	var height_regex: RegEx = RegEx.new()
	height_regex.compile('height="([0-9.]+)"')
	var height_match: RegExMatch = height_regex.search(svg_content_to_parse)
	
	# Update spin boxes if matches found
	if width_match and canvas_width_spinbox:
		var width_str: String = width_match.get_string(1)
		var width_value: float = width_str.to_float()
		if width_value > 0:
			canvas_width_spinbox.value = width_value
			print("SVG width detected: ", width_value)
	
	if height_match and canvas_height_spinbox:
		var height_str: String = height_match.get_string(1)
		var height_value: float = height_str.to_float()
		if height_value > 0:
			canvas_height_spinbox.value = height_value
			print("SVG height detected: ", height_value)
	
	# Also check for viewBox if width/height not found
	if not width_match or not height_match:
		var viewbox_regex: RegEx = RegEx.new()
		viewbox_regex.compile(r'viewBox="([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)"')
		var viewbox_match: RegExMatch = viewbox_regex.search(svg_content_to_parse)
		
		if viewbox_match:
			# viewBox format: "x y width height"
			var viewbox_width: float = viewbox_match.get_string(3).to_float()
			var viewbox_height: float = viewbox_match.get_string(4).to_float()
			
			if not width_match and canvas_width_spinbox and viewbox_width > 0:
				canvas_width_spinbox.value = viewbox_width
				print("SVG width from viewBox: ", viewbox_width)
			
			if not height_match and canvas_height_spinbox and viewbox_height > 0:
				canvas_height_spinbox.value = viewbox_height
				print("SVG height from viewBox: ", viewbox_height)

# Format number to remove unnecessary decimal points
func _format_number(value: float) -> String:
	# Check if the value is a whole number
	if value == floor(value):
		return str(int(value))
	else:
		return str(value)

# Handle opacity slider change
func _on_opacity_slider_changed(value: float) -> void:
	if change_opacity_label:
		change_opacity_label.text = "%.2f" % value

# Check if SVG has opacity attribute and update button accordingly
func _check_and_update_opacity_button() -> void:
	if not change_opacity_button:
		return

	var needs_opacity_attribute: bool = false
	# On first load, update slider from first file that has opacity
	if not svg_contents.is_empty():
		for content in svg_contents:
			if content.contains("opacity="):
				_update_opacity_from_svg(content)
				break

	# Check all loaded SVGs for missing opacity
	for content in svg_contents:
		if content.is_empty():
			continue
		if not content.contains("opacity="):
			needs_opacity_attribute = true
			break # Found one, no need to check the rest

	if needs_opacity_attribute:
		change_opacity_button.text = "Add Opacity Attribute?"
	else:
		change_opacity_button.text = "Change Opacity"

# Parse SVG content and update opacity slider and label
func _update_opacity_from_svg(svg_content_to_parse: String) -> void:
	# Parse opacity from SVG
	var opacity_regex: RegEx = RegEx.new()
	opacity_regex.compile('opacity="([0-9.]+)"')
	var opacity_match: RegExMatch = opacity_regex.search(svg_content_to_parse)
	
	if opacity_match and change_opacity_hslider and change_opacity_label:
		var opacity_str: String = opacity_match.get_string(1)
		var opacity_value: float = opacity_str.to_float()
		if opacity_value >= 0 and opacity_value <= 1:
			change_opacity_hslider.value = opacity_value
			change_opacity_label.text = "%.2f" % opacity_value

# Handle change opacity button press
func _on_change_opacity_pressed() -> void:
	if svg_contents.is_empty():
		_show_error("No SVG content to modify opacity!")
		return

	if not change_opacity_hslider:
		push_error("No opacity slider assigned!")
		return

	var opacity_value: float = change_opacity_hslider.value

	# If we have multiple files loaded, handle them as a batch
	if current_svg_paths.size() > 1:
		var is_adding: bool = (change_opacity_button.text == "Add Opacity Attribute?")
		
		var dialog_text: String
		if is_adding:
			dialog_text = "Some files are missing the opacity attribute. Add it to all SVGs that need it?\nNew opacity: " + str(opacity_value)
		else: # is updating
			dialog_text = "Update opacity in all " + str(current_svg_paths.size()) + " loaded SVG files?\nNew opacity: " + str(opacity_value)

		var confirmation_dialog: ConfirmationDialog = ConfirmationDialog.new()
		confirmation_dialog.dialog_text = dialog_text
		confirmation_dialog.title = "Update All Files"
		get_viewport().add_child(confirmation_dialog)
		confirmation_dialog.popup_centered()

		confirmation_dialog.confirmed.connect(func() -> void:
			var modified_count: int = 0
			var added_count: int = 0

			for i in range(svg_contents.size()):
				var content: String = svg_contents[i]
				if content.is_empty(): continue
				
				var has_opacity: bool = content.contains("opacity=")

				if is_adding:
					if not has_opacity:
						svg_contents[i] = _add_opacity_attribute(content, opacity_value)
						added_count += 1
				else: # is updating, so update all files
					if has_opacity:
						svg_contents[i] = _update_svg_opacity(content, opacity_value)
						modified_count += 1
					else: # If updating all, and one is missing, add it
						svg_contents[i] = _add_opacity_attribute(content, opacity_value)
						added_count += 1

			if (modified_count + added_count) > 0:
				has_changes = true
				_display_all_svg_files()
				var message: String = "Updated opacity in " + str(modified_count) + " files and added to " + str(added_count) + " files."
				_show_success(message + " (Not saved yet!)")
			
			# Reset button text after operation
			change_opacity_button.text = "Change Opacity"
			confirmation_dialog.queue_free()
		)
		confirmation_dialog.canceled.connect(func() -> void: confirmation_dialog.queue_free())

	else:
		# Single file or direct content
		if svg_contents.size() > 0 and not svg_contents[0].is_empty():
			var updated_svg: String
			var message: String
			var has_opacity: bool = svg_contents[0].contains("opacity=")

			if has_opacity:
				updated_svg = _update_svg_opacity(svg_contents[0], opacity_value)
				message = "Opacity updated successfully."
			else:
				updated_svg = _add_opacity_attribute(svg_contents[0], opacity_value)
				message = "Opacity attribute added."
				# Update button text since we now have opacity
				change_opacity_button.text = "Change Opacity"

			# Update the stored content
			svg_contents[0] = updated_svg
			has_changes = true

			# Display the updated content and show success
			_display_all_svg_files()
			_show_success(message + " (Not saved yet!)")

# Update existing opacity attributes in SVG
func _update_svg_opacity(svg_str: String, opacity_value: float) -> String:
	var result: String = svg_str
	
	# Replace opacity attributes
	var regex: RegEx = RegEx.new()
	regex.compile('opacity="[^"]+"')
	result = regex.sub(result, 'opacity="' + str(opacity_value) + '"', true)
	
	return result

# Colorize SVG attribute names (width, height, fill, stroke, opacity) in green
func _colorize_svg_attributes(content_to_colorize: String) -> String:
	var result: String = content_to_colorize
	
	# Define patterns for the attributes we want to colorize
	var attribute_patterns: Array[String] = [
		"width=",
		"height=",
		"fill=",
		"stroke=",
		"opacity=",
		"fill:",  # For style attributes
		"stroke:"  # For style attributes
	]
	
	# Replace each attribute name with colored version
	for pattern in attribute_patterns:
		result = result.replace(pattern, "[color=green]" + pattern + "[/color]")
	
	return result

# Add opacity attribute to SVG elements that have color attributes
func _add_opacity_attribute(svg_str: String, opacity_value: float) -> String:
	var result: String = svg_str
	
	# Add opacity after fill attribute
	var fill_regex: RegEx = RegEx.new()
	fill_regex.compile('(fill="[^"]+")')
	var matches: Array = fill_regex.search_all(result)
	
	# Process matches in reverse order to maintain string positions
	for i in range(matches.size() - 1, -1, -1):
		var match: RegExMatch = matches[i]
		var pos: int = match.get_end()
		# Check if opacity doesn't already exist nearby
		var check_area: String = result.substr(pos, min(50, result.length() - pos))
		if not check_area.contains("opacity="):
			result = result.insert(pos, ' opacity="' + str(opacity_value) + '"')
	
	# Add opacity after stroke attribute if no fill attribute
	var stroke_regex: RegEx = RegEx.new()
	stroke_regex.compile('(stroke="[^"]+")')
	matches = stroke_regex.search_all(result)
	
	for i in range(matches.size() - 1, -1, -1):
		var match: RegExMatch = matches[i]
		var pos: int = match.get_end()
		# Check if opacity doesn't already exist nearby
		var check_area: String = result.substr(max(0, pos - 50), min(100, result.length() - pos + 50))
		if not check_area.contains("opacity="):
			result = result.insert(pos, ' opacity="' + str(opacity_value) + '"')
	
	return result

# Handle file dialog button press
func _on_file_dialog_button_pressed() -> void:
	if file_dialog:
		file_dialog.popup_centered()

# Handle files selected in file dialog
func _on_file_dialog_files_selected(selected_files: PackedStringArray) -> void:
	if selected_files.size() > 0:
		load_svg_files(selected_files)

# Handle opacity preset selection
func _on_opacity_preset_selected(index: int) -> void:
	if opacity_presets:
		# Get the opacity percentage from the selected item's id
		var opacity_percentage: int = opacity_presets.get_item_id(index)
		# Convert percentage to 0-1 range
		var opacity_value: float = opacity_percentage / 100.0
		
		# Update the slider and label
		if change_opacity_hslider:
			change_opacity_hslider.value = opacity_value
		
		if change_opacity_label:
			change_opacity_label.text = "%.2f" % opacity_value
