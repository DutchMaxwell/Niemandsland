class_name PromptCard
extends CanvasLayer
## ONE in-viewport prompt for the questions the game asks during play (maintainer D98 = a, 28.09.2026):
## the solo combat questions (Incoming fire!, Strike back?, Cast window, Split fire?, Versatile Attack,
## Ambush Re-Deployment, a rule's placement, Hero morale), the spell picker and the interference tableau.
## A house-style card over the table instead of an OS window: a clear shield keeps the board in sight
## but out of reach while the question stands (the old dialogs were exclusive), and the keys stay what
## they were — Enter takes the OK button, Esc the cancel button. Code-built and awaitable:
##   var card := PromptCard.new("Strike back?", text, "Strike back", "Hold")
##   add_child(card)
##   var yes: bool = await card.answer()
## A caller that answers with more than yes / no sets ok_value / cancel_value or calls resolve() itself.

const LAYER := 90       # over the HUD and the action strip (85), under the loading overlay (200)
const WIDTH := 420      # data text never decides the width (UI audit 2026-07-24)

var title := ""
var ok_button: Button           # null without an OK ("" as its text)
var cancel_button: Button       # null when the question has no way out (the saves)
var ok_value: Variant = true
var cancel_value: Variant = false
var _outcome: Array = []


func _init(title_text: String, text: String = "", ok_text: String = "OK", cancel_text: String = "Cancel") -> void:
	title = title_text
	layer = LAYER
	var shield := Control.new()
	shield.name = "Shield"
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.theme = HouseStyle.theme()
	add_child(shield)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.add_child(centre)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = HouseStyle.PANEL_VARIANT
	card.custom_minimum_size = Vector2(WIDTH, 0)
	centre.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
	card.add_child(box)
	var header := HouseStyle.panel_header(title_text, true)
	_wrap(header.get_child(0) as Label, WIDTH - 2 * HouseStyle.PAD_PANEL - HouseStyle.ICON_BUTTON - HouseStyle.GAP_ROW)
	box.add_child(header)
	if text != "":
		box.add_child(_wrap(HouseStyle.label(text, HouseStyle.BODY), WIDTH - 2 * HouseStyle.PAD_PANEL))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	box.add_child(actions)
	if ok_text != "":
		ok_button = _action(actions, ok_text, HouseStyle.PRIMARY, func() -> void: resolve(ok_value))
	if cancel_text != "":
		cancel_button = _action(actions, cancel_text, HouseStyle.BUTTON, func() -> void: resolve(cancel_value))
	var close := header.get_node("CloseButton") as Button
	close.visible = cancel_button != null
	close.pressed.connect(func() -> void: _press(cancel_button))


## Ends the question with `value`; the first answer wins.
func resolve(value: Variant) -> void:
	if _outcome.is_empty():
		_outcome.append(value)


## Waits for the answer, then frees the card. `unanswered` is what a card that left the tree without
## an answer means (freed with its host).
func answer(unanswered: Variant = false) -> Variant:
	while _outcome.is_empty() and is_inside_tree():
		await get_tree().process_frame
	var result: Variant = unanswered if _outcome.is_empty() else _outcome[0]
	queue_free()
	return result


## The old dialogs' keys: Enter takes the OK button, Esc the cancel button (Esc also ended a question
## that has none). Every other key stops here, as it did at the exclusive window.
func _input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.is_action(&"ui_accept"):
		_press(ok_button)
	elif event.is_action(&"ui_cancel"):
		if cancel_button != null:
			_press(cancel_button)
		else:
			resolve(cancel_value)


func _press(b: Button) -> void:
	if b != null and b.is_visible_in_tree() and not b.disabled:
		b.pressed.emit()


func _action(row: HBoxContainer, text: String, variant: StringName, on_press: Callable) -> Button:
	var b := HouseStyle.button(text, variant, HouseStyle.H_ACTION)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # a long unit name wraps, every word stays
	b.pressed.connect(on_press)
	row.add_child(b)
	return b


## A wrapping label needs a width floor: in a container it is measured at width 0 otherwise.
static func _wrap(l: Label, width: int) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l
