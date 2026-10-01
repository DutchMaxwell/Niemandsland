class_name NetDialog
extends RefCounted
## Shared chrome + fields for the online Host / Join / Browse dialogs: an eyebrow header with its NET index in
## the house style (MenuDialog). Used by BOTH the startup
## menu and the in-game multiplayer panel so the two entry points look identical.

# === Public (static) ===


## Builds the framed AcceptDialog. Caller fills the content via content().
static func build(title_text: String, index: String, ok_text: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title_text.capitalize()
	dialog.ok_button_text = ok_text

	var vbox := VBoxContainer.new()
	vbox.name = "NetContent"
	vbox.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	var head := HBoxContainer.new()
	var heading := HouseStyle.label(title_text.to_upper(), HouseStyle.EYEBROW)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	head.add_child(HouseStyle.label(index, HouseStyle.CAPTION))
	vbox.add_child(head)
	dialog.add_child(vbox)
	# Styled when it opens: the caller has added every field by then.
	dialog.about_to_popup.connect(func() -> void: MenuDialog.style(dialog))
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
