extends Window
## Settings Panel — Lighting & Audio controls
## Interactive UI with sliders for all lighting and volume parameters

var lighting_controller: Node
var atmosphere_controller: Node = null

# UI References
var sliders: Dictionary = {}
var color_pickers: Dictionary = {}
var volume_sliders: Dictionary = {}
var _main_vbox: VBoxContainer = null

## True while _sync_ui_from_controller is pushing controller values INTO the widgets.
## Setting slider.value / picker.color emits value_changed/color_changed, which would
## otherwise call the change handlers and write the (half-synced) widget values BACK
## into the controller — clobbering e.g. the sun angle. Guard the handlers with this.
var _syncing := false

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


## Late wiring (the atmosphere controller is created after this panel): adds the
## one-click atmosphere section at the top of the settings list.
func set_atmosphere_controller(atmosphere_ctrl: Node) -> void:
	atmosphere_controller = atmosphere_ctrl
	atmosphere_controller.atmosphere_changed.connect(func(_name: String) -> void:
		_sync_ui_from_controller())
	if _main_vbox == null:
		return

	var section := VBoxContainer.new()
	var atmosphere_label := Label.new()
	atmosphere_label.text = "ATMOSPHERE:"
	atmosphere_label.add_theme_font_size_override("font_size", 16)
	section.add_child(atmosphere_label)

	var grid := GridContainer.new()
	grid.columns = 3
	section.add_child(grid)
	for preset_name in atmosphere_controller.get_atmosphere_names():
		var btn := Button.new()
		btn.text = preset_name
		btn.pressed.connect(func() -> void:
			atmosphere_controller.apply_atmosphere(preset_name))
		grid.add_child(btn)

	var fires_toggle := CheckButton.new()
	fires_toggle.text = "War-torn (fires at ruins)"
	fires_toggle.button_pressed = atmosphere_controller.is_fires_enabled()
	fires_toggle.toggled.connect(func(on: bool) -> void:
		atmosphere_controller.set_fires_enabled(on))
	section.add_child(fires_toggle)

	var war_toggle := CheckButton.new()
	war_toggle.text = "Distant war sounds"
	war_toggle.button_pressed = atmosphere_controller.is_war_sounds_enabled()
	war_toggle.toggled.connect(func(on: bool) -> void:
		atmosphere_controller.set_war_sounds_enabled(on))
	section.add_child(war_toggle)

	section.add_child(HSeparator.new())
	_main_vbox.add_child(section)
	_main_vbox.move_child(section, 0)

	# Connect close button signal
	close_requested.connect(func(): hide())
	visibility_changed.connect(func() -> void:
		if visible:
			UiPolish.grab_first_focus.call_deferred(self))


func _build_ui() -> void:
	# Apply UI theme
	var ui_theme = ThemeManager.get_current_theme()

	title = "Settings"
	# 900px is taller than a 720p screen; clamp so the ScrollContainer below governs
	# overflow and every control stays reachable.
	UiPolish.keep_window_reachable(self, Vector2i(500, 900))
	position = Vector2i(50, 50)

	# Main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = ui_theme
	add_child(margin)

	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	# Scroll container for all controls
	var scroll = ScrollContainer.new()
	scroll.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.theme = ui_theme
	margin.add_child(scroll)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	vbox.theme = ui_theme
	scroll.add_child(vbox)
	_main_vbox = vbox

	# Lighting moods are chosen through the ATMOSPHERE section only (added at the top by
	# set_atmosphere_controller); the old standalone lighting "PRESETS" were a parallel,
	# confusing second system and have been removed. The PARAMETERS sliders below still
	# fine-tune the current atmosphere.

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

	# === Audio Volume Section ===
	vbox.add_child(HSeparator.new())

	var audio_label = Label.new()
	audio_label.text = "AUDIO:"
	audio_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(audio_label)

	var audio_buses = {
		AudioManager.BUS_MASTER: "Master Volume",
		AudioManager.BUS_MUSIC: "Music Volume",
		AudioManager.BUS_SFX: "SFX Volume",
		AudioManager.BUS_AMBIENCE: "Ambience Volume",
		AudioManager.BUS_UI: "UI Volume",
	}

	for bus_name: String in audio_buses:
		var bus_label_text: String = audio_buses[bus_name]
		_add_volume_slider(vbox, bus_name, bus_label_text)

	# === Display Section ===
	vbox.add_child(HSeparator.new())

	var display_label = Label.new()
	display_label.text = "DISPLAY:"
	display_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(display_label)

	_add_ui_scale_slider(vbox)

	# Reduce Motion (accessibility) — collapses UI micro-interactions.
	var reduce_cb := CheckButton.new()
	reduce_cb.text = "Reduce Motion"
	reduce_cb.button_pressed = GraphicsSettings.reduce_motion
	reduce_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.reduce_motion = on
		GraphicsSettings.save_settings())
	vbox.add_child(reduce_cb)

	# Fullscreen (safe borderless mode, not the crash-prone exclusive fullscreen).
	var fs_cb := CheckButton.new()
	fs_cb.text = "Fullscreen"
	fs_cb.button_pressed = GraphicsSettings.fullscreen
	fs_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.apply_fullscreen(on))
	vbox.add_child(fs_cb)

	# Show Move Trails (path painting): the discoverable twin of the T hotkey. Persisted
	# via GraphicsSettings; also pushed to the live MoveTrails node so it toggles at once.
	# The move LEDGER keeps recording regardless — only the visible chalk is switched.
	var trails_cb := CheckButton.new()
	trails_cb.text = "Show Move Trails"
	trails_cb.button_pressed = GraphicsSettings.show_move_trails
	trails_cb.toggled.connect(func(on: bool) -> void:
		var mt := get_node_or_null("/root/Main/MoveTrails")
		if mt != null and mt.has_method("set_user_show_trails"):
			mt.set_user_show_trails(on)   # updates the live node AND persists
		else:
			GraphicsSettings.show_move_trails = on
			GraphicsSettings.save_settings())
	vbox.add_child(trails_cb)

	# Enforce Movement Limit (path-painting "dry brush"): Strict = a movement drag hard-stops
	# at the model's max legal band; off = Casual (free drag). DEFAULT ON. Persisted. Movement
	# only — shooting and other actions are never gated. DE/EN by locale.
	var de := str(OS.get_locale()).begins_with("de")
	var limit_cb := CheckButton.new()
	limit_cb.text = "Bewegungslimit erzwingen" if de else "Enforce Movement Limit"
	limit_cb.tooltip_text = ("Strikt: Eine Bewegung stoppt hart bei der maximal erlaubten Reichweite des Modells (Rush/Charge). Aus = Casual (freies Ziehen)." if de
			else "Strict: a movement drag hard-stops at the model's maximum legal range (Rush/Charge). Off = Casual (free drag).")
	limit_cb.button_pressed = GraphicsSettings.enforce_movement_limit
	limit_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.enforce_movement_limit = on
		GraphicsSettings.save_settings())
	vbox.add_child(limit_cb)


## UI Scale slider (content_scale_factor) — reachability/HiDPI. Bound to GraphicsSettings.
func _add_ui_scale_slider(parent: Control) -> void:
	var container := VBoxContainer.new()
	parent.add_child(container)

	var label_hbox := HBoxContainer.new()
	container.add_child(label_hbox)

	var label := Label.new()
	label.text = "UI Scale"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_hbox.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%.2fx" % GraphicsSettings.ui_scale
	label_hbox.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = GraphicsSettings.UI_SCALE_MIN
	slider.max_value = GraphicsSettings.UI_SCALE_MAX
	slider.step = 0.05
	slider.value = GraphicsSettings.ui_scale
	slider.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.apply_ui_scale(v)
		value_label.text = "%.2fx" % v)
	container.add_child(slider)


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


func _add_volume_slider(parent: Control, bus_name: String, label_text: String) -> void:
	var container = VBoxContainer.new()
	parent.add_child(container)

	var label_hbox = HBoxContainer.new()
	container.add_child(label_hbox)

	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_hbox.add_child(label)

	var value_label = Label.new()
	value_label.text = "0 dB"
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_hbox.add_child(value_label)

	var slider = HSlider.new()
	slider.min_value = -40.0
	slider.max_value = 6.0
	slider.step = 1.0
	slider.value = AudioManager.get_bus_volume(bus_name)
	value_label.text = "%d dB" % int(slider.value)
	slider.value_changed.connect(_on_volume_slider_changed.bind(bus_name, value_label))
	container.add_child(slider)

	volume_sliders[bus_name] = slider


func _on_volume_slider_changed(value: float, bus_name: String, value_label: Label) -> void:
	value_label.text = "%d dB" % int(value)
	AudioManager.set_bus_volume(bus_name, value)


func _on_slider_changed(value: float, key: String, value_label: Label) -> void:
	value_label.text = "%.2f" % value

	# Ignore the value_changed emitted while we're pushing controller values into the
	# widgets (otherwise the half-synced slider values get written back, clobbering the
	# sun angle etc.).
	if _syncing:
		return

	# A manual slider tweak must not fight a running atmosphere preset blend.
	if atmosphere_controller:
		atmosphere_controller.cancel_transition()

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
	if _syncing:
		return
	match key:
		"sun_color":
			lighting_controller.set_sun_color(color)
		"ambient_color":
			lighting_controller.set_ambient_color(color)




func _on_print_pressed() -> void:
	lighting_controller.print_current_settings()


func _sync_ui_from_controller() -> void:
	_syncing = true
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

	_syncing = false
