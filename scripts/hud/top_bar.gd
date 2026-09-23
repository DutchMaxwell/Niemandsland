class_name TopBar
extends Control
## The top bar (house style, maintainer 23.09.: "? Controls" belongs in the "Obere Leiste"): the game's
## state and its top-of-screen actions in one row (mockup m_topbar.png) — the ☰ menu button and the
## round / phase-or-turn chips left, the FPS line in the middle, Battle Log, "? Controls" and Next
## Round right.
##
## - Every item keeps today's function: ☰ is the same menu button (restyled, same handler); Battle Log
##   opens the same BattleLogPanel, below the bar at top-centre; "? Controls" opens the key list that
##   stood on the table (it moved here from the tool rail); Next Round mirrors the menu's NextRoundBtn
##   (its text, its state, its _on_next_round).
## - No strip behind the items: each carries its own dark fill, so the table shows between them and the
##   bar covers no more of it than the log tab + FPS line + menu button it replaced.
## - Display only: reads the round, the phase and whose turn it is; changes no rule, simulation or
##   network state. Round, phase and turn were shown nowhere on screen before.

enum Turn { NONE, YOURS, OPPONENT }   # NONE = hotseat / multiplayer: nobody tracks turns there

const MARGIN := 10   # from the screen edge, like the menu button

var _main: Node = null
var _round: PanelContainer = null
var _state: PanelContainer = null
var _log: Button = null
var _controls: Button = null
var _next: Button = null
var _overlay: ControlsOverlay = null
var _shown := ""   # the state last drawn; redraw only on a change


## Builds the bar on the HUD, restyles the menu button, takes over the battle log's placement and
## builds the controls overlay (on `overlay_parent`, above the HUD) from the hidden key list.
func setup(main: Node, overlay_parent: Node) -> void:
	_main = main
	name = "TopBar"
	theme = HouseStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var menu := main.get(&"hamburger_button") as Button
	HouseStyle.borrow_look(menu, HouseStyle.BAR_BUTTON)
	menu.custom_minimum_size = Vector2(HouseStyle.H_BAR, HouseStyle.H_BAR)

	var left := _row(false)
	left.offset_left = MARGIN + HouseStyle.H_BAR + HouseStyle.GAP_ROW
	_round = HouseStyle.chip("ROUND 1", HouseStyle.CHIP_ROUND)
	_round.name = "Round"
	left.add_child(_round)
	_state = HouseStyle.chip("DEPLOYMENT", HouseStyle.CHIP)
	_state.name = "State"
	left.add_child(_state)

	var right := _row(true)
	_log = _button("Battle Log", HouseStyle.BAR_BUTTON, "Battle Log — every roll, move and rule of this game")
	right.add_child(_log)
	_controls = _button("? Controls", HouseStyle.BAR_BUTTON, "Keys and mouse controls")
	right.add_child(_controls)
	_next = _button("Next Round", HouseStyle.BAR_PRIMARY, "Advance the round — all activation tokens are cleared")
	right.add_child(_next)

	var log_panel := main.get(&"battle_log_panel") as BattleLogPanel
	log_panel.offset_top = HouseStyle.BAR_TOP + HouseStyle.H_BAR + HouseStyle.GAP_SECTION
	log_panel.offset_bottom = log_panel.offset_top
	log_panel.visible = log_panel.is_open()   # the tab is gone: the panel shows while it is open
	log_panel.open_changed.connect(_on_log_open_changed)
	_log.pressed.connect(func() -> void: log_panel.set_open(not log_panel.is_open()))

	var key_list := main.get_node("UI/HUD/InfoLabel") as Label
	key_list.visible = false   # the always-on wall stays gone; "? Controls" shows the same list
	_overlay = ControlsOverlay.new()
	_overlay.build(overlay_parent, key_list)
	_controls.pressed.connect(func() -> void: _overlay.open())
	_next.pressed.connect(func() -> void: _main.call(&"_on_next_round"))
	refresh()


# === State ===

## The bar's items by function, for tests and captures: round, state, log, controls, next.
func items() -> Dictionary:
	return {"round": _round, "state": _state, "log": _log, "controls": _controls, "next": _next}


func overlay() -> ControlsOverlay:
	return _overlay


func _process(_delta: float) -> void:
	refresh()


## Reads the round, the phase, whose turn it is and the menu's Next Round button into the bar.
func refresh() -> void:
	var m := _main.get(&"opr_army_manager") as OPRArmyManager
	var rnd: int = m.current_round if m != null else 1
	var deploying: bool = m == null or m.game_phase == OPRArmyManager.GamePhase.DEPLOYMENT
	var source := _main.get(&"next_round_btn") as Button
	var key := "%d|%s|%d|%s|%s" % [rnd, deploying, _turn(), source.text, source.disabled]
	if key == _shown:
		return
	_shown = key
	show_state(rnd, deploying, _turn())
	_next.text = source.text
	_next.disabled = source.disabled


## Draws a state into the chips (display only — also used to measure the widest state).
func show_state(rnd: int, deploying: bool, turn: int) -> void:
	HouseStyle.set_chip(_round, "ROUND %d" % rnd, HouseStyle.CHIP_ROUND)
	if deploying or turn == Turn.NONE:
		HouseStyle.set_chip(_state, "DEPLOYMENT" if deploying else "PLAYING", HouseStyle.CHIP)
	elif turn == Turn.YOURS:
		HouseStyle.set_chip(_state, "YOUR TURN", HouseStyle.CHIP_TURN)
	else:
		HouseStyle.set_chip(_state, "NACHTMAHR'S TURN", HouseStyle.CHIP_ENEMY)


## Solo only: the AI's activation chain running = its turn, otherwise yours.
func _turn() -> int:
	if (_main.get(&"solo_ai_slots") as Dictionary).is_empty():
		return Turn.NONE
	return Turn.OPPONENT if bool(_main.get("_solo_ai_busy")) else Turn.YOURS


func _on_log_open_changed(open: bool) -> void:
	(_main.get(&"battle_log_panel") as Control).visible = open
	HouseStyle.set_selected(_log, open)


func _unhandled_key_input(event: InputEvent) -> void:
	if _overlay != null and event is InputEventKey and _overlay.handle_key(event as InputEventKey):
		get_viewport().set_input_as_handled()


# === Layout ===

## One side of the bar: a row at the top, growing inward from its edge.
func _row(at_right: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Right" if at_right else "Left"
	row.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW - 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the items own pixels, never the gaps
	row.anchor_left = 1.0 if at_right else 0.0
	row.anchor_right = row.anchor_left
	row.offset_top = HouseStyle.BAR_TOP
	row.offset_bottom = HouseStyle.BAR_TOP + HouseStyle.H_BAR
	if at_right:
		row.offset_right = -MARGIN
		row.offset_left = -MARGIN
		row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(row)
	return row


func _button(text: String, variant: StringName, tooltip: String) -> Button:
	var b := HouseStyle.button(text, variant)
	b.name = text.replace("?", "").strip_edges().replace(" ", "")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.tooltip_text = tooltip
	return b
