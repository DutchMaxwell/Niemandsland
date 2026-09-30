class_name CombatStage
extends CanvasLayer
## Pacing grill 2026-07-31 (maintainer): the central combat STAGE — one draggable card
## (top-centre, under the turn banner) that shows each combat phase with ALL its rule lines
## and makes the SOLO resolution WAIT there. Auto-beat (GraphicsSettings.combat_stage_hold_s,
## default 2.5 s), click on the card = next phase now, SPACE = pause to read, ◂/▸ browse the
## RUNNING activation (older history lives in the battle log's expandable lines). Solo-only
## by design — the grill ruled MP out: there is no automation to pace there. Floats stay in
## parallel: they anchor AT the model, the stage explains centrally, same event stream.
## Headless is inert unless a test forces it; batch sweeps (selfplay) are always inert.

var enabled: bool = true
var hold_s: float = 2.5
var batch: bool = false             # selfplay/batch sweeps: always inert
var force_for_tests: bool = false   # e2e: headless is inert by default

var _headline := ""
var _phases: Array = []      # [{title, lines}] of the RUNNING activation (◂/▸ browse)
var _pending: Array = []     # rule lines collected since the last phase boundary
var _collecting := false
var _view := -1              # browse index; -1 = live
var _paused := false
var _advance := false
var _holding := false

var _panel: PanelContainer = null
var _head_label: Label = null
var _phase_label: Label = null
var _lines_label: Label = null
var _pause_btn: Button = null
var _fade: Tween = null
var _placed := false
var _drag_start := Vector2.INF
var _drag_offset := Vector2.ZERO
var _dragging := false


func active() -> bool:
	if not enabled:
		return false
	if force_for_tests:
		return true   # tests opt in explicitly — selfplay sweeps never set this
	return not batch and DisplayServer.get_name() != "headless"


## Opens the collection window for one activation and resets the browse history.
func activation_begin(headline: String) -> void:
	if not active():
		return
	_headline = headline
	_phases = []
	_pending = []
	_view = -1
	_collecting = true


## One rule line (main taps the battle log's COMBAT stream into this).
func collect(line: String) -> void:
	if _collecting and active():
		_pending.append(line)


## The pacing gate: closes the pending lines into a phase card and HOLDS — the beat elapses,
## the player clicks ahead, or the stage is inert. A phase with no lines is no beat at all.
func phase(title: String) -> void:
	if not active():
		_pending = []
		return
	if _pending.is_empty():
		return
	_phases.append({"title": title, "lines": _pending})
	_pending = []
	_view = -1
	_render()
	_advance = false
	_holding = true
	var waited := 0.0
	while not _advance and (_paused or _view != -1 or waited < maxf(hold_s, 0.0)):
		await get_tree().process_frame
		if not _paused and _view == -1:
			waited += get_process_delta_time()
	_holding = false


## Closes the collection window; the card lingers one beat, then fades (non-blocking).
## The history stays browsable until the next activation resets it.
func activation_end() -> void:
	_collecting = false
	if _panel == null or not is_instance_valid(_panel):
		return
	_fade = create_tween()
	_fade.tween_interval(maxf(hold_s, 1.0))
	_fade.tween_property(_panel, "modulate:a", 0.0, 0.5)


## Click semantics: browsing → back to live; live hold → advance now.
func skip() -> void:
	if _view != -1:
		_view = -1
		_render()
		return
	_advance = true


func toggle_pause() -> void:
	_paused = not _paused
	if _pause_btn != null and is_instance_valid(_pause_btn):
		_pause_btn.text = HouseStyle.GLYPH_PLAY if _paused else HouseStyle.GLYPH_PAUSE


## ◂/▸ through the running activation's phases; reaching the newest returns to live.
func browse(delta: int) -> void:
	if _phases.is_empty():
		return
	var live := _phases.size() - 1
	var cur := live if _view == -1 else _view
	var nxt := clampi(cur + delta, 0, live)
	_view = -1 if nxt == live else nxt
	_render()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.keycode != KEY_SPACE:
		return
	if _holding and _panel != null and is_instance_valid(_panel) and _panel.visible:
		toggle_pause()
		get_viewport().set_input_as_handled()


func _render() -> void:
	_ensure_panel()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_panel.modulate.a = 1.0
	_panel.visible = true
	var idx := (_phases.size() - 1) if _view == -1 else _view
	if idx < 0 or idx >= _phases.size():
		return
	var ph := _phases[idx] as Dictionary
	_head_label.text = _headline
	_phase_label.text = "%s  (%d/%d)%s" % [str(ph["title"]), idx + 1, _phases.size(),
		("" if _view == -1 else "  — browsing")]
	var body := ""
	for l in (ph["lines"] as Array):
		body += "· %s\n" % str(l)
	_lines_label.text = body.strip_edges()
	if not _placed:
		_placed = true
		call_deferred("_place_default")


## Default spot: top-centre BELOW the three status lanes (banner 92 / toast 116 / peer 140 in main.gd,
## each ~26 px tall), so NACHTMAHR's turn banner stays readable; a drag wins from then on.
const DEFAULT_TOP := 172.0


func _place_default() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var vp := _panel.get_viewport_rect().size
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, DEFAULT_TOP)


func _ensure_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	layer = 80
	_panel = PanelContainer.new()
	_panel.name = "CombatStageCard"
	HouseStyle.apply(_panel)   # the house window (maintainer D98 = a)
	_panel.gui_input.connect(_card_input)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", HouseStyle.GAP_CONTROL)
	_panel.add_child(box)
	# The activation as the card's title, the phase as its gold key line, the rule lines as body text.
	_head_label = HouseStyle.label("", HouseStyle.EYEBROW)
	_head_label.uppercase = true
	box.add_child(_head_label)
	_phase_label = HouseStyle.label("", HouseStyle.NOTE)
	box.add_child(_phase_label)
	_lines_label = HouseStyle.label("", HouseStyle.BODY)
	box.add_child(_lines_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HouseStyle.GAP_CONTROL)
	box.add_child(row)
	# House glyphs: the UI font has no ◂ ⏸ ▸. House buttons take no focus, so a clicked ‖ never keeps
	# SPACE from the stage.
	row.add_child(_icon(HouseStyle.GLYPH_BACK, "Previous phase of this activation", browse.bind(-1)))
	_pause_btn = _icon(HouseStyle.GLYPH_PAUSE, "Pause the beat to read (SPACE)", toggle_pause)
	row.add_child(_pause_btn)
	row.add_child(_icon(HouseStyle.GLYPH_GO, "Next phase / back to live", browse.bind(1)))
	row.add_child(HouseStyle.label("click = next · SPACE = pause · drag to move", HouseStyle.CAPTION))


func _icon(glyph: String, tip: String, on_press: Callable) -> Button:
	var b := HouseStyle.button(glyph, HouseStyle.ICON, HouseStyle.ICON_BUTTON)
	b.custom_minimum_size.x = HouseStyle.ICON_BUTTON
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	return b


## LMB on the card: a short click advances, a moved press drags the card (deploy-box pattern).
func _card_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_start = _panel.get_global_mouse_position()
			_drag_offset = _panel.position
			_dragging = false
		else:
			if not _dragging:
				skip()
			_drag_start = Vector2.INF
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag_start != Vector2.INF:
		var d := _panel.get_global_mouse_position() - _drag_start
		if _dragging or d.length() > 6.0:
			_dragging = true
			_panel.position = _drag_offset + d
