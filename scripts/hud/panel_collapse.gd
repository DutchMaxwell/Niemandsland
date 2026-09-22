class_name PanelCollapse
extends RefCounted
## Collapse toggle for a HUD PanelContainer (UI handoff 22.09.).
##
## The dice panel is fixed and large (~430 x 650 px) and covers a big part of the field
## (finding 3). This turns the panel's first VBox child into a clickable header: clicking it
## hides every other child and shrinks the panel to a slim title bar, clicking again restores
## it. Display only — it never touches the panel widgets' own logic, and it saves/restores each
## child's visibility, so a label that hides itself (e.g. RollPurposeLabel) stays hidden after
## an expand.

const HudTokensScript := preload("res://scripts/hud/hud_tokens.gd")

var _panel: PanelContainer
var _vbox: VBoxContainer
var _toggle: Button
var _title: String
var _top_expanded: float
var _top_collapsed: float
var _saved_visibility: Dictionary = {}
var _expanded := true


## Wire the toggle to `panel`: its first VBox child becomes the clickable header. `top_expanded`
## and `top_collapsed` are the panel's offset_top in each state (the panel is bottom-anchored).
func install(panel: PanelContainer, title: String, top_expanded: float, top_collapsed: float) -> void:
	_panel = panel
	_title = title
	_top_expanded = top_expanded
	_top_collapsed = top_collapsed
	_vbox = _first_vbox(panel)
	if _vbox == null:
		return
	_toggle = Button.new()
	_toggle.name = "CollapseToggle"
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.tooltip_text = "Collapse or expand this panel"
	_toggle.add_theme_font_override("font", HudTokensScript.head_font())
	_toggle.add_theme_font_size_override("font_size", 13)
	_toggle.add_theme_color_override("font_color", HudTokensScript.TEXT)
	_toggle.pressed.connect(_on_toggle)
	_vbox.add_child(_toggle)
	_vbox.move_child(_toggle, 0)
	# The panel's own Title label is redundant now — the toggle carries the name.
	for child in _vbox.get_children():
		if child is Label and (child as Label).text == title:
			(child as Label).visible = false
			break
	_snapshot()
	_refresh_text()


func _first_vbox(node: Node) -> VBoxContainer:
	for child in node.get_children():
		if child is VBoxContainer:
			return child as VBoxContainer
	return null


func _snapshot() -> void:
	_saved_visibility.clear()
	for child in _vbox.get_children():
		if child != _toggle and child is CanvasItem:
			_saved_visibility[child] = (child as CanvasItem).visible


func _on_toggle() -> void:
	_expanded = not _expanded
	for child in _vbox.get_children():
		if child == _toggle or not (child is CanvasItem):
			continue
		var item := child as CanvasItem
		item.visible = bool(_saved_visibility.get(child, true)) if _expanded else false
	_panel.offset_top = _top_expanded if _expanded else _top_collapsed
	_refresh_text()


func _refresh_text() -> void:
	_toggle.text = "%s  %s" % [_title, "▾" if _expanded else "▸"]