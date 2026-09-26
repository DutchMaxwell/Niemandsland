class_name ToolRail
extends Control
## The tool rail (house style, maintainer 23.09.: "Werkzeugleiste"): Dice, Measure, Terrain and View
## in one slim column at the right edge, one tool open at a time (the open one in gold). "? Controls"
## moved to the top bar (maintainer 23.09.: "Obere Leiste").
##
## - Dice is the existing dice window, docked beside the rail — same node, same functions.
## - Measure and View show every table key with its caps. A clickable cap PRESSES that key (the same
##   InputEventKey the keyboard sends), so each function behaves exactly as on the keyboard, incl. its
##   selection and multiplayer rules. Gestures (Shift+drag, hold R, right-click) are hints, never fake
##   buttons.
## - Terrain routes to Main's existing handlers and mirrors the menu's switches.
## Display only: no rule, simulation or network change. This root is full-screen but IGNORE; only the
## rail and the open panel own their pixels.

signal tool_changed(tool: StringName)   # &"" = every tool closed

const TOOLS: Array[StringName] = [&"dice", &"measure", &"terrain", &"view"]
const MARGIN := 10      # from the screen edge (the dice window sat 10 px from it before)
const TOP := 60         # below the menu-button row, level with the game menu
const PANEL_W := 340    # measure / terrain / view (the dice window keeps its own 420)

const ICONS := {
	&"dice": "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 48 48'><rect x='7' y='7' width='34' height='34' rx='8' fill='none' stroke='#fff' stroke-width='3.5'/><g fill='#fff'><circle cx='16.5' cy='16.5' r='3.3'/><circle cx='31.5' cy='16.5' r='3.3'/><circle cx='24' cy='24' r='3.3'/><circle cx='16.5' cy='31.5' r='3.3'/><circle cx='31.5' cy='31.5' r='3.3'/></g></svg>",
	&"measure": "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 48 48'><path d='M6 24H42M6 24l8-8M6 24l8 8M42 24l-8-8M42 24l-8 8' fill='none' stroke='#fff' stroke-width='3.5' stroke-linecap='round' stroke-linejoin='round'/></svg>",
	&"terrain": "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 48 48'><path d='M4 40L18 14l9 15 5-7 12 18Z' fill='none' stroke='#fff' stroke-width='3.5' stroke-linejoin='round'/><path d='M13 23.5l5-9.5 5 8.3-3-1.8-3.5 3Z' fill='#fff'/></svg>",
	&"view": "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 48 48'><circle cx='24' cy='24' r='15' fill='none' stroke='#fff' stroke-width='3.5'/><circle cx='24' cy='24' r='6' fill='#fff'/></svg>",
}
const TITLES := {&"dice": "Dice", &"measure": "Measure", &"terrain": "Terrain", &"view": "View"}

var _main: Node = null
var _rail: PanelContainer = null
var _buttons: Dictionary = {}    # tool -> rail Button
var _panels: Dictionary = {}     # tool -> Control
var _active: StringName = &""
var _switches: Array = []        # [Button, Callable -> the source CheckBox/Button or null]


## Wires the rail into the HUD: builds it, docks the dice window beside it, builds the other panels.
func setup(main: Node, dice_panel: Control) -> void:
	_main = main
	name = "ToolRail"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_rail()
	_panels[&"dice"] = dice_panel
	_dock(dice_panel, dice_panel.offset_right - dice_panel.offset_left, dice_panel.offset_bottom - dice_panel.offset_top)
	_panels[&"measure"] = _build_measure()
	_panels[&"terrain"] = _build_terrain()
	_panels[&"view"] = _build_view()
	for t: StringName in TOOLS:
		(_panels[t] as Control).visible = false


# === State ===

func active_tool() -> StringName:
	return _active


func button(tool: StringName) -> Button:
	return _buttons.get(tool)


func panel(tool: StringName) -> Control:
	return _panels.get(tool)


## A rail click: open that tool, or close it when it is the open one.
func select(tool: StringName) -> void:
	set_open(tool, _active != tool)


## Opens `tool` (closing any other) or closes it. Emits tool_changed when the open tool changes.
func set_open(tool: StringName, open: bool) -> void:
	var next: StringName = tool if open else (&"" if _active == tool else _active)
	var changed := next != _active
	_active = next
	for t: StringName in TOOLS:
		(_panels[t] as Control).visible = t == _active
		HouseStyle.set_selected(_buttons[t], t == _active)
	if _active == &"terrain":
		_refresh_switches()
	if changed:
		tool_changed.emit(_active)


# === Layout ===

func _rail_width() -> float:
	return HouseStyle.W_RAIL + HouseStyle.PAD_RAIL * 2


## Places a panel left of the rail, top-aligned with it (mockup .tool-panel).
func _dock(p: Control, width: float, height: float) -> void:
	var right := -(MARGIN + _rail_width() + HouseStyle.GAP_SECTION)
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_top = 0.0
	p.anchor_bottom = 0.0
	p.offset_right = right
	p.offset_left = right - width
	p.offset_top = TOP
	p.offset_bottom = TOP + height
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_END


func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.name = "Rail"
	_rail.theme = HouseStyle.theme()
	_rail.theme_type_variation = HouseStyle.RAIL_PANEL
	_rail.mouse_filter = Control.MOUSE_FILTER_STOP
	_rail.anchor_left = 1.0
	_rail.anchor_right = 1.0
	_rail.offset_right = -MARGIN
	_rail.offset_left = -MARGIN - _rail_width()
	_rail.offset_top = TOP
	_rail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_rail)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW)
	_rail.add_child(col)
	for t: StringName in TOOLS:
		var b := HouseStyle.rail_button(TITLES[t], HouseStyle.svg_icon(ICONS[t]))
		b.name = "Tool_" + String(t)
		b.tooltip_text = TITLES[t]
		b.pressed.connect(select.bind(t))
		col.add_child(b)
		_buttons[t] = b


## A house-style panel for one tool, docked and closable back into the rail.
func _panel(tool: StringName) -> VBoxContainer:
	var p := PanelContainer.new()
	p.name = "Tool" + TITLES[tool] + "Panel"
	HouseStyle.apply(p)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	_dock(p, PANEL_W, 0.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW)
	p.add_child(v)
	var header := HouseStyle.panel_header(TITLES[tool], true)
	(header.get_node("CloseButton") as Button).pressed.connect(set_open.bind(tool, false))
	v.add_child(header)
	return v


# === Measure / View: keys you can click ===

## A clickable key cap that presses `keycode` (with Shift) exactly as the keyboard does.
func _key(text: String, keycode: Key, shift: bool, tooltip: String) -> Button:
	var b := HouseStyle.key_button(text, tooltip)
	b.name = "Key_" + text.replace("+", "_")
	b.pressed.connect(press_key.bind(keycode, shift))
	return b


## Sends the key the way the keyboard does (press + release, after this click is done), so the
## object manager's and Main's own key handlers run — nothing is re-implemented here.
func press_key(keycode: Key, shift: bool) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.shift_pressed = shift
		ev.pressed = pressed
		get_viewport().push_input.call_deferred(ev)


func _line(v: VBoxContainer, text: String, keys: Array) -> PanelContainer:
	var line := HouseStyle.tool_line(text, keys)
	line.name = "Line_" + text.replace(" ", "_").replace("/", "_")
	v.add_child(line)
	return line


func _build_measure() -> Control:
	var v := _panel(&"measure")
	_line(v, "Ruler", [HouseStyle.key_cap("Shift"), HouseStyle.key_cap("drag")])
	_line(v, "Pin ruler (while measuring)", [HouseStyle.key_cap("P")])
	_line(v, "Remove one ruler", [HouseStyle.key_cap("Right-click it")])
	_line(v, "Clear rulers", [
		_key("K", KEY_K, false, "K — clear my rulers"),
		_key("Shift+K", KEY_K, true, "Shift+K — clear all rulers (host: everyone's)")])
	_line(v, "Move bands", [
		_key("M", KEY_M, false, "M — Advance / Rush bands of the selected unit (on / off)"),
		_key("Shift+M", KEY_M, true, "Shift+M — clear all move bands")])
	return v.get_parent()


func _build_view() -> Control:
	var v := _panel(&"view")
	_line(v, "Range ring", [
		_key("G", KEY_G, false, "G — range ring of the selected unit: 3, 6, 9, 12, 18, 24\", off"),
		_key("Shift+G", KEY_G, true, "Shift+G — clear all range rings")])
	_line(v, "Sight / range fan", [
		_key("F", KEY_F, false, "F — sight and range fan of the selected unit (nothing selected: regiment arcs)"),
		_key("Shift+F", KEY_F, true, "Shift+F — clear the sight and range fan")])
	_line(v, "Regiment frontage", [
		_key("B", KEY_B, false, "B — cycle the frontage of the selected regiment")])
	_line(v, "Move trails", [
		_key("T", KEY_T, false, "T — show / hide the move trails"),
		_key("Shift+T", KEY_T, true, "Shift+T — clear the move trails")])
	_line(v, "Rotate to cursor", [HouseStyle.key_cap("R"), HouseStyle.key_cap("hold")])
	_line(v, "Rotate group", [HouseStyle.key_cap("Shift"), HouseStyle.key_cap("R"), HouseStyle.key_cap("hold")])
	return v.get_parent()


# === Terrain: Main's own handlers ===

func _build_terrain() -> Control:
	var v := _panel(&"terrain")
	_action(v, "Map layout…", HouseStyle.GLYPH_GO, func() -> void: _main.call(&"_on_map_layout_pressed"))
	_switch(v, "Terrain mode", func() -> Variant: return _main.get(&"_terrain_mode_btn"))
	_action(v, "Clear table…", "", func() -> void: _main.call(&"_on_clear_all"))
	_action(v, "Sort table…", "", func() -> void: _main.call(&"_on_sort_table"))
	_switch(v, "Show deployment zones", func() -> Variant: return _main.get(&"deployment_zone_check"))
	_switch(v, "Flip zone colours", func() -> Variant: return _main.get(&"deployment_flip_check"))
	_line(v, "Lock / unlock a piece", [HouseStyle.key_cap("L")])
	var note := HouseStyle.label("Terrain is placed freely; the biome only sets the look.", HouseStyle.CAPTION)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v.get_parent()


func _action(v: VBoxContainer, text: String, trailing: String, run: Callable) -> Button:
	var b := HouseStyle.action_line(text, trailing)
	b.name = "Action_" + text.replace(" ", "_").replace("…", "")
	b.pressed.connect(run)
	v.add_child(b)
	return b


## A switch line that flips the menu's own toggle (so its handler runs and both stay in step).
func _switch(v: VBoxContainer, text: String, source: Callable) -> Button:
	var b := _action(v, text, "Off", func() -> void: _flip(source))
	_switches.append([b, source])
	return b


func _flip(source: Callable) -> void:
	var toggle := source.call() as BaseButton
	if toggle != null:
		toggle.button_pressed = not toggle.button_pressed
	_refresh_switches()


func _refresh_switches() -> void:
	for s: Array in _switches:
		var toggle := (s[1] as Callable).call() as BaseButton
		var on := toggle != null and toggle.button_pressed
		HouseStyle.set_selected(s[0] as Button, on)
		(s[0] as Button).disabled = toggle == null
		var state := (s[0] as Button).get_node("Trailing") as Label   # the switch's own state word
		state.text = "On" if on else "Off"
		state.theme_type_variation = HouseStyle.HIT if on else HouseStyle.CAPTION
