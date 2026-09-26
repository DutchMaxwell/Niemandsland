class_name GameMenu
## The ☰ game menu in the house style (uimenu, PR 1 of 3; maintainer 23.09.: mockup LOOK, today's FULL
## function set): the slide-out shell and its "Table and army" and "Save / Load / Graphics / End Battle"
## sections. Restyled in place — the same nodes, texts, tooltips and handlers, because the tutorial, the
## tool rail and the top bar hold references to them. The multiplayer, solo and deployment sections keep
## today's look (the column's ThemeManager theme) until PR 2 and 3.
##
## Width 260 px (scenes/main.tscn): the scene said 200, but row 6's "Show Deployment Zones" already
## pushed the column to 232 px; the house-style panel adds PAD_PANEL on each side.


## Dresses the shell `column` and the `sections` (VBoxes of labels and buttons). `danger` = the buttons
## that end something for good.
static func style(column: ScrollContainer, sections: Array, danger: Array) -> void:
	column.add_theme_stylebox_override(&"panel", HouseStyle.theme().get_stylebox(&"panel", HouseStyle.PANEL_VARIANT))
	for section: Variant in sections:
		var box := section as VBoxContainer
		box.theme = HouseStyle.theme()
		box.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
		for c: Node in box.get_children():
			if c is Label:
				(c as Label).theme_type_variation = HouseStyle.EYEBROW
				(c as Label).uppercase = true   # the words stay as written; the eyebrow shows them in capitals
			elif c is Button:
				_line(c as Button, HouseStyle.DANGER_BUTTON if danger.has(c) else HouseStyle.BUTTON)


## A menu line: a ghost button (the Graphics dropdown too), its text at the left like the tool rail's lines.
static func _line(b: Button, variant: StringName) -> void:
	b.theme_type_variation = variant
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = HouseStyle.H_SEGMENT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
