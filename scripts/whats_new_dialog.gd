class_name WhatsNewDialog
extends AcceptDialog
## A reusable house-style release sheet, with images supplied later by the render lane.

const DIALOG_SIZE := Vector2i(760, 650)
const IMAGE_HEIGHT := 144
var state_path := WhatsNewContent.STATE_PATH
var _content := WhatsNewContent.new()
var _locale := TranslationServer.get_locale()
var _cards: VBoxContainer
var _language_button: Button

func _ready() -> void:
	name = "WhatsNewDialog"
	exclusive = true
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	add_child(column)
	_language_button = HouseStyle.button(_content.text_for(_locale, "language"))
	_language_button.pressed.connect(_switch_language)
	column.add_child(_language_button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	scroll.add_child(_cards)
	MenuDialog.style(self)
	UiPolish.keep_window_reachable(self, DIALOG_SIZE)
	_refresh()

## Startup checks acknowledgement; the menu can always open the same sheet explicitly.
func open(unseen_only: bool = false) -> bool:
	if unseen_only and not WhatsNewContent.should_show(state_path):
		return false
	_refresh()
	popup_centered()
	get_ok_button().grab_focus()
	if WhatsNewContent.mark_seen(state_path) != OK:
		push_warning("WhatsNewDialog: could not save the last-seen version")
	return true

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		set_input_as_handled()

func _switch_language() -> void:
	_locale = "en" if WhatsNewContent.language(_locale) == "de" else "de"
	_refresh()

func _refresh() -> void:
	title = _content.text_for(_locale, "title") % WhatsNewContent.version()
	ok_button_text = _content.text_for(_locale, "close")
	for child in _cards.get_children():
		child.free()
	for card: Dictionary in _content.cards():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
		var copy: Dictionary = card[WhatsNewContent.language(_locale)]
		column.add_child(_wrapped_label(copy.title, HouseStyle.NOTE))
		column.add_child(_wrapped_label(copy.body, HouseStyle.BODY))
		column.add_child(_image_slot(card.image))
		_cards.add_child(HouseStyle.card(column))

func _wrapped_label(text: String, variant: StringName) -> Label:
	var label := HouseStyle.label(text, variant)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _image_slot(path: String) -> Control:
	if ResourceLoader.exists(path):
		var image := TextureRect.new()
		image.texture = load(path) as Texture2D
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size.y = IMAGE_HEIGHT
		return image
	var label := _wrapped_label(_content.text_for(_locale, "placeholder"), HouseStyle.CAPTION)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var slot := HouseStyle.card(label)
	slot.custom_minimum_size.y = IMAGE_HEIGHT
	return slot
