class_name NetDialog
extends RefCounted
## Shared chrome + fields for the online Host / Join / Browse dialogs: an eyebrow header with its NET index in
## the house style (MenuDialog). Used by BOTH the startup
## menu and the in-game multiplayer panel so the two entry points look identical.

# === Public (static) ===


## Builds the framed AcceptDialog. Caller fills the content via content(). The table's callers pass `at_table`:
## their window keeps the table's type scale, the menu's wears the menu's.
static func build(
	title_text: String, index: String, ok_text: String, at_table: bool = false
) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title_text.capitalize()
	dialog.ok_button_text = ok_text

	var vbox := VBoxContainer.new()
	vbox.name = "NetContent"
	vbox.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	MenuDialog.add_header(dialog, vbox)  # the title and a close box; the working index is never shown (`index` stays for callers)
	dialog.add_child(vbox)
	# Styled when it opens: the caller has added every field by then.
	dialog.about_to_popup.connect(func() -> void: MenuDialog.style(dialog, false, at_table))
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


## An invitation code as it is typed: upper case, letters and digits only, six at most, the hyphen after the
## third character ("abc123" -> "ABC-123").
static func code_as_typed(raw: String) -> String:
	var kept := ""
	for ch: String in raw.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			kept += ch
	kept = kept.substr(0, 6)
	return kept if kept.length() <= 3 else kept.substr(0, 3) + "-" + kept.substr(3)


## A content text field with placeholder.
static func line_edit(text_value: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text_value
	edit.placeholder_text = placeholder
	return edit
