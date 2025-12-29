extends Node
## Global Theme Manager
## Handles theme selection and application across the entire game

signal theme_changed(new_theme: Theme)

const KenneyThemeGenerator = preload("res://scripts/kenney_theme_generator.gd")

# Current theme settings
var current_style: KenneyThemeGenerator.ThemeStyle = KenneyThemeGenerator.ThemeStyle.FANTASY_BLUE
var current_theme: Theme = null

# Settings file path
const SETTINGS_PATH = "user://theme_settings.json"


func _ready() -> void:
	# Load saved theme preference
	_load_theme_preference()

	# Create initial theme
	current_theme = KenneyThemeGenerator.create_theme(current_style)

	print("Theme Manager initialized with: %s" % KenneyThemeGenerator.THEME_CONFIGS[current_style].name)


## Get the current theme
func get_current_theme() -> Theme:
	return current_theme


## Set theme by style enum
func set_theme_style(style: KenneyThemeGenerator.ThemeStyle) -> void:
	current_style = style
	current_theme = KenneyThemeGenerator.create_theme(style)

	# Save preference
	_save_theme_preference()

	# Emit signal for any listeners
	theme_changed.emit(current_theme)

	print("Theme changed to: %s" % KenneyThemeGenerator.THEME_CONFIGS[style].name)


## Set theme by name string
func set_theme_by_name(theme_name: String) -> void:
	var style = KenneyThemeGenerator.get_style_from_name(theme_name)
	set_theme_style(style)


## Get all available theme names
func get_available_themes() -> Array[String]:
	return KenneyThemeGenerator.get_theme_names()


## Get current theme name
func get_current_theme_name() -> String:
	return KenneyThemeGenerator.THEME_CONFIGS[current_style].name


## Check if current theme is SciFi
func is_scifi_theme() -> bool:
	return KenneyThemeGenerator.THEME_CONFIGS[current_style].is_scifi


## Check if current theme is Fantasy
func is_fantasy_theme() -> bool:
	return not KenneyThemeGenerator.THEME_CONFIGS[current_style].is_scifi


## Save theme preference to file
func _save_theme_preference() -> void:
	var settings = {
		"theme_style": current_style,
		"theme_name": get_current_theme_name()
	}

	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()
		print("Theme preference saved: %s" % get_current_theme_name())
	else:
		push_warning("Failed to save theme preference")


## Load theme preference from file
func _load_theme_preference() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		# Use default
		current_style = KenneyThemeGenerator.ThemeStyle.FANTASY_BLUE
		return

	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		push_warning("Failed to load theme preference")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result == OK:
		var data = json.data
		if data is Dictionary and data.has("theme_style"):
			current_style = data.theme_style as KenneyThemeGenerator.ThemeStyle
			print("Loaded theme preference: %s" % data.get("theme_name", "Unknown"))
	else:
		push_warning("Failed to parse theme settings JSON")
