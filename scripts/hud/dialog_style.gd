class_name DialogStyle
extends RefCounted
## Dark theme for the stock FileDialogs (Load/Save) so they match the Tactical HUD language
## (UI handoff 22.09.).
##
## The app theme already covers Window/Button/LineEdit/Tree, but the FileDialog's GRID view is an
## ItemList, which the app theme never styled — that is why the dialogs read as stock grey.
## This extends the app theme with the missing pieces; nothing else changes.

const HudTokensScript := preload("res://scripts/hud/hud_tokens.gd")


static func file_dialog_theme() -> Theme:
	var base: Theme = preload("res://scripts/glassmorphism_theme.gd").get_theme()
	var th := base.duplicate(true) as Theme
	_style_item_list(th)
	return th


static func _style_item_list(th: Theme) -> void:
	th.set_stylebox("panel", "ItemList", HudTokensScript.sunken_style())
	th.set_stylebox("selected", "ItemList", _fill(HudTokensScript.CYAN, 0.22))
	th.set_stylebox("selected_focus", "ItemList", _fill(HudTokensScript.CYAN, 0.30))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("cursor", "ItemList", _outline(HudTokensScript.CYAN))
	th.set_stylebox("cursor_unfocused", "ItemList", _outline(HudTokensScript.HAIRLINE))
	th.set_color("font_color", "ItemList", HudTokensScript.TEXT)
	th.set_color("font_selected_color", "ItemList", Color.WHITE)
	th.set_font_size("font_size", "ItemList", 13)


static func _fill(c: Color, a: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(c.r, c.g, c.b, a)
	s.set_corner_radius_all(HudTokensScript.RADIUS)
	return s


static func _outline(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_border_width_all(1)
	s.border_color = c
	s.set_corner_radius_all(HudTokensScript.RADIUS)
	return s