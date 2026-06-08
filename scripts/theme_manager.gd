extends Node
## Global Theme Manager
## Provides the Glassmorphism UI theme

const GlassmorphismTheme = preload("res://scripts/glassmorphism_theme.gd")

var current_theme: Theme = null


func _ready() -> void:
	current_theme = GlassmorphismTheme.get_theme()
	print("Theme Manager initialized with: Glassmorphism")


## Get the current theme
func get_current_theme() -> Theme:
	if not current_theme:
		current_theme = GlassmorphismTheme.get_theme()
	return current_theme


## Get current theme name
func get_current_theme_name() -> String:
	return "Glassmorphism"
