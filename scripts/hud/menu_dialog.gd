class_name MenuDialog
extends RefCounted
## House-style chrome for the menu scene's AcceptDialogs: the shared theme, a gold OK, ghost lines for the
## content buttons. A control that already carries a variation keeps it (RESET = danger, goal lines = caption).


## The menu's windows have no frame of their own (borderless): the title and a close button stand as the first
## row of their content (add_header) and a scrim dims the menu behind them (open). `framed` keeps the engine's
## title bar for the in-game dialogs that have no header of their own. The menu's windows wear the menu's
## scale (HouseStyle.menu_theme); a framed window and a window `at_table` keep the table's theme.
static func style(d: AcceptDialog, framed: bool = false, at_table: bool = false) -> void:
	var menu_scale := not framed and not at_table
	var action_h := HouseStyle.MENU_H_ACTION if menu_scale else HouseStyle.H_ACTION
	d.theme = HouseStyle.menu_theme() if menu_scale else HouseStyle.theme()
	d.borderless = not framed
	# A borderless window shows only its rounded sheet: without these its square, engine-grey (76, 76, 76) back shows
	# at the sheet's corners (gap review 27.11., sheet 08).
	d.transparent = not framed
	d.transparent_bg = not framed
	d.get_ok_button().theme_type_variation = HouseStyle.PRIMARY
	d.get_ok_button().custom_minimum_size.y = action_h
	if d is ConfirmationDialog:
		(d as ConfirmationDialog).get_cancel_button().theme_type_variation = HouseStyle.BUTTON
		(d as ConfirmationDialog).get_cancel_button().custom_minimum_size.y = action_h
	for n: Node in d.find_children("*", "Button", true, false):
		var b := n as Button
		if b == d.get_ok_button() or b.theme_type_variation != &"" or b is CheckBox or b is CheckButton:
			continue
		if d is ConfirmationDialog and b == (d as ConfirmationDialog).get_cancel_button():
			continue
		b.theme_type_variation = HouseStyle.BUTTON
		b.custom_minimum_size.y = HouseStyle.H_SEGMENT
	for n: Node in d.find_children("*", "Label", true, false):
		if (n as Label).theme_type_variation == &"":
			(n as Label).theme_type_variation = HouseStyle.BODY


## The window's title and a close button as the first row of `content`; returns the title label.
static func add_header(d: AcceptDialog, content: Control) -> Label:
	var row := HouseStyle.panel_header(d.title, true)
	(row.get_node("CloseButton") as Button).pressed.connect(
		func() -> void:
			d.hide()
			d.canceled.emit()
	)
	content.add_child(row)
	content.move_child(row, 0)
	return row.get_child(0) as Label


## Shows `dialog` in `host` over a scrim that dims the menu while the window is open.
static func open(host: Node, dialog: AcceptDialog) -> void:
	host.add_child(dialog)
	attach_scrim(dialog)
	dialog.reset_size()
	dialog.popup_centered()


## A full-screen scrim behind a window that is already in the tree: visible while the window is, gone with it.
static func attach_scrim(dialog: Window) -> void:
	var scrim := ColorRect.new()
	scrim.name = "DialogScrim"
	scrim.color = Color(HouseStyle.SCRIM, 0.0 if not UiMotion.reduced() else HouseStyle.SCRIM.a)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.visible = dialog.visible
	dialog.get_parent().add_child(scrim)
	dialog.visibility_changed.connect(
		func() -> void:
			scrim.visible = dialog.visible
			UiFeedback.play_panel(dialog.visible)
			if dialog.visible and not UiMotion.reduced():
				scrim.color.a = 0.0
				var fade := scrim.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				fade.tween_property(scrim, "color:a", HouseStyle.SCRIM.a, HudTokens.DUR_PANEL_IN)
	)
	dialog.tree_exited.connect(scrim.queue_free)
