class_name CommandBar
extends Control
## Top command bar for the in-game HUD (UI handoff 22.09.).
##
## A slim bar across the top that finally gives the round, the phase and whose turn it is a
## permanent home, plus one clear button for the turn action. It also owns the controls help
## overlay that replaces the old always-on controls wall (UI/HUD/InfoLabel).
##
## DISPLAY ONLY. The bar reads existing state (opr_army_manager round/phase, the solo turn
## manager's active side) and routes its turn button to main's existing _on_next_round(). It
## changes no rule or simulation behaviour.
##
## Click ownership (see test/ui_click_ownership_test.gd): this root is a transparent full-rect
## holder and stays IGNORE; the bar and the help overlay are STOP surfaces that own their pixels.

const HudTokensScript := preload("res://scripts/hud/hud_tokens.gd")

var _main: Node = null
var _bar: PanelContainer = null
var _round: Label = null
var _phase: Label = null
var _turn: Label = null
var _turn_action: Button = null
var _help: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Wire the bar to the live game. `main` is the Main node: the bar reads its managers and calls
## its existing turn action.
func setup(main: Node) -> void:
	_main = main
	_build_bar()
	_build_help()
	var info := main.get_node_or_null("UI/HUD/InfoLabel") as Label
	if info != null:
		info.visible = false   # the controls list now lives behind the ? Controls button
	refresh()


# === Bar ===

func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.name = "CommandBar"
	_bar.add_theme_stylebox_override("panel", HudTokensScript.panel_style())
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP   # paints a background: owns every pixel
	_bar.anchor_right = 1.0
	_bar.offset_left = 66.0     # clear of the hamburger button
	_bar.offset_right = -16.0
	_bar.offset_top = 8.0
	_bar.offset_bottom = 52.0
	add_child(_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_bar.add_child(row)

	_round = _label("ROUND 1", HudTokensScript.AMBER, HudTokensScript.head_font(), 15)
	row.add_child(_round)
	_phase = _label("DEPLOYMENT", HudTokensScript.TEXT_MUTED, HudTokensScript.body_font(), 12)
	row.add_child(_phase)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_turn = _label("HOTSEAT", HudTokensScript.CYAN, HudTokensScript.body_font(), 13)
	row.add_child(_turn)

	var help_btn := Button.new()
	help_btn.name = "ControlsHelpBtn"
	help_btn.text = "? Controls"
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.tooltip_text = "Show the keyboard and mouse controls"
	help_btn.pressed.connect(toggle_help)
	row.add_child(help_btn)

	_turn_action = Button.new()
	_turn_action.name = "TurnActionBtn"
	_turn_action.text = "Next Round"
	_turn_action.focus_mode = Control.FOCUS_NONE
	_turn_action.tooltip_text = "Advance the round — all activation tokens are cleared."
	_turn_action.pressed.connect(_on_turn_action)
	row.add_child(_turn_action)


func _label(text: String, color: Color, font: Font, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _on_turn_action() -> void:
	if _main != null and _main.has_method("_on_next_round"):
		_main._on_next_round()


# === Help overlay ===

func _build_help() -> void:
	_help = Control.new()
	_help.name = "HelpOverlay"
	_help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_STOP
	_help.visible = false
	add_child(_help)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTokensScript.panel_style())
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("CONTROLS", HudTokensScript.TEXT, HudTokensScript.head_font(), 18)
	head.add_child(title)
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_spacer)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_help)
	head.add_child(close)

	var info := _main.get_node_or_null("UI/HUD/InfoLabel") as Label
	var body := Label.new()
	body.text = info.text if info != null else ""
	body.add_theme_font_override("font", HudTokensScript.body_font())
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", HudTokensScript.TEXT)
	v.add_child(body)

	_help.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_help.visible = false)


func toggle_help() -> void:
	if _help != null:
		_help.visible = not _help.visible


# === State (display only) ===

## Read the current round / phase / turn into the bar. Safe to call any time.
func refresh() -> void:
	if _bar == null or _main == null:
		return
	var manager = _main.get("opr_army_manager")
	var round_n := 1
	var phase: int = OPRArmyManager.GamePhase.DEPLOYMENT
	if manager != null:
		round_n = int(manager.current_round)
		phase = int(manager.game_phase)
	_round.text = "ROUND %d" % round_n
	_phase.text = "DEPLOYMENT" if phase == OPRArmyManager.GamePhase.DEPLOYMENT else "PLAYING"
	_turn.text = _turn_text()
	_turn.add_theme_color_override("font_color", _turn_color())
	if _turn_action != null:
		var final_round: bool = bool(_main.call("_solo_final_round_active"))
		_turn_action.text = _main.next_round_button_label(round_n, final_round)
	# Lazy hook: the solo turn manager is created with the controller, which can happen after the
	# bar is built. Connect once so every side change refreshes the indicator.
	var solo = _main.get("solo_controller")
	if solo != null and solo.turn_manager != null \
			and not solo.turn_manager.turn_changed.is_connected(_on_turn_changed):
		solo.turn_manager.turn_changed.connect(_on_turn_changed)


func _turn_text() -> String:
	var solo = _main.get("solo_controller")
	if solo != null and solo.turn_manager != null:
		return "YOUR TURN" if solo.turn_manager.active_side() == TurnManager.Side.HUMAN else "NACHTMAHR'S TURN"
	var net = _main.get("network_manager")
	if net != null and net.is_multiplayer_active():
		return "MULTIPLAYER"
	return "HOTSEAT"


func _turn_color() -> Color:
	var solo = _main.get("solo_controller")
	if solo != null and solo.turn_manager != null \
			and solo.turn_manager.active_side() != TurnManager.Side.HUMAN:
		return Color(0.85, 0.45, 0.35)
	return HudTokensScript.CYAN


func _on_turn_changed(_side: int) -> void:
	refresh()
