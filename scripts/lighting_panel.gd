extends CanvasLayer
## Settings Panel — Lighting & Audio controls
## Interactive UI with sliders for all lighting and volume parameters

const LAYER := 0   # under the HUD layer (1): the menu, rail and top bar stay clickable, as with the old OS window
const SHEET_W := 760
const SCROLL_H := 620
const PAGE_RAIL_W := 200   # the column of page buttons left of the content (sheet 05)
## In the menu the sheet is drawn at the mockup's size (up to this, with 128 px / 120 px of air) and its rail is wider.
const SHEET_MENU_W := 1340
const SHEET_MENU_H := 840
const PAGE_RAIL_MENU_W := 290
## One setting per row in the menu (sheet 05): at least this high, the control in a column of this width at the right.
const ROW_H := 78
const ROW_CONTROL_W := 470
const ROW_NAME_PX := 19
const ROW_FRAME_W := 300   # the table frame's dropdown
const ROW_DROPDOWN_H := 44   # a dropdown in a row (sheet 05 .dd)
const ROW_SEGMENT_H := 40    # the Quality segments, one joined group (sheet 05 .seg)
## The rail's page icons: own drawings in the menu rows' style (24 x 24 view box, white strokes, tinted by the button).
const PAGE_ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 24 24' fill='none' stroke='#fff' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'>%s</svg>"
const PAGE_ICONS := {
	"Display": "<rect x='3' y='4' width='18' height='12' rx='2'/><path d='M8 20h8M12 16v4'/>",
	"Graphics": "<path d='M4 7h10M18 7h2M4 17h4M12 17h8M14 4.5v5M8 14.5v5'/>",
	"Audio": "<path d='M4 9.5v5h3.5L13 19V5L7.5 9.5z'/><path d='M16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11'/>",
	"Gameplay": "<rect x='4' y='4' width='16' height='16' rx='3'/><circle cx='9' cy='9' r='1'/><circle cx='15' cy='9' r='1'/><circle cx='12' cy='12' r='1'/><circle cx='9' cy='15' r='1'/><circle cx='15' cy='15' r='1'/>",
	"Accessibility": "<circle cx='12' cy='5' r='2'/><path d='M5 9h14M12 9v5M9 21l3-7 3 7'/>",
	"Lighting lab": "<path d='M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.3 1 2.1h5c0-.8.4-1.6 1-2.1A6 6 0 0 0 12 3z'/>",
}
static var _page_icons: Dictionary = {}
## The sheet's pages, in rail order. Controls not sorted onto a page yet live on "Lighting lab".
const PAGES := ["Display", "Graphics", "Audio", "Gameplay", "Accessibility", "Lighting lab"]
const FIRST_PAGE := "Display"
## The pages whose settings live in GraphicsSettings: they get "Reset this page". Audio has none yet (its start values
## have no names in audio_manager.gd); Lighting lab tunes the light controller.
const RESETTABLE := ["Display", "Graphics", "Gameplay", "Accessibility"]
## The GraphicsSettings field behind each switch, by its label (sliders and dropdowns carry theirs as meta "setting").
const SWITCH_FIELDS := {"Fullscreen": "fullscreen", "Calm Mode": "calm_mode", "Reduce Motion": "reduce_motion",
	"Miniature Idle Motion": "idle_motion", "Show Move Trails": "show_move_trails",
	"Show Rule Texts at the Table": "show_rule_floats", "Combat Effects": "show_combat_effects",
	"Tilt-Shift (Depth of Field)": "tilt_shift", "Board Mist and Steam": "show_board_mist",
	"Combat Stage (paces the resolution)": "show_combat_stage", "Enforce Movement Limit": "enforce_movement_limit",
	"AI Explanations Stay Up": "ai_explain_persistent"}

var lighting_controller: Node
var atmosphere_controller: Node = null
var privacy_menu: PrivacyMenu = null

# UI References
var sliders: Dictionary = {}
var color_pickers: Dictionary = {}
var volume_sliders: Dictionary = {}
var _main_vbox: VBoxContainer = null
var _pages: Dictionary = {}          # page name -> its content box
var _page_buttons: Dictionary = {}   # page name -> its rail button
var _page_shown := ""
var _reset_button: Button = null
var _modal := false   # in the menu (set_modal(true)): the menu's scale and a scrim
var _sheet: Control
var _header: HBoxContainer
var _columns: HBoxContainer
var _rail: VBoxContainer
var _rail_head: VBoxContainer
var _rail_column: PanelContainer   # the rail's column: in the menu a darker well with a hairline at its right (sheet 05)
var _lab_sep: VBoxContainer
var _footer: HBoxContainer
var _graphics_rows := false
var _footer_note: Label
var _footer_close: Button
var _scroll: ScrollContainer
## Accessibility preset (GH #1634): the Calm toggle plus the individual switches it
## forces, kept in sync so the panel never shows a stale state.
var _calm_cb: CheckButton = null
var _switch_toggles: Dictionary = {}
var _quality_row: HBoxContainer = null   # Graphics: one segment per GraphicsSettings.QualityPreset, in enum order

## True while _sync_ui_from_controller is pushing controller values INTO the widgets.
## Setting slider.value / picker.color emits value_changed/color_changed, which would
## otherwise call the change handlers and write the (half-synced) widget values BACK
## into the controller — clobbering e.g. the sun angle. Guard the handlers with this.
var _syncing := false

## One line of help under each setting (D7 defaults, sheet 05), keyed by the name the player reads (or the node name of
## a control without one). Shown in the caption style; a setting not in the table has no line.
const HELP := {
	"Quality": "Shadows, reflections and effects in one step. Lower it if the table stutters.",
	"UI Scale": "The size of every window and label. Raise it on a small or distant screen.",
	"Fullscreen": "Fills the screen without a window frame.",
	"Monitor": "The screen the game opens on.",
	"Menu background": "The scene behind the main menu.",
	"Tilt-Shift (Depth of Field)": "Blurs the far edge so the table reads as miniatures.",
	"Board Mist and Steam": "Low haze over the board. Off on Performance and Low.",
	"Combat Effects": "Muzzle flashes, impacts and auras during play.",
	"Miniature Idle Motion": "Small breathing and head turns while models stand.",
	"TableFrameOption": "The look of the table's rim.",
	"Distant war sounds": "Far-off battle noise under the table's ambience.",
	"Master Volume": "Everything you hear.",
	"Music Volume": "The menu and table music.",
	"SFX Volume": "Dice, shots and impacts.",
	"Ambience Volume": "Wind, rain and the sound of the table.",
	"UI Volume": "Clicks and confirmations in the menus.",
	"Show Move Trails": "Chalk lines of this round's moves. The T key switches them too.",
	"Show Rule Texts at the Table": "A short rule text floats over the table when a rule applies.",
	"Combat Stage (paces the resolution)": "Plays a fight step by step instead of all at once.",
	"Enforce Movement Limit": "A move stops at the model's legal range. Off: free drag.",
	"AI Explanations Stay Up": "The opponent's explanation stays until the next event.",
	"Gore": "How wounds and casualties look. Off shows dust instead of blood.",
	"Calm Mode": "Turns down effects, motion and pulsing selection aids in one click.",
	"Reduce Motion": "Interface movements become short fades.",
}

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
			atmosphere_controller.choose_atmosphere(preset_name))   # a pick of his own: saved, it wins over the game system's default
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
	_page("Audio").add_child(war_toggle)

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
	_sheet = parts["sheet"] as Control
	_header = (parts["body"] as VBoxContainer).get_child(0) as HBoxContainer
	var columns := HBoxContainer.new()
	_columns = columns
	columns.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
	(parts["body"] as VBoxContainer).add_child(columns)
	var rail := VBoxContainer.new()
	rail.name = "PageRail"
	rail.custom_minimum_size = Vector2(PAGE_RAIL_W, 0)
	rail.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	var left := VBoxContainer.new()   # the rail, headed in the menu by the eyebrow and the title
	left.add_theme_constant_override(&"separation", 0)
	_rail_column = PanelContainer.new()
	_rail_column.name = "RailColumn"
	_rail_column.add_child(left)
	columns.add_child(_rail_column)
	_rail = rail
	_rail_head = _build_rail_head()
	left.add_child(_rail_head)
	left.add_child(rail)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, SCROLL_H)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.add_child(holder)
	var group := ButtonGroup.new()
	for page_name: String in PAGES:
		var page := VBoxContainer.new()
		page.name = "Page" + page_name.replace(" ", "")
		page.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		holder.add_child(page)
		_pages[page_name] = page
		var tab := Button.new()
		tab.name = "PageButton" + page_name.replace(" ", "")
		tab.text = page_name
		tab.toggle_mode = true
		tab.button_group = group
		tab.theme_type_variation = HouseStyle.SEGMENT
		tab.custom_minimum_size.y = HouseStyle.H_ACTION
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.pressed.connect(show_page.bind(page_name))
		if page_name == "Lighting lab":
			_lab_sep = _build_lab_separator()
			rail.add_child(_lab_sep)
		rail.add_child(tab)
		_page_buttons[page_name] = tab
	var vbox := _page("Lighting lab")
	_main_vbox = vbox
	show_page(FIRST_PAGE)
	_add_quality_row(_page("Graphics"))
	# Not modal, like the old window: no scrim over the table (the lighting is tuned by eye) and its clicks pass through.
	var root := parts["root"] as Control
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(root.get_node("Scrim") as ColorRect).visible = false
	add_child(parts["root"] as Control)
	# The footer row under the pages: in the menu the note at the left, Reset this page and a gold Close at the right.
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	_footer_note = HouseStyle.label("Changes apply at once and are saved.", HouseStyle.CAPTION)
	_footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_note.visible = false
	_footer.add_child(_footer_note)
	_reset_button = HouseStyle.button("Reset this page", HouseStyle.BUTTON)
	_reset_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_reset_button.pressed.connect(func() -> void: _ask_reset(_page_shown))
	_footer.add_child(_reset_button)
	_footer_close = HouseStyle.button("Close", HouseStyle.PRIMARY, HouseStyle.MENU_H_ACTION)
	_footer_close.name = "FooterClose"
	_footer_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_footer_close.custom_minimum_size.x = 180
	_footer_close.visible = false
	_footer_close.pressed.connect(hide)
	var cap := HouseStyle.key_cap_on_gold("Esc")
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cap.grow_vertical = Control.GROW_DIRECTION_BOTH
	cap.offset_left = -10
	cap.offset_right = -10
	_footer_close.add_child(cap)
	_footer.add_child(_footer_close)
	(parts["body"] as VBoxContainer).add_child(_footer)
	show_page(_page_shown)
	visibility_changed.connect(func() -> void:
		if visible:
			_restyle())
	_restyle.call_deferred()   # a sheet shown at once never fires visibility_changed: house look and help lines next frame

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
	_page("Audio").add_child(audio_label)

	var audio_buses = {
		AudioManager.BUS_MASTER: "Master Volume",
		AudioManager.BUS_MUSIC: "Music Volume",
		AudioManager.BUS_SFX: "SFX Volume",
		AudioManager.BUS_AMBIENCE: "Ambience Volume",
		AudioManager.BUS_UI: "UI Volume",
	}

	for bus_name: String in audio_buses:
		var bus_label_text: String = audio_buses[bus_name]
		_add_volume_slider(_page("Audio"), bus_name, bus_label_text)

	# === Display Section ===
	vbox.add_child(HSeparator.new())

	var display_label = Label.new()
	display_label.text = "DISPLAY:"
	display_label.add_theme_font_size_override("font_size", 16)
	_page("Display").add_child(display_label)

	# Calm mode (GH #1634, accessibility, from a player with ADHD): one switch that dials
	# the sensory load down — it is a preset over the switches below, snapshotting the
	# player's choices and restoring them when switched off. DEFAULT OFF.
	var calm_cb := CheckButton.new()
	calm_cb.text = "Calm Mode"
	calm_cb.tooltip_text = "Turns down combat effects, motion and pulsing selection aids in one click."
	calm_cb.button_pressed = GraphicsSettings.calm_mode
	calm_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.set_calm_mode(on))
	calm_cb.set_meta("calm", true)
	_calm_cb = calm_cb
	_page("Accessibility").add_child(calm_cb)
	GraphicsSettings.calm_mode_changed.connect(_on_calm_changed)

	_add_ui_scale_slider(_page("Display"))

	# Reduce Motion (accessibility) — collapses UI micro-interactions.
	var reduce_cb := CheckButton.new()
	reduce_cb.text = "Reduce Motion"
	reduce_cb.button_pressed = GraphicsSettings.reduce_motion
	reduce_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.reduce_motion = on
		GraphicsSettings.save_settings())
	_page("Accessibility").add_child(reduce_cb)
	_switch_toggles["reduce_motion"] = reduce_cb

	var idle_cb := CheckButton.new()
	idle_cb.text = "Miniature Idle Motion"
	idle_cb.button_pressed = GraphicsSettings.idle_motion
	idle_cb.tooltip_text = "Animate supported miniatures nearby. Off on Low/Performance and with Reduce Motion."
	idle_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.idle_motion = on
		GraphicsSettings.save_settings())
	_page("Graphics").add_child(idle_cb)
	_switch_toggles["idle_motion"] = idle_cb

	# Fullscreen (safe borderless mode, not the crash-prone exclusive fullscreen).
	var fs_cb := CheckButton.new()
	fs_cb.text = "Fullscreen"
	fs_cb.button_pressed = GraphicsSettings.fullscreen
	fs_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.apply_fullscreen(on))
	_page("Display").add_child(fs_cb)

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
		_page("Display").add_child(monitor_row)

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
	_page("Gameplay").add_child(trails_cb)

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
	_page("Gameplay").add_child(floats_cb)

	# Combat effects (result marks, shots, falls, spells, hero auras): one switch for all of them; an effect that is
	# not in the game yet is skipped.
	var vfx_cb := CheckButton.new()
	vfx_cb.text = "Combat Effects"
	vfx_cb.button_pressed = GraphicsSettings.show_combat_effects
	vfx_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.show_combat_effects = on
		GraphicsSettings.save_settings()
		for fx_name in ["ResultPips", "VolleyCue", "SpellSeal", "ShotShow", "SpellShow", "CasualtyShow", "ModelAuras"]:
			var fx := get_node_or_null("/root/Main/" + fx_name)
			if fx != null:
				fx.enabled = on)
	_page("Graphics").add_child(vfx_cb)
	_switch_toggles["show_combat_effects"] = vfx_cb

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
	_page("Graphics").add_child(tilt_cb)
	_switch_toggles["tilt_shift"] = tilt_cb

	# Low ground mist and wall steam on a generated board (dev flag): shader-only; off on Low/Performance and in calm mode.
	var mist_cb := CheckButton.new()
	mist_cb.text = "Board Mist and Steam"
	mist_cb.button_pressed = GraphicsSettings.show_board_mist
	mist_cb.tooltip_text = "Ground mist and steam on a generated board. Off on Low/Performance and in Calm mode."
	mist_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.show_board_mist = on
		GraphicsSettings.save_settings())
	_page("Graphics").add_child(mist_cb)
	var frame := OptionButton.new()
	frame.name = "TableFrameOption"
	for title in ["Frame: Today's look", "Frame: Walnut", "Frame: Oak", "Frame: Ivory"]:
		frame.add_item(title)
	frame.select(GraphicsSettings.table_frame_style)
	frame.set_meta("setting", "table_frame_style")
	frame.tooltip_text = "Frame finish. Active at Medium quality and above."
	frame.item_selected.connect(GraphicsSettings.set_table_frame_style)
	_page("Graphics").add_child(frame)

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
	gore_ob.set_meta("setting", "gore_level")
	gore_ob.item_selected.connect(func(index: int) -> void:
		GraphicsSettings.gore_level = index
		GraphicsSettings.save_settings())
	gore_row.add_child(gore_ob)
	_page("Gameplay").add_child(gore_row)

	# Pacing grill 31.07.: the combat stage's discoverable switch + its beat length.
	var stage_cb := CheckButton.new()
	stage_cb.text = "Combat Stage (paces the resolution)"
	stage_cb.button_pressed = GraphicsSettings.show_combat_stage
	stage_cb.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.show_combat_stage = on
		GraphicsSettings.save_settings())
	_page("Gameplay").add_child(stage_cb)
	var beat_row := HBoxContainer.new()
	beat_row.add_theme_constant_override("separation", 8)
	var beat := HSlider.new()
	beat.scrollable = false  # the wheel scrolls the list, it never sets a value
	beat.min_value = 1.0
	beat.max_value = 6.0
	beat.step = 0.5
	beat.value = GraphicsSettings.combat_stage_hold_s
	beat.custom_minimum_size = Vector2(140, 0)
	beat.set_meta("setting", "combat_stage_hold_s")
	beat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	beat_row.add_child(beat)
	var beat_lbl := Label.new()
	beat_lbl.text = "Stage beat: %.1fs" % GraphicsSettings.combat_stage_hold_s
	beat_row.add_child(beat_lbl)
	beat.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.combat_stage_hold_s = v
		beat_lbl.text = "Stage beat: %.1fs" % v
		GraphicsSettings.save_settings())
	_page("Gameplay").add_child(beat_row)

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
	_page("Gameplay").add_child(limit_cb)

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
	_page("Gameplay").add_child(explain_cb)


## Graphics > Quality: the five presets as a segment row. It sets the preset like the in-game dropdown does and
## follows every change of it (that dropdown, the auto-tier), so the two always agree.
func _add_quality_row(parent: Control) -> void:
	var quality := Label.new()
	quality.text = "Quality"
	parent.add_child(quality)
	var names: Array = GraphicsSettings.PRESETS.keys().map(func(p: int) -> String: return GraphicsSettings.PRESETS[p]["name"])
	_quality_row = HouseStyle.button_row(names, HouseStyle.SEGMENT)
	_quality_row.name = "QualityRow"
	for i in _quality_row.get_child_count():
		(_quality_row.get_child(i) as Button).pressed.connect(GraphicsSettings.apply_preset.bind(i))
	parent.add_child(_quality_row)
	GraphicsSettings.settings_applied.connect(_on_preset_applied)
	_on_preset_applied("")


func _on_preset_applied(_preset_name: String) -> void:
	for i in _quality_row.get_child_count():
		HouseStyle.set_selected(_quality_row.get_child(i) as Button, i == GraphicsSettings.current_preset)
	_on_calm_changed()   # a preset also sets Idle Motion: the switches show it at once


## Modal with the scrim (the menu: nothing behind the sheet is tuned by eye) or, as at the table, without a scrim and
## letting the clicks through (the lighting is tuned by eye there).
func set_modal(on: bool) -> void:
	_modal = on
	var root := get_child(0) as Control
	root.theme = HouseStyle.menu_theme() if on else HouseStyle.theme()
	_apply_menu_layout()
	if on and not get_viewport().size_changed.is_connected(_apply_menu_layout):
		get_viewport().size_changed.connect(_apply_menu_layout)
	root.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	(root.get_node("Scrim") as ColorRect).visible = on


## The head of the rail in the menu: the eyebrow and the title "Settings" (the sheet's own header row then shows only
## the close box).
func _build_rail_head() -> VBoxContainer:
	var head := VBoxContainer.new()
	head.name = "RailHead"
	head.add_theme_constant_override(&"separation", 6)
	head.visible = false
	head.add_child(HouseStyle.label("NIEMANDSLAND", HouseStyle.EYEBROW))
	var title := HouseStyle.label("Settings", HouseStyle.BODY)
	title.add_theme_font_override(&"font", HouseStyle.font(500))
	title.add_theme_font_size_override(&"font_size", HouseStyle.FONT_PAGE_TITLE)
	head.add_child(title)
	var air := Control.new()
	air.custom_minimum_size.y = HouseStyle.GAP_SECTION
	head.add_child(air)
	return head


## A rule with air above the Lighting lab, which stands apart from the settings pages (menu only).
func _build_lab_separator() -> VBoxContainer:
	var sep := VBoxContainer.new()
	sep.name = "LabSeparator"
	sep.visible = false
	var air := Control.new()
	air.custom_minimum_size.y = 18
	sep.add_child(air)
	var rule := ColorRect.new()
	rule.color = HouseStyle.LINE
	rule.custom_minimum_size.y = 1
	sep.add_child(rule)
	return sep


## The sheet in the menu (sheet 05): up to 1340 x 840 px with a 290 px rail headed by the eyebrow and the title, its
## page buttons flat rows with an icon; at the table the compact sheet of today.
func _apply_menu_layout() -> void:
	var on := _modal
	var window := get_viewport().get_visible_rect().size
	_sheet.custom_minimum_size = Vector2(minf(SHEET_MENU_W, window.x - 128.0), minf(SHEET_MENU_H, window.y - 120.0)) if on \
			else Vector2(SHEET_W, 0)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL
	_scroll.custom_minimum_size.y = 0.0 if on else float(SCROLL_H)
	_rail.custom_minimum_size.x = PAGE_RAIL_MENU_W if on else PAGE_RAIL_W
	_rail_head.visible = on
	var well := StyleBoxFlat.new()   # the menu sets the rail off: a darker column, a 1 px rule at its right
	well.bg_color = HouseStyle.WELL if on else Color(0, 0, 0, 0)
	well.border_color = HouseStyle.LINE
	well.border_width_right = HouseStyle.BORDER if on else 0
	well.content_margin_right = HouseStyle.GAP_SECTION if on else 0.0
	_rail_column.add_theme_stylebox_override(&"panel", well)
	(_header.get_child(0) as Control).visible = not on
	var close := _header.get_node("CloseButton") as Control
	close.size_flags_horizontal = (Control.SIZE_SHRINK_END | Control.SIZE_EXPAND) if on else Control.SIZE_SHRINK_END
	_lab_sep.visible = on
	_footer_note.visible = on
	_footer_close.visible = on
	if on and not _graphics_rows:
		HouseStyle.sheet_close_box(close as Button)
		_build_graphics_rows()
		_build_switch_rows("Accessibility", ["Calm Mode", "Reduce Motion"])
		_build_audio_rows()
		_build_mixed_rows("Display")
		_build_mixed_rows("Gameplay")
	for page_name: String in PAGES:
		_style_page_button(_page_buttons[page_name] as Button, page_name)
	_sync_page_ticks()


## The Graphics page as rows, in the order of sheet 05: Quality, Tilt-Shift, Board Mist and Steam, Combat Effects, Miniature
## Idle Motion, Table frame. The controls move into their rows (a switch gives its name to the row and keeps it as meta
## "row_name"); no setting leaves the page. Built once, the first time the sheet is modal.
func _build_graphics_rows() -> void:
	_graphics_rows = true
	var page := _page("Graphics")
	var by_name := {}
	for n: Node in page.find_children("*", "CheckButton", true, false):
		by_name[(n as Button).text] = n
	var frame := page.find_child("TableFrameOption", true, false) as OptionButton
	var items: Array = ["Today's look", "Walnut", "Oak", "Ivory"]
	for i in frame.item_count:
		frame.set_item_text(i, items[i])
	frame.custom_minimum_size.x = ROW_FRAME_W
	_quality_row.add_theme_constant_override(&"separation", 0)   # one joined group of five
	_quality_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	for segment: Node in _quality_row.get_children():
		(segment as Control).custom_minimum_size.y = ROW_SEGMENT_H
	var first := page.get_child(0)
	if first is Label and (first as Label).text == "Quality":   # the row names it now
		_drop_help_line(first)
		page.remove_child(first)   # out of the tree at once: the deferred restyle must not hang a line under it
		first.queue_free()
	var eyebrow := HouseStyle.label("GRAPHICS", HouseStyle.EYEBROW)
	page.add_child(eyebrow)
	page.move_child(eyebrow, 0)
	var heading := HouseStyle.label("How the table looks", HouseStyle.BODY)   # sheet 05's page heading
	heading.name = "PageHeading"
	heading.add_theme_font_override(&"font", HouseStyle.font(500))
	heading.add_theme_font_size_override(&"font_size", HouseStyle.FONT_VALUE)
	page.add_child(heading)
	page.move_child(heading, 1)
	for row_name: String in ["Quality", "Tilt-Shift (Depth of Field)", "Board Mist and Steam", "Combat Effects",
			"Miniature Idle Motion", "Table frame"]:
		var control: Control = _quality_row if row_name == "Quality" else frame if row_name == "Table frame" \
				else by_name[row_name]
		var help_key := "TableFrameOption" if row_name == "Table frame" else row_name
		page.add_child(_as_row(control, row_name,
				str(HELP.get(help_key, ""))))


## The Audio page as rows: each volume is a row with the slider and its per cent (mono, gold) in the right column.
func _build_audio_rows() -> void:
	var page := _page("Audio")
	for n: Node in page.get_children():
		if n is Label and (n as Label).text == "AUDIO:":   # the page's name stands as an eyebrow now
			page.remove_child(n)
			n.queue_free()
	var eyebrow := HouseStyle.label("AUDIO", HouseStyle.EYEBROW)
	page.add_child(eyebrow)
	page.move_child(eyebrow, 0)
	for bus: String in volume_sliders:
		var slider := volume_sliders[bus] as HSlider
		var block := slider.get_parent()
		var head := block.get_child(0)
		var name_label := head.get_child(0) as Label
		var value_label := head.get_child(1) as Label
		_drop_help_line(name_label)
		head.remove_child(value_label)
		block.remove_child(slider)
		slider.custom_minimum_size.x = 300.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_label.custom_minimum_size.x = 62.0
		value_label.add_theme_font_override(&"font", HouseStyle.mono())
		value_label.add_theme_color_override(&"font_color", HouseStyle.GOLD)
		var control := HBoxContainer.new()
		control.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
		control.add_child(slider)
		control.add_child(value_label)
		page.remove_child(block)
		block.queue_free()
		page.add_child(_as_row(control, name_label.text, str(HELP.get(name_label.text, ""))))


## A page that holds only switches (Accessibility) as rows, in `names` order, under the page's name as an eyebrow.
func _build_switch_rows(page_name: String, names: Array) -> void:
	var page := _page(page_name)
	var by_name := {}
	for n: Node in page.find_children("*", "CheckButton", true, false):
		by_name[(n as Button).text] = n
	var eyebrow := HouseStyle.label(page_name.to_upper(), HouseStyle.EYEBROW)
	page.add_child(eyebrow)
	page.move_child(eyebrow, 0)
	for row_name: String in names:
		if by_name.has(row_name):
			page.add_child(_as_row(by_name[row_name], row_name, str(HELP.get(row_name, ""))))


## Display and Gameplay as rows, in the page's order under its name as an eyebrow: a switch is its own row; a "Name
## [dropdown]" line (Monitor, Gore) and a slider block (UI Scale, Stage beat) give their control to a row named after their
## label - a slider with its value (mono, gold) beside it. The old "DISPLAY:" heading goes.
func _build_mixed_rows(page_name: String) -> void:
	var page := _page(page_name)
	var rows: Array = []
	for n: Node in page.get_children():
		var control: Control = n as Control
		var row_name := ""
		if n is CheckButton:
			row_name = (n as Button).text
		elif n is BoxContainer:
			var labels: Array = n.find_children("*", "Label", true, false)
			var picks: Array = n.find_children("*", "OptionButton", true, false) + n.find_children("*", "HSlider", true, false)
			if labels.is_empty() or picks.is_empty():
				continue
			control = picks[0]
			row_name = (labels[0] as Label).text.get_slice(":", 0)   # "Stage beat: 2.0s" names its row "Stage beat"
			_drop_help_line(labels[0])
			if control is HSlider:
				control = _slider_with_value(control as HSlider, labels[-1] as Label)
			else:
				control.get_parent().remove_child(control)
				control.custom_minimum_size.x = ROW_FRAME_W
		else:
			continue   # the "DISPLAY:" heading and the old help lines go with the page's leftovers
		rows.append(_as_row(control, row_name, str(HELP.get(row_name, ""))))
	for n: Node in page.get_children():
		page.remove_child(n)
		n.queue_free()
	page.add_child(HouseStyle.label(page_name.to_upper(), HouseStyle.EYEBROW))
	for row: Control in rows:
		page.add_child(row)


## A slider and its value label side by side for a row's right column; the value in mono gold, without the name.
func _slider_with_value(slider: HSlider, value_label: Label) -> HBoxContainer:
	slider.get_parent().remove_child(slider)
	value_label.get_parent().remove_child(value_label)
	slider.custom_minimum_size.x = 300.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.custom_minimum_size.x = 62.0
	value_label.add_theme_font_override(&"font", HouseStyle.mono())
	value_label.add_theme_color_override(&"font_color", HouseStyle.GOLD)
	var strip := func(_v: float = 0.0) -> void: value_label.text = value_label.text.get_slice(": ", 1) \
			if value_label.text.contains(": ") else value_label.text
	strip.call()
	slider.value_changed.connect(strip)   # after the slider's own handler, which writes "Stage beat: 2.0s"
	var control := HBoxContainer.new()
	control.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
	control.add_child(slider)
	control.add_child(value_label)
	return control


## Takes away the help line that was hung under `control` (the row carries its own).
func _drop_help_line(control: Node) -> void:
	var old: Variant = control.get_meta("help_line", null)
	if old is Node and is_instance_valid(old):
		(old as Node).get_parent().remove_child(old)
		(old as Node).queue_free()


## One setting as a row: the name (19 px, weight 500) with its help line below at the left, the control at the right in a
## 470 px column, a hairline under the row. The control's own help line is the row's, so none is hung under it later.
func _as_row(control: Control, row_name: String, help: String) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.name = "Row" + row_name.replace(" ", "")
	wrapper.add_theme_constant_override(&"separation", 0)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_H
	row.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
	wrapper.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override(&"separation", 2)
	row.add_child(words)
	var name_label := HouseStyle.label(row_name, HouseStyle.BODY)
	name_label.add_theme_font_override(&"font", HouseStyle.font(500))
	name_label.add_theme_font_size_override(&"font_size", ROW_NAME_PX)
	name_label.set_meta("help_line", true)   # the row's own line is under it already
	words.add_child(name_label)
	if not help.is_empty():
		var line := HouseStyle.label(help, HouseStyle.CAPTION)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(line)
	var holder := HBoxContainer.new()
	holder.custom_minimum_size.x = ROW_CONTROL_W
	holder.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(holder)
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	if control is CheckButton:   # the row's name says what the switch is
		control.set_meta("row_name", (control as Button).text)
		(control as Button).text = ""
	_drop_help_line(control)
	control.set_meta("help_line", true)
	if control is OptionButton:
		control.custom_minimum_size.y = ROW_DROPDOWN_H
	control.size_flags_horizontal = Control.SIZE_FILL if control is HBoxContainer else Control.SIZE_SHRINK_END
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(control)
	var rule := ColorRect.new()
	rule.color = Color(HouseStyle.LINE, 0.6)
	rule.custom_minimum_size.y = 1
	wrapper.add_child(rule)
	return wrapper


## A page button as a segment (the table's sheet) or, in the menu, a flat 56 px row: icon, 19 px text, a soft fill
## under the pointer, the open page with its rim and a gold tick (the tick is its child, shown by _sync_page_ticks).
func _style_page_button(tab: Button, page_name: String) -> void:
	var states: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]
	var colours: Array[StringName] = [&"font_color", &"font_hover_color", &"font_pressed_color",
		&"font_hover_pressed_color", &"font_focus_color", &"icon_normal_color", &"icon_hover_color",
		&"icon_pressed_color", &"icon_hover_pressed_color", &"icon_focus_color"]
	var tick := tab.get_node_or_null("Tick") as Control
	if not _modal:
		tab.theme_type_variation = HouseStyle.SEGMENT
		tab.custom_minimum_size.y = HouseStyle.H_ACTION
		tab.icon = null
		for state: StringName in states:
			tab.remove_theme_stylebox_override(state)
		for colour: StringName in colours:
			tab.remove_theme_color_override(colour)
		tab.remove_theme_font_override(&"font")
		tab.remove_theme_font_size_override(&"font_size")
		if tick != null:
			tick.visible = false
		return
	tab.theme_type_variation = HouseStyle.BUTTON
	tab.custom_minimum_size.y = HouseStyle.H_PAGE_ROW
	tab.icon = _page_icon(page_name)
	tab.expand_icon = true
	tab.add_theme_constant_override(&"icon_max_width", HouseStyle.ICON_PAGE_ROW)
	tab.add_theme_constant_override(&"h_separation", 14)
	tab.add_theme_font_override(&"font", HouseStyle.font(500))
	tab.add_theme_font_size_override(&"font_size", HouseStyle.FONT_PAGE_ROW)
	var clear := Color(0, 0, 0, 0)
	var boxes := {&"normal": _page_box(clear, clear), &"hover": _page_box(HouseStyle.ROW_HOVER, clear),
		&"pressed": _page_box(HouseStyle.ROW_HOVER, HouseStyle.LINE_SOFT),
		&"hover_pressed": _page_box(HouseStyle.ROW_HOVER, HouseStyle.LINE_SOFT), &"focus": _page_box(clear, HouseStyle.ACCENT)}
	for state: StringName in states:
		tab.add_theme_stylebox_override(state, boxes[state] as StyleBox)
	for colour: StringName in colours:
		var ink := HouseStyle.MUTED if colour.ends_with("normal_color") or colour == &"font_color" else HouseStyle.INK
		tab.add_theme_color_override(colour, ink)
	if tick == null:
		var mark := ColorRect.new()
		mark.name = "Tick"
		mark.color = HouseStyle.GOLD
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		mark.offset_right = 3.0
		mark.offset_top = 10.0
		mark.offset_bottom = -10.0
		tab.add_child(mark)


func _page_box(fill: Color, rim: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = rim
	box.set_border_width_all(1 if rim.a > 0.0 else 0)
	box.set_corner_radius_all(HouseStyle.RADIUS_CARD)
	box.content_margin_left = 16
	box.content_margin_right = 12
	return box


func _page_icon(page_name: String) -> Texture2D:
	if not _page_icons.has(page_name):
		_page_icons[page_name] = HouseStyle.svg_icon(PAGE_ICON_SVG % PAGE_ICONS[page_name])
	return _page_icons[page_name]


## The gold tick stands at the open page's button, in the menu only.
func _sync_page_ticks() -> void:
	for page_name: String in _page_buttons:
		var tick := (_page_buttons[page_name] as Button).get_node_or_null("Tick") as Control
		if tick != null:
			tick.visible = _modal and page_name == _page_shown


## The content box of the page `page_name` (one of PAGES): the place a control is added to.
func _page(page_name: String) -> VBoxContainer:
	return _pages[page_name] as VBoxContainer


## Shows the page `page_name` and marks its rail button; the other pages are hidden.
func show_page(page_name: String) -> void:
	for n: String in _pages:
		(_pages[n] as Control).visible = n == page_name
		(_page_buttons[n] as Button).set_pressed_no_signal(n == page_name)
	_page_shown = page_name
	_sync_page_ticks()
	if _reset_button != null:
		_reset_button.visible = page_name in RESETTABLE


## "Reset this page": a prompt card first, then reset_page.
func _ask_reset(page_name: String) -> void:
	var card := PromptCard.new("Reset %s?" % page_name, "Puts the settings of this page back to how the game ships.", "Reset", "Cancel")
	card.menu_scale = _modal
	add_child(card)
	if await card.answer():
		reset_page(page_name)


## Every switch, slider and dropdown of `page_name` that stands for a GraphicsSettings field goes back to the value a
## fresh GraphicsSettings starts with - through the control itself, so its own handler applies and saves it.
func reset_page(page_name: String) -> void:
	var fresh: Object = (GraphicsSettings.get_script() as Script).new()
	if page_name == "Graphics" and GraphicsSettings.current_preset != fresh.get("current_preset"):
		GraphicsSettings.apply_preset(fresh.get("current_preset"))   # first: a preset also sets Idle Motion
	for n: Node in _page(page_name).find_children("*", "Control", true, false):
		var switch_name := str(n.get_meta("row_name", (n as Button).text)) if n is CheckButton else ""   # a row took the text
		var field := str(SWITCH_FIELDS.get(switch_name, "")) if n is CheckButton else str(n.get_meta("setting", ""))
		if field.is_empty():
			continue
		var value: Variant = fresh.get(field)
		if n is CheckButton:
			(n as CheckButton).button_pressed = value   # toggled fires only on a change, as with a click
		elif n is Range:
			(n as Range).value = value
		elif n is OptionButton and (n as OptionButton).selected != int(value):
			(n as OptionButton).select(value)
			(n as OptionButton).item_selected.emit(value)
	fresh.free()


## Calm mode changed (from this panel or elsewhere): reflect the toggle and the
## individual switches it forces, WITHOUT re-emitting (set_pressed_no_signal), so the
## panel never shows a stale state and the handlers do not bounce.
func _on_calm_changed() -> void:
	if _calm_cb != null and is_instance_valid(_calm_cb):
		_calm_cb.set_pressed_no_signal(GraphicsSettings.calm_mode)
	for field: String in _switch_toggles:
		var cb := _switch_toggles[field] as CheckButton
		if cb != null and is_instance_valid(cb):
			cb.set_pressed_no_signal(bool(GraphicsSettings.get(field)))


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
	slider.scrollable = false  # the wheel scrolls the list, it never sets a value
	slider.min_value = GraphicsSettings.UI_SCALE_MIN
	slider.max_value = GraphicsSettings.UI_SCALE_MAX
	slider.step = 0.05
	slider.value = GraphicsSettings.ui_scale
	slider.set_meta("setting", "ui_scale")
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
	slider.scrollable = false  # the wheel scrolls the list, it never sets a value
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
	slider.scrollable = false  # the wheel scrolls the list, it never sets a value
	slider.min_value = -40.0
	slider.max_value = 6.0
	slider.step = 1.0
	slider.value = AudioManager.get_bus_volume(bus_name)
	_show_volume(slider, value_label)
	slider.value_changed.connect(_on_volume_slider_changed.bind(bus_name, value_label))
	container.add_child(slider)

	volume_sliders[bus_name] = slider


func _on_volume_slider_changed(value: float, bus_name: String, value_label: Label) -> void:
	_show_volume(volume_sliders[bus_name], value_label)
	AudioManager.set_bus_volume(bus_name, value)


## A volume reads 0-100 % of its slider's travel; the stored value and the bus stay in dB, shown in the tooltip.
func _show_volume(slider: HSlider, value_label: Label) -> void:
	value_label.text = "%d %%" % roundi(slider.ratio * 100.0)
	value_label.tooltip_text = "%d dB" % int(slider.value)
	value_label.mouse_filter = Control.MOUSE_FILTER_PASS   # a label shows its tooltip only when it takes the mouse


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
	_add_help_lines()
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


## Puts each HELP line under its setting, once (late additions such as the menu background included): a switch or a
## dropdown gets it right below; a name in a row gets it below the row (Gore) or below its slider (the volumes).
func _add_help_lines() -> void:
	for n: Node in find_children("*", "Control", true, false):
		var key := String(n.name)
		if not HELP.has(key) and (n is Label or n is Button):
			key = str(n.get("text"))
		if not HELP.has(key) or n.has_meta("help_line") or n is ColorPickerButton:
			continue
		var anchor := n as Control
		if n is Label and n.get_parent() is HBoxContainer:   # a name in a row: the line goes under the row,
			anchor = n.get_parent()   # and under the whole block when the row heads a slider block
			if not anchor.get_parent() in _pages.values():
				anchor = anchor.get_parent()
		var line := HouseStyle.label(HELP[key], HouseStyle.CAPTION)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		anchor.add_sibling(line)
		n.set_meta("help_line", line)


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
