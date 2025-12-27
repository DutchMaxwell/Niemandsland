extends Window
## Theme Selector Window
## Allows users to choose between Fantasy and SciFi UI themes

const KenneyThemeGenerator = preload("res://scripts/kenney_theme_generator.gd")

var theme_buttons: Dictionary = {}


func _ready() -> void:
	_build_ui()

	# Connect close button
	close_requested.connect(func(): hide())


func _build_ui() -> void:
	# Apply current theme
	var current_theme = ThemeManager.get_current_theme()

	title = "Theme Selection"
	size = Vector2i(600, 500)
	position = Vector2i(200, 150)

	# Main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = current_theme
	add_child(margin)

	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.theme = current_theme
	margin.add_child(vbox)

	# Title label
	var title_label = Label.new()
	title_label.text = "Choose Your UI Theme:"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	vbox.add_child(HSeparator.new())

	# Current theme display
	var current_label = Label.new()
	current_label.text = "Current Theme: %s" % ThemeManager.get_current_theme_name()
	current_label.name = "CurrentThemeLabel"
	current_label.add_theme_font_size_override("font_size", 14)
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(current_label)

	vbox.add_child(HSeparator.new())

	# Scroll container for theme list
	var scroll = ScrollContainer.new()
	scroll.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.theme = current_theme
	vbox.add_child(scroll)

	# Theme list VBox
	var theme_vbox = VBoxContainer.new()
	theme_vbox.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.add_child(theme_vbox)

	# Fantasy section
	var fantasy_label = Label.new()
	fantasy_label.text = "FANTASY THEMES:"
	fantasy_label.add_theme_font_size_override("font_size", 16)
	theme_vbox.add_child(fantasy_label)

	var fantasy_grid = GridContainer.new()
	fantasy_grid.columns = 2
	theme_vbox.add_child(fantasy_grid)

	_add_theme_button(fantasy_grid, KenneyThemeGenerator.ThemeStyle.FANTASY_BEIGE)
	_add_theme_button(fantasy_grid, KenneyThemeGenerator.ThemeStyle.FANTASY_BLUE)
	_add_theme_button(fantasy_grid, KenneyThemeGenerator.ThemeStyle.FANTASY_BROWN)
	_add_theme_button(fantasy_grid, KenneyThemeGenerator.ThemeStyle.FANTASY_GREY)

	theme_vbox.add_child(HSeparator.new())

	# SciFi section
	var scifi_label = Label.new()
	scifi_label.text = "SCIFI THEMES:"
	scifi_label.add_theme_font_size_override("font_size", 16)
	theme_vbox.add_child(scifi_label)

	var scifi_grid = GridContainer.new()
	scifi_grid.columns = 2
	theme_vbox.add_child(scifi_grid)

	_add_theme_button(scifi_grid, KenneyThemeGenerator.ThemeStyle.SCIFI_BLUE)
	_add_theme_button(scifi_grid, KenneyThemeGenerator.ThemeStyle.SCIFI_GREEN)
	_add_theme_button(scifi_grid, KenneyThemeGenerator.ThemeStyle.SCIFI_GREY)
	_add_theme_button(scifi_grid, KenneyThemeGenerator.ThemeStyle.SCIFI_RED)
	_add_theme_button(scifi_grid, KenneyThemeGenerator.ThemeStyle.SCIFI_YELLOW)

	vbox.add_child(HSeparator.new())

	# Bottom buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_hbox)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): hide())
	button_hbox.add_child(close_btn)

	# Highlight current theme
	_update_button_highlights()


func _add_theme_button(parent: Control, style: KenneyThemeGenerator.ThemeStyle) -> void:
	var config = KenneyThemeGenerator.THEME_CONFIGS[style]

	var btn = Button.new()
	btn.text = config.name
	btn.custom_minimum_size = Vector2(250, 40)
	btn.pressed.connect(_on_theme_button_pressed.bind(style))
	parent.add_child(btn)

	theme_buttons[style] = btn


func _on_theme_button_pressed(style: KenneyThemeGenerator.ThemeStyle) -> void:
	# Apply the selected theme
	ThemeManager.set_theme_style(style)

	# Update current theme label
	var current_label = get_node_or_null("MarginContainer/VBoxContainer/CurrentThemeLabel")
	if current_label:
		current_label.text = "Current Theme: %s" % ThemeManager.get_current_theme_name()

	# Update button highlights
	_update_button_highlights()

	print("Theme selected: %s" % KenneyThemeGenerator.THEME_CONFIGS[style].name)


func _update_button_highlights() -> void:
	var current_style = ThemeManager.current_style

	for style in theme_buttons:
		var btn: Button = theme_buttons[style]
		if style == current_style:
			# Highlight current theme button
			btn.text = "✓ " + KenneyThemeGenerator.THEME_CONFIGS[style].name
		else:
			btn.text = KenneyThemeGenerator.THEME_CONFIGS[style].name
