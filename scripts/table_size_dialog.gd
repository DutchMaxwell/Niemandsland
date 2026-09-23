extends Window
class_name TableSizeDialog
## Select first, create once. Cancelling never emits size_chosen or changes game state.
signal size_chosen(size_feet: Vector2)
signal cancelled
const FEET_4X4 := Vector2(4,4)
const FEET_6X4 := Vector2(6,4)
const DEFAULT_SIZE := FEET_6X4
const INCHES_TO_FEET := 1.0/12.0
const CM_TO_FEET := 1.0/30.48
const PAGE_ASPECT := 1768.0/1080.0
const FONT = preload("res://assets/ui_glassmorphism/fonts/Inter.ttf")
const LOGO = preload("res://assets/ui_glassmorphism/fonts/Orbitron.ttf")
const INK := Color("e9e9df")
const MUTED := Color("a7b0b6")
const CYAN := Color("87babc")
const GOLD := Color("d9bd83")
# Keys are the TABLE's biome ids (table.gd BIOMES): the selection goes straight into table.set_biome.
const BIOMES := {
	"urban_ruins":["Urban ruins","Fractured stone, scarred concrete and scattered rubble."],
	"alien_jungle":["Alien jungle","Dense foliage, mossy ground and strange undergrowth."],
	"temperate_grassland":["Grassland","Soft earth, open grass and weathered woodland."],
	"arid_desert":["Arid desert","Wind-worn rock, dry ground and drifting sand."],
	"frozen_tundra":["Frozen tundra","Frosted stone and snow across a cold, exposed landscape."],
	"volcanic_ash":["Volcanic ash","Blackened rock, ash-covered ground and ember-red accents."]}
## The menu diorama names grassland "grassland"; the table only knows "temperate_grassland".
const MENU_TO_TABLE := {"grassland":"temperate_grassland"}
## Preview images keep the diorama's file names (assets/ui/table_setup/<name>.webp).
const PREVIEW_FILE := {"temperate_grassland":"grassland"}
var selected_biome := "urban_ruins"
var selected_size := "standard"
var custom_inches := Vector2(72,48)
var _biome_keys: Array = BIOMES.keys()
var _emitted := false
var _unit_option: OptionButton
var _width_input: LineEdit
var _length_input: LineEdit
var _biome_buttons: Dictionary = {}
var _size_buttons: Dictionary = {}
var _size_labels: Dictionary = {}
var _custom: HBoxContainer
var _error: Label
var _summary: Label
var _create: Button
var _back: Button
var _preview: TextureRect
var _preview_title: Label
var _preview_description: Label
var _footprint: Footprint
var _feet_label: Label
var _secondary_size: Label
var _unit_labels: Array[Label] = []
var _scroll: ScrollContainer
var _header: BoxContainer
var _footer: BoxContainer
var _page: VBoxContainer
var _left: VBoxContainer
var _columns: BoxContainer
var _grid: GridContainer
var _hero: Control
var _margin: MarginContainer
var _cards: Array[TextureRect] = []
var _valid := true

class Footprint extends Control:
	var inches := Vector2(72,48)
	var centimeters := false
	func _draw() -> void:
		var scale_value := minf((size.x-90)/inches.x,(size.y-38)/inches.y)
		var extent := inches*scale_value
		var origin := Vector2((size.x-60-extent.x)*0.5,(size.y+16-extent.y)*0.5)
		draw_rect(Rect2(origin,extent),Color("14262b"))
		for i in range(1,12):
			var x := origin.x+extent.x*float(i)/12
			draw_line(Vector2(x,origin.y),Vector2(x,origin.y+extent.y),Color("234048"))
		for i in range(1,8):
			var y := origin.y+extent.y*float(i)/8
			draw_line(Vector2(origin.x,y),Vector2(origin.x+extent.x,y),Color("234048"))
		draw_rect(Rect2(origin,extent),CYAN,false,1)
		var factor := 2.54 if centimeters else 1.0
		var unit := "cm" if centimeters else "in"
		draw_string(FONT,Vector2(origin.x,origin.y-8),"%s %s" % [TableSizeDialog.number(inches.x*factor),unit],HORIZONTAL_ALIGNMENT_CENTER,extent.x,11,MUTED)
		draw_string(FONT,Vector2(origin.x+extent.x+8,origin.y+extent.y*0.5+4),"%s %s" % [TableSizeDialog.number(inches.y*factor),unit],HORIZONTAL_ALIGNMENT_LEFT,65,11,MUTED)


func _ready() -> void:
	title = "Prepare your table"
	borderless = true
	unresizable = true
	exclusive = true
	transient = true
	close_requested.connect(_on_close)
	_build_ui()
	size_changed.connect(_layout)
	get_tree().root.size_changed.connect(_fit_host)
	visibility_changed.connect(func() -> void:
		if visible:
			_fit_host()
			_back.grab_focus.call_deferred())
	_fit_host()
	_sync_inputs()
	_refresh()


func _fit_host() -> void:
	var root := get_tree().root
	# Compensate the 1920px canvas shrink while preserving the user's UI scale. Only the shrink: on
	# windows above 1080p the chooser grows with the canvas like the rest of the UI (1440p, ultrawide).
	content_scale_factor = maxf(1.0,root.content_scale_factor / maxf(0.1,root.get_final_transform().get_scale().x))
	size = Vector2i(root.get_visible_rect().size)
	position = Vector2i.ZERO
	_layout()


func _build_ui() -> void:
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel",_box(Color("0b1116"),Color.TRANSPARENT))
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(_margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation",24)
	_scroll.add_child(_page)
	_header = BoxContainer.new()
	_page.add_child(_header)
	var wordmark := HBoxContainer.new()
	wordmark.add_theme_constant_override("separation",0)
	_header.add_child(wordmark)
	var brand := _label("NIEMANDS",27)
	brand.add_theme_font_override("font",LOGO)
	wordmark.add_child(brand)
	var land := _label("LAND",27,CYAN)
	land.add_theme_font_override("font",LOGO)
	wordmark.add_child(land)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)
	_back = _button("←  Back to main menu")
	_back.flat = true
	_back.pressed.connect(_on_close)
	_header.add_child(_back)
	var intro := VBoxContainer.new()
	intro.add_theme_constant_override("separation",8)
	_page.add_child(intro)
	intro.add_child(_label("Prepare your table.",34))
	intro.add_child(_label("Choose the setting and the space. Build the battlefield your way.",13,MUTED,true))
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation",36)
	_page.add_child(_columns)
	var left := VBoxContainer.new()
	_left = left
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1
	left.add_theme_constant_override("separation",14)
	_columns.add_child(left)
	left.add_child(_label("01   Choose a biome",17))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation",10)
	_grid.add_theme_constant_override("v_separation",10)
	left.add_child(_grid)
	for key in BIOMES:
		var button := _button("")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = BIOMES[key][0]
		button.text = BIOMES[key][0]
		button.set_meta("visual_card",true)
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_theme_constant_override("separation",0)
		button.add_child(stack)
		var photo := _image(key)
		photo.custom_minimum_size.y = 76
		stack.add_child(photo)
		_cards.append(photo)
		var label := _label(BIOMES[key][0],12)
		label.custom_minimum_size.y = 30
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(label)
		button.pressed.connect(_select_biome.bind(key))
		_grid.add_child(button)
		_biome_buttons[key] = button
	var size_header := HBoxContainer.new()
	left.add_child(size_header)
	var size_title := _label("02   Set the table size",17)
	size_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_header.add_child(size_title)
	_unit_option = OptionButton.new()
	_unit_option.add_item("Inches")
	_unit_option.add_item("Centimeters")
	_unit_option.add_theme_font_override("font",FONT)
	_unit_option.add_theme_font_size_override("font_size",12)
	_unit_option.item_selected.connect(_on_units_changed)
	size_header.add_child(_unit_option)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation",10)
	left.add_child(presets)
	for spec in [["standard","Standard","6 × 4 ft"],["square","Square","4 × 4 ft"],["custom","Custom","Set width & depth"]]:
		var button := _button("")
		button.text = spec[1]
		button.set_meta("visual_card",true)
		button.custom_minimum_size.y = 76
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 12
		column.offset_top = 9
		column.offset_right = -8
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(column)
		column.add_child(_label(spec[1],11,MUTED))
		var value := _label("Your dimensions",13)
		column.add_child(value)
		column.add_child(_label(spec[2],10,MUTED))
		_size_labels[spec[0]] = value
		button.pressed.connect(_select_size.bind(spec[0]))
		presets.add_child(button)
		_size_buttons[spec[0]] = button
	_custom = HBoxContainer.new()
	_custom.add_theme_constant_override("separation",12)
	left.add_child(_custom)
	for title_value in ["Width","Depth"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_custom.add_child(column)
		var caption := _label(title_value+" (in)",12,MUTED)
		column.add_child(caption)
		_unit_labels.append(caption)
		var input := LineEdit.new()
		input.add_theme_font_override("font",FONT)
		input.custom_minimum_size.y = 38
		input.text_changed.connect(_on_dimensions_edited)
		column.add_child(input)
		if title_value == "Width":
			_width_input = input
		else:
			_length_input = input
	_error = _label("",12,Color("eab2a2"),true)
	left.add_child(_error)
	left.add_child(_label("Table size is fixed once you create it.",11,MUTED))
	left.add_child(HSeparator.new())
	left.add_child(_label("+   Your terrain. Your layout.",14,CYAN))
	left.add_child(_label("Place and rearrange terrain freely after creating your table. The biome defines its visual style.",12,MUTED,true))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.2
	right.add_theme_constant_override("separation",12)
	_columns.add_child(right)
	_hero = Control.new()
	_hero.custom_minimum_size.y = 370
	right.add_child(_hero)
	_preview = _image(selected_biome)
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero.add_child(_preview)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0,Color(0.03,0.05,0.07,0))
	gradient.set_color(1,Color(0.03,0.05,0.07,0.96))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0,0)
	texture.fill_to = Vector2(0,1)
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(shade)
	var tag := _label("BIOME REFERENCE · EXAMPLE ARRANGEMENT",10)
	tag.position = Vector2(20,18)
	_hero.add_child(tag)
	var caption := VBoxContainer.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 24
	caption.offset_right = -24
	caption.offset_top = -92
	caption.offset_bottom = -16
	_hero.add_child(caption)
	_preview_title = _label("",29)
	caption.add_child(_preview_title)
	_preview_description = _label("",12,MUTED,true)
	caption.add_child(_preview_description)
	right.add_child(_label("Example terrain arrangement. Your layout is up to you.",11,MUTED,true))
	right.add_child(HSeparator.new())
	var footprint_row := HBoxContainer.new()
	right.add_child(footprint_row)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footprint_row.add_child(details)
	details.add_child(_label("TABLE FOOTPRINT",10,CYAN))
	_feet_label = _label("",21)
	details.add_child(_feet_label)
	_secondary_size = _label("",12,MUTED)
	details.add_child(_secondary_size)
	_footprint = Footprint.new()
	_footprint.custom_minimum_size = Vector2(240,110)
	_footprint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footprint.resized.connect(_footprint.queue_redraw)
	footprint_row.add_child(_footprint)
	_page.add_child(HSeparator.new())
	_footer = BoxContainer.new()
	_page.add_child(_footer)
	var summary_column := VBoxContainer.new()
	summary_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(summary_column)
	summary_column.add_child(_label("YOUR TABLE",10,MUTED))
	_summary = _label("",16)
	summary_column.add_child(_summary)
	_create = _button("Create table     →")
	_create.custom_minimum_size = Vector2(230,50)
	_create.pressed.connect(_confirm)
	_footer.add_child(_create)
	_style(_create,true,true)


func set_biomes(keys: Array, current: String) -> void:
	_biome_keys = keys.map(func(key: Variant) -> String: return table_biome(str(key))) \
		.filter(func(key: String) -> bool: return BIOMES.has(key))
	current = table_biome(current)
	selected_biome = current if current in _biome_keys else str(_biome_keys[0]) if not _biome_keys.is_empty() else ""
	if is_node_ready():
		_refresh()


func _select_biome(key: String) -> void:
	if key in _biome_keys:
		selected_biome = key
		_refresh()


func _select_size(key: String) -> void:
	if key not in ["standard","square","custom"]:
		return
	selected_size = key
	_refresh()


func _on_units_changed(_index: int) -> void:
	_sync_inputs()
	_refresh()


func _sync_inputs() -> void:
	var factor := 2.54 if _unit_option.selected == 1 else 1.0
	_width_input.text = _editable_number(custom_inches.x*factor)
	_length_input.text = _editable_number(custom_inches.y*factor)
	var unit := "cm" if _unit_option.selected == 1 else "in"
	_unit_labels[0].text = "Width ("+unit+")"
	_unit_labels[1].text = "Depth ("+unit+")"


func _on_dimensions_edited(_text: String) -> void:
	var factor := 2.54 if _unit_option.selected == 1 else 1.0
	custom_inches = Vector2(_parse_dimension(_width_input.text)/factor,_parse_dimension(_length_input.text)/factor)
	_refresh()


static func _parse_dimension(value: String) -> float:
	var normalized := value.strip_edges().replace(",",".")
	return normalized.to_float() if normalized.is_valid_float() else NAN


static func _editable_number(value: float) -> String:
	return ("%.4f" % value).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".") if is_finite(value) else ""


static func number(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


func chosen_inches() -> Vector2:
	return Vector2(72,48) if selected_size == "standard" else Vector2(48,48) if selected_size == "square" else custom_inches


static func valid_dimensions(inches: Vector2) -> bool:
	return is_finite(inches.x) and is_finite(inches.y) and inches.x >= 12-0.0001 and inches.y >= 12-0.0001 and inches.x <= 240+0.0001 and inches.y <= 240+0.0001


func _size_text(inches: Vector2) -> String:
	var factor := 2.54 if _unit_option.selected == 1 else 1.0
	return "%s × %s %s" % [number(inches.x*factor),number(inches.y*factor),"cm" if factor > 1 else "in"]


func _refresh() -> void:
	for key in _biome_buttons:
		_biome_buttons[key].visible = key in _biome_keys
		_style(_biome_buttons[key],key == selected_biome)
	for key in _size_buttons:
		_style(_size_buttons[key],key == selected_size)
	_size_labels.standard.text = _size_text(Vector2(72,48))
	_size_labels.square.text = _size_text(Vector2(48,48))
	_custom.visible = selected_size == "custom"
	var inches := chosen_inches()
	_valid = valid_dimensions(inches) and selected_biome in _biome_keys
	_create.disabled = not _valid or _emitted
	_error.visible = not _valid
	_error.text = "Enter width and depth from 30.48 to 609.6 cm." if _unit_option.selected == 1 else "Enter width and depth from 12 to 240 in."
	_summary.text = "%s · %s" % [BIOMES.get(selected_biome,["Choose a biome"])[0],_size_text(inches) if _valid else "Choose valid dimensions"]
	if BIOMES.has(selected_biome):
		_preview.texture = load(_preview_path(selected_biome))
		_preview_title.text = BIOMES[selected_biome][0]
		_preview_description.text = BIOMES[selected_biome][1]
	if _valid:
		_feet_label.text = "%s × %s ft" % [number(inches.x/12),number(inches.y/12)]
		_secondary_size.text = "%s × %s cm" % [number(inches.x*2.54),number(inches.y*2.54)] if _unit_option.selected == 0 else "%s × %s in" % [number(inches.x),number(inches.y)]
		_footprint.inches = inches
		_footprint.centimeters = _unit_option.selected == 1
		_footprint.queue_redraw()
	_footprint.modulate.a = 1.0 if _valid else 0.25
	_layout()


func _confirm() -> void:
	if _emitted or not _valid:
		return
	_emitted = true
	_create.disabled = true
	size_chosen.emit(chosen_inches()/12.0)


func _on_close() -> void:
	if _emitted:
		return
	_emitted = true
	hide()
	cancelled.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if not is_instance_valid(_margin):
		return
	var area := get_visible_rect().size
	var compact := area.y <= 800
	var narrow := area.x < 900
	# The page is a centred column no wider than PAGE_ASPECT x the height (the 1080p page is 1768 px wide),
	# so wide windows keep the 16:9 proportions of cards and preview instead of stretching them.
	var padding := maxi(maxi(20,int(area.x*0.04)),int((area.x-area.y*PAGE_ASPECT)*0.5))
	_header.vertical = area.x < 560
	_footer.vertical = narrow
	for side in ["left","right"]:
		_margin.add_theme_constant_override("margin_"+side,padding)
	for side in ["top","bottom"]:
		_margin.add_theme_constant_override("margin_"+side,20 if compact else 36)
	_page.add_theme_constant_override("separation",12 if compact else 24)
	_left.add_theme_constant_override("separation",11 if compact else 14)
	_columns.vertical = narrow
	_columns.add_theme_constant_override("separation",24 if compact else 36)
	_grid.columns = 2 if area.x < 560 else 3
	for photo in _cards:
		photo.custom_minimum_size.y = 46 if compact else 76
	for button in _biome_buttons.values():
		button.custom_minimum_size.y = 76 if compact else 106
	_hero.custom_minimum_size.y = 250 if compact else 370


func _label(value: String, font_size: int, color := INK, wrap := false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_override("font",FONT)
	button.add_theme_font_size_override("font_size",14)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style(button,false)
	return button


func _style(button: Button, selected: bool, primary := false) -> void:
	for state in ["normal","hover","pressed","focus"]:
		var color := GOLD if primary else Color("253035") if selected else Color("142027")
		if state == "hover":
			color = Color("ebd19a") if primary else Color("293b43")
		button.add_theme_stylebox_override(state,_box(color,GOLD if selected or state == "focus" else Color("334047")))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state,Color.TRANSPARENT if button.has_meta("visual_card") else Color("192125") if primary else INK)


func _box(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 10
	box.content_margin_right = 10
	return box


## A menu or table biome id -> the table's id (what table.set_biome accepts).
static func table_biome(key: String) -> String:
	return MENU_TO_TABLE.get(key,key)


func _preview_path(key: String) -> String:
	return "res://assets/ui/table_setup/"+str(PREVIEW_FILE.get(key,key))+".webp"


func _image(key: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load(_preview_path(key))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
