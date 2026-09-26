class_name GameMenu
## The ☰ game menu in the house style (uimenu; maintainer 23.09.: mockup LOOK, today's FULL function set):
## the slide-out shell and its "Table and army", "Multiplayer" (+ the room code) and "Save / Load /
## Graphics / End Battle" sections, then the NACHTMAHR solo section, deployment zones, the phase gate and
## the host tools. Restyled in place — the same nodes, texts, tooltips and handlers, because the tutorial,
## the tool rail and the top bar hold references to them.
##
## Width 260 px (scenes/main.tscn): the scene said 200, but row 6's "Show Deployment Zones" already
## pushed the column to 232 px; the house-style panel adds PAD_PANEL on each side.


## Dresses the shell `column` and the `sections` built with the scene. `danger` = the buttons that end
## something for good.
static func style(column: ScrollContainer, sections: Array, danger: Array) -> void:
	column.add_theme_stylebox_override(&"panel", HouseStyle.theme().get_stylebox(&"panel", HouseStyle.PANEL_VARIANT))
	for box: Variant in sections:
		section(box as VBoxContainer, danger)


## Dresses one section (a VBox of labels and buttons; a section that rebuilds itself calls this again):
## a label as its first child is the eyebrow title, a later one text that wraps inside the column — body,
## unless its builder gave it a role (a CAPTION hint). Every button, check box and dropdown is a menu line.
static func section(box: VBoxContainer, danger: Array = []) -> void:
	box.theme = HouseStyle.theme()
	box.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	var first := true
	for c: Node in box.get_children():
		if c.is_queued_for_deletion():   # a rebuilt section's old nodes linger to the frame's end
			continue
		if c is Label and first:
			(c as Label).theme_type_variation = HouseStyle.EYEBROW
			(c as Label).uppercase = true   # the words stay as written; the eyebrow shows them in capitals
			(c as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # never widens the column
		elif c is Label:
			if (c as Label).theme_type_variation == &"":
				(c as Label).theme_type_variation = HouseStyle.BODY
			(c as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif c is Button:
			_line(c as Button, HouseStyle.DANGER_BUTTON if danger.has(c) else HouseStyle.BUTTON)
		first = false


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
## A line never widens the column — a scrolling column gives 8 px of it to the scrollbar (#1145 CI): a text
## that does not fit wraps (every word stays), a dropdown trims its closed text (its list shows each entry).
static func _line(b: Button, variant: StringName) -> void:
	b.theme_type_variation = variant
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = HouseStyle.H_SEGMENT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if b is OptionButton:
		(b as OptionButton).fit_to_longest_item = false
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
