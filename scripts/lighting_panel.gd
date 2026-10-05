extends CanvasLayer
## Settings Panel — Lighting & Audio controls
## Interactive UI with sliders for all lighting and volume parameters

const LAYER := 0   # under the HUD layer (1): the menu, rail and top bar stay clickable, as with the old OS window
const SHEET_W := 520
const SCROLL_H := 620

var lighting_controller: Node
var atmosphere_controller: Node = null
var privacy_menu: PrivacyMenu = null

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

	visibility_changed.connect(func() -> void:
		if visible:
			UiPolish.grab_first_focus.call_deferred(self))


## Settings > Privacy & data > Help improve the computer opponent.
func set_privacy_menu(menu: PrivacyMenu) -> void:
	privacy_menu = menu
	if _main_vbox == null:
		return
	var separator := HSeparator.new()
	separator.name = "PrivacySeparator"
	_main_vbox.add_child(separator)
	var label := Label.new()
	label.name = "PrivacyDataLabel"
	label.text = privacy_menu.localized_text("settings_section")
	label.add_theme_font_size_override("font_size", 16)
	_main_vbox.add_child(label)
	var button := Button.new()
	button.name = "PrivacyDataButton"
	button.text = privacy_menu.localized_text("heading")
	button.pressed.connect(func() -> void:
		privacy_menu.open_settings())
	_main_vbox.add_child(button)


func _build_ui() -> void:
	layer = LAYER
	var parts := HouseStyle.overlay_sheet("Settings", SHEET_W)
	(parts["close"] as Button).pressed.connect(hide)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, SCROLL_H)
	(parts["body"] as VBoxContainer).add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.add_child(vbox)
	_main_vbox = vbox
	# Not modal, like the old window: no scrim over the table (the lighting is tuned by eye) and its clicks pass through.
	var root := parts["root"] as Control
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(root.get_node("Scrim") as ColorRect).visible = false
	add_child(parts["root"] as Control)
	visibility_changed.connect(func() -> void:
		if visible:
			_restyle())

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

	# Developer tool: dumps the current lighting preset as pasteable code. Useful internally
	# for authoring atmosphere presets, but in a shipped build it reads as an unfinished UI
	# (there is no console for the player to read) — so it exists only in debug builds.
	if OS.is_debug_build():
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

	# Monitor (NML-1078 / GH #363): pick which screen the window opens/moves to. Only shown
	# with more than one screen attached — nothing to choose between on a single monitor.
	var screen_count := DisplayServer.get_screen_count()
	if screen_count > 1:
		var monitor_row := HBoxContainer.new()
		monitor_row.add_theme_constant_override("separation", 8)
		var monitor_lbl := Label.new()
		monitor_lbl.text = "Monitor"
		monitor_row.add_child(monitor_lbl)
		var monitor_ob := OptionButton.new()
		monitor_ob.add_item("Primary")
		monitor_ob.set_item_id(0, -1)
		for i in range(screen_count):
			monitor_ob.add_item("Monitor %d" % (i + 1))
			monitor_ob.set_item_id(monitor_ob.item_count - 1, i)
		for i in range(monitor_ob.item_count):
			if monitor_ob.get_item_id(i) == GraphicsSettings.screen_index:
				monitor_ob.select(i)
				break
		monitor_ob.item_selected.connect(func(index: int) -> void:
			var value := monitor_ob.get_item_id(index)
			GraphicsSettings.screen_index = value
			GraphicsSettings.apply_screen(value)
			GraphicsSettings.save_settings())
		monitor_row.add_child(monitor_ob)
		vbox.add_child(monitor_row)

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

	# Show Rule Texts (transparency stage 2): the floats' discoverable switch — the
	# maintainer's release pass could not find the toggle because only the setting existed.
	var floats_cb := CheckButton.new()
	floats_cb.text = "Show Rule Texts at the Table"
	floats_cb.button_pressed = GraphicsSettings.show_rule_floats
	floats_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.show_rule_floats = on
		GraphicsSettings.save_settings()
		var rf := get_node_or_null("/root/Main/FloatingRuleText")
		if rf != null:
			rf.enabled = on)
	vbox.add_child(floats_cb)

	# Combat effects (result marks, shots, falls, spells, hero auras): one switch for all of them; an effect that is
	# not in the game yet is skipped.
	var vfx_cb := CheckButton.new()
	vfx_cb.text = "Combat Effects (preview)"
	vfx_cb.button_pressed = GraphicsSettings.show_combat_effects
	vfx_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.show_combat_effects = on
		GraphicsSettings.save_settings()
		for fx_name in ["ResultPips", "VolleyCue", "SpellSeal", "ShotShow", "SpellShow", "CasualtyShow", "ModelAuras"]:
			var fx := get_node_or_null("/root/Main/" + fx_name)
			if fx != null:
				fx.enabled = on)
	vbox.add_child(vfx_cb)

	# Tilt-Shift (cinematic depth of field): sharp while zoomed out, softly blurred in
	# the foreground/background as the camera zooms towards the models. On by default;
	# persisted; CameraController applies it live.
	var tilt_cb := CheckButton.new()
	tilt_cb.text = "Tilt-Shift (Depth of Field)"
	tilt_cb.button_pressed = GraphicsSettings.tilt_shift
	tilt_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.tilt_shift = on
		GraphicsSettings.save_settings()
		var pivot := get_node_or_null("/root/Main/CameraPivot")
		if pivot != null and pivot.has_method("set_tilt_shift_enabled"):
			pivot.set_tilt_shift_enabled(on))
	vbox.add_child(tilt_cb)
	var frame := OptionButton.new()
	frame.name = "TableFrameOption"
	for title in ["Frame: Today's look", "Frame: Walnut", "Frame: Oak", "Frame: Ivory"]:
		frame.add_item(title)
	frame.select(GraphicsSettings.table_frame_style)
	frame.tooltip_text = "Frame finish. Active at Medium quality and above."
	frame.item_selected.connect(GraphicsSettings.set_table_frame_style)
	vbox.add_child(frame)

	# Gore (combat effects): how bloody wounds and casualties look — Off shows dust instead of blood.
	var gore_row := HBoxContainer.new()
	gore_row.add_theme_constant_override("separation", 8)
	var gore_lbl := Label.new()
	gore_lbl.text = "Gore"
	gore_row.add_child(gore_lbl)
	var gore_ob := OptionButton.new()
	for item in ["Off", "Normal", "Extra"]:
		gore_ob.add_item(item)
	gore_ob.select(clampi(GraphicsSettings.gore_level, 0, 2))
	gore_ob.item_selected.connect(func(index: int) -> void:
		GraphicsSettings.gore_level = index
		GraphicsSettings.save_settings())
	gore_row.add_child(gore_ob)
	vbox.add_child(gore_row)

	# Pacing grill 31.07.: the combat stage's discoverable switch + its beat length.
	var stage_cb := CheckButton.new()
	stage_cb.text = "Combat Stage (paces the resolution)"
	stage_cb.button_pressed = GraphicsSettings.show_combat_stage
	stage_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.show_combat_stage = on
		GraphicsSettings.save_settings())
	vbox.add_child(stage_cb)
	var beat_row := HBoxContainer.new()
	beat_row.add_theme_constant_override("separation", 8)
	var beat := HSlider.new()
	beat.min_value = 1.0
	beat.max_value = 6.0
	beat.step = 0.5
	beat.value = GraphicsSettings.combat_stage_hold_s
	beat.custom_minimum_size = Vector2(140, 0)
	beat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	beat_row.add_child(beat)
	var beat_lbl := Label.new()
	beat_lbl.text = "Stage beat: %.1fs" % GraphicsSettings.combat_stage_hold_s
	beat_row.add_child(beat_lbl)
	beat.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.combat_stage_hold_s = v
		beat_lbl.text = "Stage beat: %.1fs" % v
		GraphicsSettings.save_settings())
	vbox.add_child(beat_row)

	# Enforce Movement Limit (path-painting "dry brush"): Strict = a movement drag hard-stops
	# at the model's max legal band; off = Casual (free drag). DEFAULT ON. Persisted. Movement
	# only — shooting and other actions are never gated. English-only, like the rest of the UI.
	var limit_cb := CheckButton.new()
	limit_cb.text = "Enforce Movement Limit"
	limit_cb.tooltip_text = "Strict: a movement drag hard-stops at the model's maximum legal range (Rush/Charge). Off = Casual (free drag)."
	limit_cb.button_pressed = GraphicsSettings.enforce_movement_limit
	limit_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.enforce_movement_limit = on
		GraphicsSettings.save_settings())
	vbox.add_child(limit_cb)

	# NML-955: AI EXPLANATION toasts (which unit NACHTMAHR picked, what it shot, what the roll did)
	# stay up until the next event replaces them or you click them away. DEFAULT ON. Persisted.
	# Operational notices (export path, autosave) always fade — this switch does not reach them.
	var explain_cb := CheckButton.new()
	explain_cb.text = "AI Explanations Stay Up"
	explain_cb.tooltip_text = "On: NACHTMAHR's explanation stays on screen until the next event replaces it or you click it away. Off: it fades after a few seconds. Operational notices (export path, autosave) always fade."
	explain_cb.button_pressed = GraphicsSettings.ai_explain_persistent
	explain_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.ai_explain_persistent = on
		GraphicsSettings.save_settings())
	vbox.add_child(explain_cb)


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
	picker.theme_type_variation = HouseStyle.BUTTON   # the swatch needs a box and a size under the house theme
	picker.custom_minimum_size = Vector2(56, HouseStyle.H_PIP)
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




## House look for everything the sheet holds, late additions (atmosphere, privacy, the menu's background
## dropdown) included: section titles are eyebrows, lines are ghost buttons, the rest is body text. A control
## that already carries a variation keeps it. Runs on every open, so it is cheap and idempotent.
func _restyle() -> void:
	for n: Node in find_children("*", "Control", true, false):
		if n is Label:
			var l := n as Label
			if l.theme_type_variation != &"":
				continue
			var title := l.has_theme_font_size_override("font_size")
			l.remove_theme_font_size_override("font_size")
			l.theme_type_variation = HouseStyle.EYEBROW if title else HouseStyle.BODY
		elif n is Button and not (n is CheckButton or n is ColorPickerButton) and (n as Button).theme_type_variation == &"":
			(n as Button).theme_type_variation = HouseStyle.BUTTON
			(n as Button).custom_minimum_size.y = HouseStyle.H_SEGMENT


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()


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
