class_name GameMenu
## The ☰ game menu in the house style (uimenu; maintainer 23.09.: mockup LOOK, today's FULL function set):
## the slide-out shell and its "Table and army", "Multiplayer" (+ the room code) and "Save / Load /
## Graphics / End Battle" sections. Restyled in place — the same nodes, texts, tooltips and handlers,
## because the tutorial, the tool rail and the top bar hold references to them. The solo and deployment
## sections keep today's look (the column's ThemeManager theme) until PR 3.
##
## Width 260 px (scenes/main.tscn): the scene said 200, but row 6's "Show Deployment Zones" already
## pushed the column to 232 px; the house-style panel adds PAD_PANEL on each side.


## Dresses the shell `column` and the `sections` (VBoxes of labels and buttons): a section's first label
## is its eyebrow title, a later one body text that wraps inside the column (the multiplayer status).
## `danger` = the buttons that end something for good.
static func style(column: ScrollContainer, sections: Array, danger: Array) -> void:
	column.add_theme_stylebox_override(&"panel", HouseStyle.theme().get_stylebox(&"panel", HouseStyle.PANEL_VARIANT))
	for section: Variant in sections:
		var box := section as VBoxContainer
		box.theme = HouseStyle.theme()
		box.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
		var titled := false
		for c: Node in box.get_children():
			if c is Label and not titled:
				(c as Label).theme_type_variation = HouseStyle.EYEBROW
				(c as Label).uppercase = true   # the words stay as written; the eyebrow shows them in capitals
				titled = true
			elif c is Label:
				(c as Label).theme_type_variation = HouseStyle.BODY
				(c as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			elif c is Button:
				_line(c as Button, HouseStyle.DANGER_BUTTON if danger.has(c) else HouseStyle.BUTTON)


## The multiplayer status line: `text` in the ink of its connection state — HouseStyle.TONE_MUTED
## offline, TONE_OK online, TONE_WARN while reconnecting, TONE_DANGER when it failed.
static func set_status(label: Label, text: String, tone: StringName) -> void:
	label.text = text
	label.add_theme_color_override(&"font_color", HouseStyle.tone_ink(tone))


## The permanent room-code line above the sections: a menu line in the "online" ink.
static func room_code(b: Button) -> void:
	b.theme = HouseStyle.theme()
	_line(b, HouseStyle.BUTTON)
	b.add_theme_color_override(&"font_color", HouseStyle.tone_ink(HouseStyle.TONE_OK))


## A menu line: a ghost button (the Graphics dropdown too), its text at the left like the tool rail's lines.
static func _line(b: Button, variant: StringName) -> void:
	b.theme_type_variation = variant
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = HouseStyle.H_SEGMENT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
