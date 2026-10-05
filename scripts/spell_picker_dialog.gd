class_name SpellPickerDialog
extends CanvasLayer
## Awaitable spell picker for the human cast flow (spell wave F2): one button per faction spell
## with token cost + live army-book effect text; spells the caster cannot afford are disabled.
## Asked on the house card (PromptCard, maintainer D98 = a); pick() returns the chosen entry ({} = cancel).

const EFFECT_W := PromptCard.WIDTH - 2 * HouseStyle.PAD_PANEL - 12   # the list's width left of its scrollbar


## entries: [{entry: Dictionary (registry), text: String (live effect), enabled: bool}]
func pick(caster_name: String, tokens: int, entries: Array) -> Dictionary:
	var card := PromptCard.new("%s — cast a spell (%d token%s)" % [caster_name, tokens, "" if tokens == 1 else "s"],
		"", "", "Cancel")
	card.cancel_value = {}
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(84 * entries.size(), 340))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.rows.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	scroll.add_child(list)
	for e in entries:
		var ed := e as Dictionary
		var entry: Dictionary = ed.get("entry", {})
		var cost := int(entry.get("threshold", 1))
		var b := HouseStyle.action_line("%s  (%d token%s)" % [str(entry.get("name", "?")), cost, "" if cost == 1 else "s"])
		b.tooltip_text = str(ed.get("text", ""))
		b.disabled = not bool(ed.get("enabled", true))
		b.pressed.connect(card.resolve.bind(entry))
		list.add_child(b)
		var fx := HouseStyle.label(str(ed.get("text", "")), HouseStyle.CAPTION)
		fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fx.custom_minimum_size.x = EFFECT_W   # a wrapping label is measured at width 0 without a floor
		list.add_child(fx)
	add_child(card)
	var result: Dictionary = await card.answer({})
	queue_free()
	return result
