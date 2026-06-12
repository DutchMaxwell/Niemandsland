class_name NetDialog
extends RefCounted
## Shared chrome + fields for the online Host / Join / Browse dialogs: a HudTokens
## glass panel with corner brackets and an Orbitron header. Used by BOTH the startup
## menu and the in-game multiplayer panel so the two entry points look identical.

# === Public (static) ===


## Builds the framed AcceptDialog. Caller fills the content via content().
static func build(title_text: String, index: String, ok_text: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title_text.capitalize()
	dialog.ok_button_text = ok_text

	var panel := PanelContainer.new()
	panel.name = "NetPanel"
	panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	panel.add_child(HudFrame.new())

	var margin := MarginContainer.new()
	UiPolish.set_dialog_margins(margin)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "NetContent"
	vbox.add_theme_constant_override("separation", HudTokens.SPACE_12)
	vbox.add_child(HudTokens.header(title_text, index))
	margin.add_child(vbox)

	dialog.add_child(panel)
	return dialog


## The content VBox to add fields into. find_child resolves the explicitly-named
## node — the intermediate MarginContainer gets a runtime auto-name, so a fixed
## node path would return null.
static func content(dialog: AcceptDialog) -> VBoxContainer:
	return dialog.find_child("NetContent", true, false) as VBoxContainer


## A plain content label.
static func label(text_value: String) -> Label:
	var lbl := Label.new()
	lbl.text = text_value
	return lbl


## A content text field with placeholder.
static func line_edit(text_value: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text_value
	edit.placeholder_text = placeholder
	return edit
