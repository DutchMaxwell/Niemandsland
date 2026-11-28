class_name WhatsNewDialog
extends AcceptDialog
## A reusable house-style release sheet, with images supplied later by the render lane.

const DIALOG_SIZE := Vector2i(708, 884)
const IMAGE_SIZE := Vector2(150, 84)
const TITLE_PX := 17
const BODY_PX := 15
var state_path := WhatsNewContent.STATE_PATH
var _content := WhatsNewContent.new()
var _locale := TranslationServer.get_locale()
var _in_game := false
var _cards: VBoxContainer
var _language_button: Button   # the Deutsch segment (its handler is the same switch)
var _english_button: Button
var _close_button: Button
var _header_title: Label

func _ready() -> void:
	name = "WhatsNewDialog"
	exclusive = true
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	add_child(column)
	_header_title = MenuDialog.add_header(self, column)
	# English | Deutsch: a segment pair at the right of the header row, before the close box.
	var header := column.get_child(0) as HBoxContainer
	var segments := HBoxContainer.new()
	segments.add_theme_constant_override("separation", 0)
	_english_button = _segment("English", "en")
	_language_button = _segment("Deutsch", "de")
	segments.add_child(_english_button)
	segments.add_child(_language_button)
	header.add_child(segments)
	header.move_child(segments, header.get_node("CloseButton").get_index())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	scroll.add_child(_cards)
	column.add_child(_close_row())
	MenuDialog.style(self)
	get_ok_button().hide()   # the content's own full-width Close answers for it
	UiPolish.keep_window_reachable(self, DIALOG_SIZE)
	_refresh()

## Startup checks acknowledgement; the menu can always open the same sheet explicitly.
## `in_game` only changes the dismiss label: "Back to the table" mid-battle, "Close" on the menu.
func open(unseen_only: bool = false, in_game: bool = false) -> bool:
	if unseen_only and not WhatsNewContent.should_show(state_path):
		return false
	_in_game = in_game
	_refresh()
	popup_centered()
	_fit_to_cards()
	_close_button.grab_focus()
	if WhatsNewContent.mark_seen(state_path) != OK:
		push_warning("WhatsNewDialog: could not save the last-seen version")
	return true

## The sheet takes the height its cards need, up to DIALOG_SIZE: text-only cards no longer
## leave the lower half of a tall sheet empty (gap review 28.11., sheet 08). Measured one
## frame on, once the cards are wrapped at their width.
func _fit_to_cards() -> void:
	await get_tree().process_frame
	var spare := (_cards.get_parent() as Control).size.y - _cards.size.y
	if visible and spare > 1.0:
		size.y = int(size.y - spare)
		move_to_center()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		set_input_as_handled()

func _set_language(code: String) -> void:
	_locale = code
	_refresh()

func _segment(text: String, code: String) -> Button:
	var b := HouseStyle.button(text, HouseStyle.SEGMENT, HouseStyle.H_SEGMENT)
	b.custom_minimum_size.x = 96
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(_set_language.bind(code))
	return b

## "Close" at full width, 44 px high, with its Esc key cap; it presses the dialog's own (hidden) OK.
func _close_row() -> Button:
	_close_button = HouseStyle.button("", HouseStyle.PRIMARY, HouseStyle.MENU_H_ACTION)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(func() -> void: get_ok_button().pressed.emit())
	var cap := HouseStyle.key_cap_on_gold("Esc")
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cap.grow_vertical = Control.GROW_DIRECTION_BOTH
	cap.offset_left = -16
	cap.offset_right = -16
	_close_button.add_child(cap)
	return _close_button

func _refresh() -> void:
	title = _content.text_for(_locale, "title") % WhatsNewContent.version()
	_header_title.text = title.to_upper()
	ok_button_text = _content.text_for(_locale, "back" if _in_game else "close")
	_close_button.text = ok_button_text
	var language := WhatsNewContent.language(_locale)
	HouseStyle.set_selected(_english_button, language == "en")
	HouseStyle.set_selected(_language_button, language == "de")
	for child in _cards.get_children():
		child.free()
	for card: Dictionary in _content.cards():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
		var copy: Dictionary = card[WhatsNewContent.language(_locale)]
		var title_label := _wrapped_label(copy.title, HouseStyle.NOTE)
		title_label.add_theme_font_override("font", HouseStyle.font(500))
		title_label.add_theme_font_size_override("font_size", TITLE_PX)
		var body_label := _wrapped_label(copy.body, HouseStyle.BODY)
		body_label.add_theme_font_size_override("font_size", BODY_PX)
		column.add_child(title_label)
		column.add_child(body_label)
		# A card that names a picture is a row (the picture left, 150 x 84); one without it,
		# or whose picture is missing, is the text alone, full width.
		var picture := _picture(str(card.get("image", "")))
		if picture == null:
			_cards.add_child(HouseStyle.card(column))
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
		row.add_child(picture)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		_cards.add_child(HouseStyle.card(row))

func _wrapped_label(text: String, variant: StringName) -> Label:
	var label := HouseStyle.label(text, variant)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _picture(path: String) -> TextureRect:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var image := TextureRect.new()
	image.texture = load(path) as Texture2D
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size = IMAGE_SIZE
	image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return image
