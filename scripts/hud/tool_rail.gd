class_name ToolRail
extends Control
## Right-side tool rail for the in-game HUD (UI handoff 22.09.).
##
## Groups the four table tools — Dice, Measure, Terrain, View — into one collapsible rail
## instead of scattering them across the field. The Dice tool reuses the existing
## DiceRollerPanel (moved out of the bottom-right corner to the rail slot); Measure and View
## are shortcut references, Terrain routes to the existing map-layout / terrain-mode /
## clear / sort actions.
##
## DISPLAY ONLY. It reads and routes to functions that already exist on Main; it adds no rule,
## simulation or new game function. No tool logic is duplicated.
##
## Click ownership (see test/ui_click_ownership_test.gd): this root stays IGNORE; the rail
## buttons and the tool panel are STOP surfaces that own their pixels.

const HudTokensScript := preload("res://scripts/hud/hud_tokens.gd")

# The right-hand slot the tools occupy; the rail buttons sit just right of it.
const SLOT_LEFT := -396.0
const SLOT_RIGHT := -64.0
const SLOT_TOP := 60.0
const SLOT_BOTTOM := -70.0

var _main: Node = null
var _dice: Control = null
var _rail: VBoxContainer = null
var _host: PanelContainer = null
var _content: VBoxContainer = null
var _buttons: Dictionary = {}
var _panels: Dictionary = {}
var _active := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Wire the rail to the live game. `main` is the Main node; the rail reads its HUD nodes and
## calls its existing handlers.
func setup(main: Node) -> void:
	_main = main
	_dice = main.get_node_or_null("UI/HUD/DiceRollerPanel") as Control
	if _dice != null:
		_place_dice()
	_build_rail()
	_build_host()
	_select("dice")


# === Layout ===

## Move the dice panel from the bottom-right corner into the rail slot (top-right, stretched).
## Its widgets and 3D dice tray are untouched — only its rect changes.
func _place_dice() -> void:
	_apply_slot(_dice)
	_dice.visible = false


func _apply_slot(node: Control) -> void:
	node.anchor_left = 1.0
	node.anchor_right = 1.0
	node.anchor_top = 0.0
	node.anchor_bottom = 1.0
	node.offset_left = SLOT_LEFT
	node.offset_right = SLOT_RIGHT
	node.offset_top = SLOT_TOP
	node.offset_bottom = SLOT_BOTTOM
	node.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	node.grow_vertical = Control.GROW_DIRECTION_BOTH


func _build_rail() -> void:
	_rail = VBoxContainer.new()
	_rail.name = "ToolRail"
	_rail.add_theme_constant_override("separation", HudTokensScript.SPACE_8)
	_rail.anchor_left = 1.0
	_rail.anchor_right = 1.0
	_rail.anchor_top = 0.5
	_rail.anchor_bottom = 0.5
	_rail.offset_left = -60.0
	_rail.offset_right = -12.0
	_rail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_rail.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_rail)

	for tool in [["dice", "Dice"], ["measure", "Measure"], ["terrain", "Terrain"], ["view", "View"]]:
		var b := Button.new()
		b.name = "Tool_" + str(tool[0])
		b.text = str(tool[1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(48, 48)
		b.add_theme_font_override("font", HudTokensScript.body_font())
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_tool_pressed.bind(str(tool[0])))
		_rail.add_child(b)
		_buttons[tool[0]] = b
		_style(b, false)


func _build_host() -> void:
	_host = PanelContainer.new()
	_host.name = "ToolPanelHost"
	_host.add_theme_stylebox_override("panel", HudTokensScript.panel_style())
	_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_slot(_host)
	_host.visible = false
	add_child(_host)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", HudTokensScript.SPACE_16)
	margin.add_theme_constant_override("margin_right", HudTokensScript.SPACE_16)
	margin.add_theme_constant_override("margin_top", HudTokensScript.SPACE_12)
	margin.add_theme_constant_override("margin_bottom", HudTokensScript.SPACE_12)
	_host.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", HudTokensScript.SPACE_12)
	margin.add_child(_content)

	_panels["measure"] = _build_measure()
	_panels["terrain"] = _build_terrain()
	_panels["view"] = _build_view()
	for key in _panels:
		(_panels[key] as Control).visible = false


# === Tool panels ===

func _build_measure() -> Control:
	var v := VBoxContainer.new()
	v.name = "ToolMeasure"
	v.add_theme_constant_override("separation", HudTokensScript.SPACE_8)
	v.add_child(HudTokensScript.header("MEASURE"))
	v.add_child(_info_line("Ruler", ["Shift", "Click"]))
	v.add_child(_info_line("Pin ruler", ["P"]))
	v.add_child(_info_line("Clear rulers", ["K", "Shift+K"]))
	v.add_child(_info_line("Move bands", ["M", "Shift+M"]))
	_content.add_child(v)
	return v


func _build_view() -> Control:
	var v := VBoxContainer.new()
	v.name = "ToolView"
	v.add_theme_constant_override("separation", HudTokensScript.SPACE_8)
	v.add_child(HudTokensScript.header("VIEW"))
	v.add_child(_info_line("Range ring", ["G", "Shift+G"]))
	v.add_child(_info_line("Sight / range fan", ["F", "Shift+F"]))
	v.add_child(_info_line("Move trails", ["T", "Shift+T"]))
	v.add_child(_info_line("Rotate to cursor", ["R", "Shift+R"]))
	_content.add_child(v)
	return v


func _build_terrain() -> Control:
	var v := VBoxContainer.new()
	v.name = "ToolTerrain"
	v.add_theme_constant_override("separation", HudTokensScript.SPACE_8)
	v.add_child(HudTokensScript.header("TERRAIN"))
	v.add_child(_action_line("Map layout…", func() -> void: _call("_on_map_layout_pressed")))
	v.add_child(_action_line("Terrain mode", _toggle_terrain_mode))
	v.add_child(_action_line("Clear table", func() -> void: _call("_on_clear_all")))
	v.add_child(_action_line("Sort table", func() -> void: _call("_on_sort_table")))
	var note := Label.new()
	note.text = "Terrain is placed freely; the biome only sets the look."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_override("font", HudTokensScript.body_font())
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", HudTokensScript.TEXT_MUTED)
	v.add_child(note)
	_content.add_child(v)
	return v


## A row of shortcut reference: the action name on the left, key hints on the right.
func _info_line(name: String, keys: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HudTokensScript.SPACE_8)
	var label := Label.new()
	label.text = name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", HudTokensScript.body_font())
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", HudTokensScript.TEXT)
	row.add_child(label)
	for key in keys:
		row.add_child(_key_cap(str(key)))
	return row


func _key_cap(text: String) -> Control:
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", HudTokensScript.sunken_style())
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HudTokensScript.mono_font())
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", HudTokensScript.TEXT_MUTED)
	cap.add_child(l)
	return cap


## A clickable row that routes to an existing Main action (or a small local toggle).
func _action_line(name: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = name
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HudTokensScript.body_font())
	b.add_theme_font_size_override("font_size", 12)
	var ghost := HudTokensScript.ghost_button()
	for state in ghost:
		b.add_theme_stylebox_override(state, ghost[state])
	b.pressed.connect(on_press)
	return b


# === State ===

func _on_tool_pressed(tool: String) -> void:
	_select(tool)


func _select(tool: String) -> void:
	_active = tool
	for key in _buttons:
		_style(_buttons[key], key == tool)
	if tool == "dice":
		_host.visible = false
		if _dice != null:
			_dice.visible = true
		return
	if _dice != null:
		_dice.visible = false
	_host.visible = true
	for key in _panels:
		(_panels[key] as Control).visible = (key == tool)


func _style(button: Button, active: bool) -> void:
	var boxes := HudTokensScript.primary_button() if active else HudTokensScript.ghost_button()
	for state in boxes:
		button.add_theme_stylebox_override(state, boxes[state])
	button.add_theme_color_override("font_color", HudTokensScript.TEXT if active else HudTokensScript.TEXT_MUTED)


# === Routing to existing Main functions ===

func _call(method: String) -> void:
	if _main != null and _main.has_method(method):
		_main.call(method)


func _toggle_terrain_mode() -> void:
	var btn = _main.get("_terrain_mode_btn") if _main != null else null
	if btn != null:
		btn.button_pressed = not bool(btn.button_pressed)