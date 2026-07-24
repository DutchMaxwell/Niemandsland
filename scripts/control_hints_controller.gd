class_name ControlHintsController
extends CanvasLayer
## Contextual control hints (ROADMAP "Next" / UX polish): hover an object → a small dimmed line at
## the bottom of the screen names the hotkeys that apply to THAT object kind. Display-only, local,
## and deliberately CURATED — every listed key is a verified live binding (object_manager /
## main.gd), so the line can never advertise a dead key. Shows after a short hover dwell (no
## flicker while sweeping the cursor across the table), hides instantly when the hover ends —
## including on drag start, where the hover target is cleared anyway.

const DWELL_SEC := 0.45
const PANEL_ALPHA := 0.72

## One verified hint line per object kind (English-only UI).
const HINTS := {
	"regiment": "Drag: move tray · R (hold): rotate · Shift+F: frontage · Ctrl+R: pivot snap · F: arcs · M: reach · G: ring",
	"unit": "Drag: move · R (hold): rotate · G: ring · M: reach · T: trails · P: pin ruler · Esc: cancel drag",
	"object": "Drag: move · R (hold): rotate · Esc: cancel drag",
}

var _label: Label = null
var _panel: PanelContainer = null
var _dwell: Timer = null
var _pending_text := ""


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	_panel.name = "ControlHints"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate = Color(1, 1, 1, PANEL_ALPHA)
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -34.0
	_panel.offset_bottom = -10.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_label)
	_dwell = Timer.new()
	_dwell.one_shot = true
	_dwell.wait_time = DWELL_SEC
	_dwell.timeout.connect(_on_dwell)
	add_child(_dwell)


## PURE: the hint line for an object's classification ("" = show nothing).
static func hint_for(kind: String) -> String:
	return str(HINTS.get(kind, ""))


## PURE: classify an object by its precomputed facts (unit-testable without a scene).
static func classify(has_game_unit: bool, is_regiment: bool, selectable: bool) -> String:
	if is_regiment:
		return "regiment"
	if has_game_unit:
		return "unit"
	if selectable:
		return "object"
	return ""


## The hover seam (object_manager.hover_changed): null hides instantly, a target arms the dwell.
func on_hover_changed(obj: Node3D) -> void:
	if obj == null or not is_instance_valid(obj):
		_hide()
		return
	var unit: Object = obj.get_meta("game_unit") if obj.has_meta("game_unit") else null
	var is_regiment := false
	if unit != null and unit.get("unit_properties") != null:
		is_regiment = bool((unit.unit_properties as Dictionary).get("regiment_mode", false))
	var text := hint_for(classify(unit != null, is_regiment, obj.is_in_group("selectable")))
	if text.is_empty():
		_hide()
		return
	_pending_text = text
	if _panel.visible and _label.text == text:
		return   # same hint already up — no restart flicker
	_dwell.start()


func _on_dwell() -> void:
	if _pending_text.is_empty():
		return
	_label.text = _pending_text
	_panel.visible = true


func _hide() -> void:
	_pending_text = ""
	_dwell.stop()
	_panel.visible = false
