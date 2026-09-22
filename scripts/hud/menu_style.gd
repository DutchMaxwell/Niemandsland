class_name MenuStyle
extends RefCounted
## Restyle the in-game slide-out menu (LeftPanelVBox) to the Tactical HUD language
## (UI handoff 22.09.): ghost buttons, Orbitron section headers, muted body text.
##
## The menu shipped with the older glassmorphism theme; the mockup uses HudTokens.
## This walks the built tree and overrides button/label styles in place. Display only —
## it changes no behaviour and leaves the buttons' signals intact.

const HudTokensScript := preload("res://scripts/hud/hud_tokens.gd")


static func apply(root: Node) -> void:
	for child in root.get_children():
		if child is OptionButton:
			_style_button(child, HudTokensScript.ghost_button())
		elif child is Button:
			_style_button(child, _button_set(child))
		elif child is Label:
			_style_label(child)
		apply(child)


## Destructive action gets the amber set; everything else is a ghost button.
static func _button_set(btn: Button) -> Dictionary:
	if btn.name == "EndBattleBtn":
		return HudTokensScript.amber_button()
	return HudTokensScript.ghost_button()


static func _style_button(btn: Button, set: Dictionary) -> void:
	for state in set.keys():
		btn.add_theme_stylebox_override(state, set[state])
	btn.add_theme_font_override("font", HudTokensScript.body_font())
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", HudTokensScript.TEXT)
	btn.add_theme_color_override("font_hover_color", HudTokensScript.CYAN)
	btn.add_theme_color_override("font_pressed_color", HudTokensScript.CYAN)
	btn.add_theme_color_override("font_focus_color", HudTokensScript.TEXT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = HudTokensScript.BUTTON_H


## Section headers end with ":" ("Multiplayer:", "Graphics:"); everything else is body text.
static func _style_label(lbl: Label) -> void:
	var is_header := lbl.text.ends_with(":")
	lbl.add_theme_font_override("font",
		HudTokensScript.head_font() if is_header else HudTokensScript.body_font())
	lbl.add_theme_font_size_override("font_size", 12 if is_header else 13)
	lbl.add_theme_color_override("font_color", HudTokensScript.TEXT_MUTED)