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
## A caller with more than yes / no adds its controls to `rows` (split fire: one check box per weapon) and
## sets ok_value / cancel_value or calls resolve() itself.

const LAYER := 90       # over the HUD and the action strip (85), under the loading overlay (200)
const WIDTH := 420      # data text never decides the width (UI audit 2026-07-24)

var title := ""
var rows: VBoxContainer         # the caller's controls, between the text and the buttons
var ok_button: Button           # null without an OK ("" as its text)
var cancel_button: Button       # null when the question has no way out (the saves)
var ok_value: Variant = true
## The menu's cards fade in and out (motion table: the scrim to 66 % and the card from alpha 0 and scale 0.98,
## 220 ms in, 180 ms out). Off by default, so the questions during play stay instant; Reduce Motion is always
## instant.
var animate := false
## The menu's cards stand at the menu's scale (HouseStyle.menu_theme, 44 px actions, a 32 px close box). Off by
## default: the questions during play keep the table's type scale. Set before the card enters the tree.
var menu_scale := false
var cancel_value: Variant = false
var _outcome: Array = []
var _scrim: ColorRect
var _title_label: Label
var _text_label: Label


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
	_title_label = _wrap(header.get_child(0) as Label,
			WIDTH - 2 * HouseStyle.PAD_PANEL - HouseStyle.ICON_BUTTON - HouseStyle.GAP_ROW)
	box.add_child(header)
	if text != "":
		_text_label = _wrap(HouseStyle.label(text, HouseStyle.BODY), WIDTH - 2 * HouseStyle.PAD_PANEL)
		box.add_child(_text_label)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW)
	box.add_child(rows)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	box.add_child(actions)
	# The way out left, the main action right: the old dialogs' order and the dice window's (Quick | Roll).
	if cancel_text != "":
		cancel_button = _action(actions, cancel_text, HouseStyle.BUTTON, func() -> void: resolve(cancel_value))
	if ok_text != "":
		ok_button = _action(actions, ok_text, HouseStyle.PRIMARY, func() -> void: resolve(ok_value))
	var close := header.get_node("CloseButton") as Button
	close.visible = cancel_button != null
	close.pressed.connect(func() -> void: _press(cancel_button))


func _ready() -> void:
	rows.visible = rows.get_child_count() > 0
	if menu_scale:
		_apply_menu_scale()
	if animate and not UiMotion.reduced():
		_fade(true)


## The menu's scale: the menu theme, 44 px actions, a 32 px close box, and the wrapping floors measured against
## the wider padding (else the text would force the card wider than WIDTH).
func _apply_menu_scale() -> void:
	($Shield as Control).theme = HouseStyle.menu_theme()
	for b: Button in [ok_button, cancel_button]:
		if b != null:
			b.custom_minimum_size.y = HouseStyle.MENU_H_ACTION
	var close := find_child("CloseButton", true, false) as Control
	close.custom_minimum_size = Vector2.ONE * HouseStyle.MENU_ICON_BUTTON
	_title_label.custom_minimum_size.x = \
			WIDTH - 2 * HouseStyle.MENU_PAD_PANEL - HouseStyle.MENU_ICON_BUTTON - HouseStyle.GAP_ROW
	if _text_label != null:
		_text_label.custom_minimum_size.x = WIDTH - 2 * HouseStyle.MENU_PAD_PANEL
		_split_paragraphs()
	if cancel_button != null:
		_add_esc_cap(cancel_button)


## A text with a blank line is split there: every paragraph after the first steps back (muted, caption size).
func _split_paragraphs() -> void:
	var paragraphs := _text_label.text.split("\n\n", false)
	if paragraphs.size() < 2:
		return
	_text_label.text = paragraphs[0]
	var after: Node = _text_label
	for i in range(1, paragraphs.size()):
		var more := _wrap(HouseStyle.label(paragraphs[i], HouseStyle.CAPTION),
				WIDTH - 2 * HouseStyle.MENU_PAD_PANEL)
		after.add_sibling(more)
		after = more


## The way out shows its key: an Esc cap right after the button's text.
func _add_esc_cap(button: Button) -> void:
	var cap := HouseStyle.key_cap("Esc")
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cap)
	var place := func() -> void:
		var font := button.get_theme_font(&"font")
		var text_w := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				button.get_theme_font_size(&"font_size")).x
		cap.position = Vector2((button.size.x + text_w) * 0.5 + 10.0,
				(button.size.y - cap.get_combined_minimum_size().y) * 0.5)
	button.resized.connect(place)
	place.call_deferred()


## Ends the question with `value`; the first answer wins.
func resolve(value: Variant) -> void:
	if _outcome.is_empty():
		_outcome.append(value)


## Waits for the answer, then frees the card. `unanswered` is what a card that left the tree without
## an answer means (freed with its host).
## The title's colour (a warning reads gold, sheet 08); the accent eyebrow otherwise.
func set_title_tone(colour: Color) -> void:
	_title_label.add_theme_color_override(&"font_color", colour)


func answer(unanswered: Variant = false) -> Variant:
	while _outcome.is_empty() and is_inside_tree():
		await get_tree().process_frame
	var result: Variant = unanswered if _outcome.is_empty() else _outcome[0]
	if animate and is_inside_tree() and not UiMotion.reduced():
		await _fade(false)
	queue_free()
	return result


## The scrim and the card come in (`opening`) or go out: alpha and a 0.98 -> 1 scale, cubic.
func _fade(opening: bool) -> void:
	var card := find_child("Card", true, false) as Control
	if _scrim == null:
		_scrim = ColorRect.new()
		_scrim.color = Color(HouseStyle.SCRIM, 0.0)
		_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		$Shield.add_child(_scrim)
		$Shield.move_child(_scrim, 0)
	# The card sits in a container, which resets its scale: the scale goes on the full-screen holder that
	# centres it, so the card scales about the screen centre.
	var holder := card.get_parent() as Control
	if opening:
		card.modulate.a = 0.0
		holder.scale = Vector2.ONE * 0.98
		await get_tree().process_frame  # the pivot needs the laid-out size
	holder.pivot_offset = holder.size * 0.5
	var duration := HudTokens.DUR_PANEL_IN if opening else HudTokens.DUR_PANEL_OUT
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	tween.tween_property(card, "modulate:a", 1.0 if opening else 0.0, duration)
	tween.tween_property(holder, "scale", Vector2.ONE if opening else Vector2.ONE * 0.98, duration)
	tween.tween_property(_scrim, "color:a", HouseStyle.SCRIM.a if opening else 0.0, duration)
	await tween.finished


## The old dialogs' keys: Enter takes the OK button, Esc the cancel button (Esc also ended a question
## that has none). Every other key stops here, as it did at the exclusive window.
func _input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.is_action(&"ui_accept"):
		# A button of the card that holds focus takes Enter (the menu's quit card focuses its safe answer);
		# the in-game cards have no focusable button, so Enter keeps taking OK there.
		var focused := get_viewport().gui_get_focus_owner() as Button
		_press(focused if focused != null and is_ancestor_of(focused) else ok_button)
	elif event.is_action(&"ui_cancel"):
		if cancel_button != null:
			_press(cancel_button)
		else:
			resolve(cancel_value)


## A third answer between the way out and the OK button (split fire: "All at <target>").
func add_action(text: String, value: Variant) -> Button:
	var anchor := cancel_button if cancel_button != null else ok_button   # without a way out: just before OK
	var b := _action(anchor.get_parent() as HBoxContainer, text, HouseStyle.BUTTON, func() -> void: resolve(value))
	b.get_parent().move_child(b, anchor.get_index() + (1 if cancel_button != null else 0))
	return b


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
