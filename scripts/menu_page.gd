class_name MenuPage
extends Control
## A page of the main menu in place of its list (the lesson page, the online hub): the backdrop stays, the
## wordmark stands small top left, then the way back "Main menu" (Esc), an eyebrow and a title over a `left`
## column; a `right` panel fills the rest of the width. MenuView.open_page shows it, `closed` takes it away.

signal closed

const MenuView = preload("res://scripts/startup_menu_view.gd")
const TOP := 150          # the way back and the right panel start here
const RIGHT_X := 640      # the right panel's left edge
const EDGE := 64          # the right panel ends this far from the right edge
const AIR_AFTER_BACK := 26   # sheet 07 .back margin-bottom
const AIR_AFTER_TITLE := 22  # sheet 07 h1 margin-bottom

var back: Button
var eyebrow: Label
var title: Label
var left: VBoxContainer
var right: PanelContainer
var column_width := 470
var _wordmark: VBoxContainer
var _head: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = HouseStyle.menu_theme()
	_wordmark = VBoxContainer.new()
	var word := HBoxContainer.new()
	word.add_theme_constant_override(&"separation", 0)
	for part: String in ["NIEMANDS", "LAND"]:
		var letter := _text(part, HouseStyle.FONT_WORDMARK_SMALL, load(HouseStyle.FONT_WORDMARK_PATH) as Font)
		letter.add_theme_color_override(&"font_color", HouseStyle.ACCENT if part == "LAND" else HouseStyle.INK)
		word.add_child(letter)
	_wordmark.add_child(word)
	_wordmark.add_child(HouseStyle.signature_rule(250))
	add_child(_wordmark)
	_head = VBoxContainer.new()
	_head.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
	add_child(_head)
	var way := HBoxContainer.new()
	back = Button.new()
	back.name = "WayBack"
	back.text = "Main menu"
	back.flat = true
	back.icon = HouseStyle.svg_icon(MenuView.ICON_SVG % "<path d='M15 5l-7 7 7 7'/>")
	back.add_theme_font_size_override(&"font_size", 16)
	back.add_theme_constant_override(&"icon_max_width", 16)
	back.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	back.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	back.pressed.connect(func() -> void: closed.emit())
	way.add_child(back)
	way.add_child(HouseStyle.key_cap("Esc"))
	_head.add_child(way)
	_head.add_child(_air(AIR_AFTER_BACK))   # the header's rhythm of sheets 02 and 07: 26 px after the way back,
	eyebrow = _text("", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font())
	eyebrow.add_theme_color_override(&"font_color", HouseStyle.ACCENT)
	_head.add_child(eyebrow)
	title = _text("", 44, HouseStyle.font(500))
	_head.add_child(title)
	_head.add_child(_air(AIR_AFTER_TITLE))   # ... 22 px after the title
	left = VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 18)
	_head.add_child(left)
	right = PanelContainer.new()
	right.theme_type_variation = HouseStyle.PANEL_VARIANT
	add_child(right)
	resized.connect(_layout)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Left margin as the menu's (5 % of the width, at least 28 px); the wordmark at the menu's masthead height.
func _layout() -> void:
	var margin := maxf(28, size.x * 0.05)
	_wordmark.position = Vector2(margin, 58)
	_head.position = Vector2(margin, TOP)
	_head.size = Vector2(column_width, 0)
	right.position = Vector2(RIGHT_X, TOP)
	right.size = Vector2(maxf(0, size.x - EDGE - RIGHT_X), 0)


## Extra height between two header parts, on top of the header's own separation.
func _air(height: int) -> Control:
	var air := Control.new()
	air.custom_minimum_size.y = height - HouseStyle.GAP_SECTION * 2   # the spacer stands between two separations
	return air


func _text(text: String, font_size: int, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_font_override(&"font", font)
	return label
