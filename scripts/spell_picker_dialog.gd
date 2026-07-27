class_name SpellPickerDialog
extends CanvasLayer
## Awaitable spell picker for the human cast flow (spell wave F2): one button per faction spell
## with token cost + live army-book effect text; spells the caster cannot afford are disabled.
## Code-built like InterferenceDialog; pick() returns the chosen entry ({} = cancel).

var _outcome: Array = []


## entries: [{entry: Dictionary (registry), text: String (live effect), enabled: bool}]
func pick(caster_name: String, tokens: int, entries: Array) -> Dictionary:
	_outcome = []
	layer = 90
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := Label.new()
	title.text = "%s — cast a spell (%d token%s)" % [caster_name, tokens, "" if tokens == 1 else "s"]
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, mini(64 * entries.size(), 340))
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for e in entries:
		var ed := e as Dictionary
		var entry: Dictionary = ed.get("entry", {})
		var b := Button.new()
		var cost := int(entry.get("threshold", 1))
		b.text = "%s  (%d token%s)" % [str(entry.get("name", "?")), cost, "" if cost == 1 else "s"]
		b.tooltip_text = str(ed.get("text", ""))
		b.disabled = not bool(ed.get("enabled", true))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _outcome.append(entry))
		list.add_child(b)
		var fx := Label.new()
		fx.text = str(ed.get("text", ""))
		fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fx.custom_minimum_size = Vector2(440, 0)
		fx.add_theme_font_size_override("font_size", 11)
		fx.modulate = Color(1, 1, 1, 0.75)
		list.add_child(fx)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(120, 34)
	cancel.pressed.connect(func() -> void: _outcome.append({}))
	box.add_child(cancel)
	while _outcome.is_empty() and is_inside_tree():
		await get_tree().process_frame
	var result: Dictionary = {} if _outcome.is_empty() else (_outcome[0] as Dictionary)
	queue_free()
	return result
