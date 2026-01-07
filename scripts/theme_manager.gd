extends Node
## Global Theme Manager
## Handles theme selection and application across the entire game

signal theme_changed(new_theme: Theme)

const KenneyThemeGenerator = preload("res://scripts/kenney_theme_generator.gd")
const GlassmorphismTheme = preload("res://scripts/glassmorphism_theme.gd")

## Theme categories
enum ThemeCategory {
	GLASSMORPHISM,  # Modern glassmorphism style (default)
	KENNEY_FANTASY, # Legacy Kenney fantasy themes
	KENNEY_SCIFI    # Legacy Kenney scifi themes
}

# Current theme settings
var current_category: ThemeCategory = ThemeCategory.GLASSMORPHISM
var current_style: KenneyThemeGenerator.ThemeStyle = KenneyThemeGenerator.ThemeStyle.FANTASY_BLUE
var current_theme: Theme = null

# Settings file path
const SETTINGS_PATH = "user://theme_settings.json"


func _ready() -> void:
	# Load saved theme preference
	_load_theme_preference()

	# Create initial theme based on category
	_create_current_theme()

	print("Theme Manager initialized with: %s" % get_current_theme_name())


## Create theme based on current category
func _create_current_theme() -> void:
	match current_category:
		ThemeCategory.GLASSMORPHISM:
			current_theme = GlassmorphismTheme.get_theme()
		ThemeCategory.KENNEY_FANTASY, ThemeCategory.KENNEY_SCIFI:
			current_theme = KenneyThemeGenerator.create_theme(current_style)


## Get the current theme
func get_current_theme() -> Theme:
	return current_theme


## Set to Glassmorphism theme (modern default)
func set_glassmorphism_theme() -> void:
	current_category = ThemeCategory.GLASSMORPHISM
	_create_current_theme()
	_save_theme_preference()
	theme_changed.emit(current_theme)
	print("Theme changed to: Glassmorphism")


## Set theme by Kenney style enum (legacy)
func set_theme_style(style: KenneyThemeGenerator.ThemeStyle) -> void:
	current_style = style
	# Determine category from style
	if style in [KenneyThemeGenerator.ThemeStyle.FANTASY_BEIGE,
				 KenneyThemeGenerator.ThemeStyle.FANTASY_BLUE,
				 KenneyThemeGenerator.ThemeStyle.FANTASY_BROWN,
				 KenneyThemeGenerator.ThemeStyle.FANTASY_GREY]:
		current_category = ThemeCategory.KENNEY_FANTASY
	else:
		current_category = ThemeCategory.KENNEY_SCIFI

	_create_current_theme()
	_save_theme_preference()
	theme_changed.emit(current_theme)
	print("Theme changed to: %s" % KenneyThemeGenerator.THEME_CONFIGS[style].name)


## Set theme by name string
func set_theme_by_name(theme_name: String) -> void:
	if theme_name == "Glassmorphism":
		set_glassmorphism_theme()
	else:
		var style = KenneyThemeGenerator.get_style_from_name(theme_name)
		set_theme_style(style)


## Get all available theme names
func get_available_themes() -> Array[String]:
	var themes: Array[String] = ["Glassmorphism"]
	themes.append_array(KenneyThemeGenerator.get_theme_names())
	return themes


## Get current theme name
func get_current_theme_name() -> String:
	if current_category == ThemeCategory.GLASSMORPHISM:
		return "Glassmorphism"
	return KenneyThemeGenerator.THEME_CONFIGS[current_style].name


## Check if using Glassmorphism theme
func is_glassmorphism_theme() -> bool:
	return current_category == ThemeCategory.GLASSMORPHISM


## Check if current theme is SciFi (legacy)
func is_scifi_theme() -> bool:
	return current_category == ThemeCategory.KENNEY_SCIFI


## Check if current theme is Fantasy (legacy)
func is_fantasy_theme() -> bool:
	return current_category == ThemeCategory.KENNEY_FANTASY


## Save theme preference to file
func _save_theme_preference() -> void:
	var settings = {
		"theme_category": current_category,
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
		# Use Glassmorphism as default for new installs
		current_category = ThemeCategory.GLASSMORPHISM
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
		if data is Dictionary:
			# Load category (new format)
			if data.has("theme_category"):
				current_category = data.theme_category as ThemeCategory
			else:
				# Legacy format - default to Glassmorphism
				current_category = ThemeCategory.GLASSMORPHISM

			# Load Kenney style if applicable
			if data.has("theme_style"):
				current_style = data.theme_style as KenneyThemeGenerator.ThemeStyle

			print("Loaded theme preference: %s" % data.get("theme_name", "Glassmorphism"))
	else:
		push_warning("Failed to parse theme settings JSON")
