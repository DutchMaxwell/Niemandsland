extends Window
## Lighting Control Panel
## Interactive UI with sliders for all lighting parameters

var lighting_controller: Node

# UI References
var sliders: Dictionary = {}
var color_pickers: Dictionary = {}
var preset_buttons: Array = []

# Parameters to control
const PARAMS = {
	"sun_energy": {"label": "Sun Energy", "min": 0.0, "max": 3.0, "step": 0.1},
	"sun_angle_h": {"label": "Sun Horizontal Angle", "min": -180.0, "max": 180.0, "step": 1.0},
	"sun_angle_v": {"label": "Sun Vertical Angle", "min": -90.0, "max": 90.0, "step": 1.0},
	"ambient_energy": {"label": "Ambient Energy", "min": 0.0, "max": 2.0, "step": 0.1},
	"exposure": {"label": "Exposure", "min": 0.5, "max": 2.0, "step": 0.1},
	"shadow_opacity": {"label": "Shadow Opacity", "min": 0.0, "max": 1.0, "step": 0.05},
	"shadow_blur": {"label": "Shadow Blur", "min": 0.0, "max": 5.0, "step": 0.5},
	"ssao_intensity": {"label": "SSAO Intensity", "min": 0.0, "max": 4.0, "step": 0.1},
	"ssr_intensity": {"label": "SSR Intensity", "min": 0.0, "max": 2.0, "step": 0.1},
	"glow_intensity": {"label": "Glow Intensity", "min": 0.0, "max": 2.0, "step": 0.1},
	"contrast": {"label": "Contrast", "min": 0.5, "max": 2.0, "step": 0.05},
	"saturation": {"label": "Saturation", "min": 0.5, "max": 1.5, "step": 0.05},
}


func initialize(light_ctrl: Node) -> void:
	lighting_controller = light_ctrl
	_build_ui()
	_sync_ui_from_controller()

	# Connect close button signal
	close_requested.connect(func(): hide())


func _build_ui() -> void:
	# Apply Kenney UI theme from global ThemeManager
	var kenney_theme = ThemeManager.get_current_theme()

	title = "Lighting Settings"
	size = Vector2i(500, 800)
	position = Vector2i(50, 50)

	# Listen for theme changes
	ThemeManager.theme_changed.connect(_on_theme_changed)

	# Main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = kenney_theme
	add_child(margin)

	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	# Scroll container for all controls
	var scroll = ScrollContainer.new()
	scroll.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.theme = kenney_theme
	margin.add_child(scroll)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	vbox.theme = kenney_theme
	scroll.add_child(vbox)

	# Presets Section
	var preset_label = Label.new()
	preset_label.text = "PRESETS:"
	preset_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(preset_label)

	var preset_grid = GridContainer.new()
	preset_grid.columns = 2
	vbox.add_child(preset_grid)

	var preset_names = lighting_controller.get_preset_names()
	for preset_name in preset_names:
		var btn = Button.new()
		btn.text = preset_name
		btn.pressed.connect(_on_preset_pressed.bind(preset_name))
		preset_grid.add_child(btn)
		preset_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	# Parameters Section
	var params_label = Label.new()
	params_label.text = "PARAMETERS:"
	params_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(params_label)

	# Color pickers
	_add_color_picker(vbox, "sun_color", "Sun Color")
	_add_color_picker(vbox, "ambient_color", "Ambient Color")

	vbox.add_child(HSeparator.new())

	# Sliders
	for param_key in PARAMS:
		var param_data = PARAMS[param_key]
		_add_slider(vbox, param_key, param_data)

	vbox.add_child(HSeparator.new())

	# Action buttons
	var action_hbox = HBoxContainer.new()
	vbox.add_child(action_hbox)

	var print_btn = Button.new()
	print_btn.text = "Print to Console"
	print_btn.pressed.connect(_on_print_pressed)
	action_hbox.add_child(print_btn)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): hide())
	action_hbox.add_child(close_btn)


func _add_slider(parent: Control, key: String, data: Dictionary) -> void:
	var container = VBoxContainer.new()
	parent.add_child(container)

	# Label with value
	var label_hbox = HBoxContainer.new()
	container.add_child(label_hbox)

	var label = Label.new()
	label.text = data.label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_hbox.add_child(label)

	var value_label = Label.new()
	value_label.name = key + "_value"
	value_label.text = "0.0"
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_hbox.add_child(value_label)

	# Slider
	var slider = HSlider.new()
	slider.min_value = data.min
	slider.max_value = data.max
	slider.step = data.step
	slider.value = (data.min + data.max) / 2.0
	slider.value_changed.connect(_on_slider_changed.bind(key, value_label))
	container.add_child(slider)

	sliders[key] = slider


func _add_color_picker(parent: Control, key: String, label_text: String) -> void:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(label)

	var picker = ColorPickerButton.new()
	picker.color = Color.WHITE
	picker.color_changed.connect(_on_color_changed.bind(key))
	hbox.add_child(picker)

	color_pickers[key] = picker


func _on_slider_changed(value: float, key: String, value_label: Label) -> void:
	value_label.text = "%.2f" % value

	# Update lighting controller
	match key:
		"sun_energy":
			lighting_controller.set_sun_energy(value)
		"sun_angle_h":
			var v = sliders["sun_angle_v"].value
			lighting_controller.set_sun_angles(value, v)
		"sun_angle_v":
			var h = sliders["sun_angle_h"].value
			lighting_controller.set_sun_angles(h, value)
		"ambient_energy":
			lighting_controller.set_ambient_energy(value)
		"exposure":
			lighting_controller.set_exposure(value)
		"shadow_opacity":
			lighting_controller.set_shadow_opacity(value)
		"shadow_blur":
			lighting_controller.set_shadow_blur(value)
		"ssao_intensity":
			lighting_controller.set_ssao_intensity(value)
		"ssr_intensity":
			lighting_controller.set_ssr_intensity(value)
		"glow_intensity":
			lighting_controller.set_glow_intensity(value)
		"contrast":
			lighting_controller.set_contrast(value)
		"saturation":
			lighting_controller.set_saturation(value)


func _on_color_changed(color: Color, key: String) -> void:
	match key:
		"sun_color":
			lighting_controller.set_sun_color(color)
		"ambient_color":
			lighting_controller.set_ambient_color(color)


func _on_preset_pressed(preset_name: String) -> void:
	lighting_controller.apply_preset(preset_name)
	_sync_ui_from_controller()


func _on_print_pressed() -> void:
	lighting_controller.print_current_settings()


func _sync_ui_from_controller() -> void:
	var preset = lighting_controller.current_preset

	# Update sliders
	for key in sliders:
		if preset.has(key):
			sliders[key].value = preset[key]
			var value_label = get_node_or_null("MarginContainer/ScrollContainer/VBoxContainer/" + key + "_value")
			if value_label:
				value_label.text = "%.2f" % preset[key]

	# Update color pickers
	if color_pickers.has("sun_color") and preset.has("sun_color"):
		color_pickers["sun_color"].color = preset.sun_color
	if color_pickers.has("ambient_color") and preset.has("ambient_color"):
		color_pickers["ambient_color"].color = preset.ambient_color


func _on_theme_changed(_new_theme: Theme) -> void:
	"""Handle theme changes from ThemeManager"""
	# Note: Since UI is built dynamically, we'd need to rebuild it to apply new theme
	# For now, this will apply on next window open
	print("Lighting panel will use new theme on next open: %s" % ThemeManager.get_current_theme_name())
