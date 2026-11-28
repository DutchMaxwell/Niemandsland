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
## Spare window height grows the preview and the biome cards only down to these proportions.
const HERO_MIN_ASPECT := 2.2
const RAIL_HERO_ASPECT := 1.6   # the rail card's picture may grow to sheet 03's 594 x 372
const RAIL_MIN_H := 900.0
const SIX_MIN_W := 1000.0   # a left column this wide shows the six biomes in one row (step 83, sheet 03)
const SIX_PHOTO_H := 150.0
const SIX_BAND_H := 44.0
const SIX_MIN_ASPECT := 0.6   # a card of the one-row form grows up to 0.6 : 1 to fill the left column   # from this window height the right column is the rail card (sheet 03)
const CARD_MIN_ASPECT := 2.0
const CARD_MAX_ASPECT := 2.8
const FONT = preload("res://assets/ui_glassmorphism/fonts/Inter.ttf")
const MenuView = preload("res://scripts/startup_menu_view.gd")
const LOGO = preload("res://assets/ui_glassmorphism/fonts/Orbitron.ttf")
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
## The game system the table is set up for (GameSystem.IDS): it filters the biomes on offer (assets/terrain_systems.json).
var selected_system := GameSystem.DEFAULT_ID
var selected_size := "standard"
var custom_inches := Vector2(72,48)
var _biome_keys: Array = BIOMES.keys()
var _emitted := false
var _unit_option: OptionButton   # hidden twin of the segment pair: holds the unit (0 = in, 1 = cm)
var _unit_segments: HBoxContainer   # Inches | Centimeters
var _width_input: LineEdit
var _length_input: LineEdit
var _biome_buttons: Dictionary = {}
var _system_option: OptionButton   # hidden twin of the system cards (item index = index into GameSystem.IDS)
var _system_buttons: Dictionary = {}   # GameSystem id -> its card in step 01
var _system_step: BoxContainer   # heading over the cards; one line below 800 px window height
var _intro_line: Label           # the intro's second line; hidden below 800 px so the page fits without scrolling
var _title_row: BoxContainer
var _size_buttons: Dictionary = {}
var _size_labels: Dictionary = {}
var _custom: HBoxContainer
var _error: Label
var _summary: Dictionary = {}   # "System" / "Biome" / "Size" -> its value in the summary row above Create table
var _create: Button
var _back: Button
var _back_wide: HBoxContainer   # from 900 px: a bordered "Back to main menu" with its Esc cap (step 84)
var _wide_only: Array[Control] = []   # the breadcrumb and the eyebrow "NEW TABLE": shown from 900 px only
var _intro: VBoxContainer
var _headings: Array = []    # [number, name, hint] of each step heading (step 84: 22 px, mono number, hint at the right)
var _size_texts: Array = []  # [caption, value, sub-line] of each size card
var _system_parts: Dictionary = {}   # id -> [column, family, name, tag line, chip row, tick] of each system card (step 84)
var _size_note: Label        # "Table size is fixed once you create it." under the cards; the heading's hint from 900 px
var _title: Label
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
var _left_air: Array[Control] = []
var _right: VBoxContainer
var _rail_card: PanelContainer   # the right column; from 900 px of window height the framed rail card of sheet 03
var _rail_body: VBoxContainer    # the card's last part: the summary rows and Create table (rail form only)
var _foot_margin: MarginContainer
var _summary_column: VBoxContainer
var _summary_rows: BoxContainer
var _right_note: Array[Control] = []   # the example line and its rule under the picture (not in the rail form)
var _columns: BoxContainer
var _grid: GridContainer
var _hero: Control
var _margin: MarginContainer
var _cards: Array[TextureRect] = []
var _card_names: Array[Label] = []
var _valid := true
var online := false:   # an online room locks the rules pick to Manual; it follows the card of step 04
	set(value):
		online = value
		if online and selected_rules == RulesAutomation.Level.AUTOMATIC:
			selected_rules = RulesAutomation.default_pick(true)
var layout_step := false   # set before add_child: the menu's setup has step 04 (the table's chooser does not)
var layout: SetupLayout
var _step04: Control   # the inner page: who is at the table (step 04) or the layout (step 05)
var _layout_name: Label
var opponent: SetupOpponent
var _opponent_name: Label
var _opponent_key: Label
var selected_rules := RulesAutomation.Level.MANUAL

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
		draw_rect(Rect2(origin,extent),HouseStyle.ACCENT,false,1)
		var factor := 2.54 if centimeters else 1.0
		var unit := "cm" if centimeters else "in"
		draw_string(FONT,Vector2(origin.x,origin.y-8),"%s %s" % [TableSizeDialog.number(inches.x*factor),unit],HORIZONTAL_ALIGNMENT_CENTER,extent.x,11,HouseStyle.MUTED)
		draw_string(FONT,Vector2(origin.x+extent.x+8,origin.y+extent.y*0.5+4),"%s %s" % [TableSizeDialog.number(inches.y*factor),unit],HORIZONTAL_ALIGNMENT_LEFT,65,11,HouseStyle.MUTED)


func _ready() -> void:
	title = "Prepare your table"
	selected_rules = RulesAutomation.default_pick(online)
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
			(_back if _back.visible else _back_wide.get_child(0) as Button).grab_focus.call_deferred())
	_fit_host()
	_sync_inputs()
	set_system(selected_system)   # the row's pick (default gf) filters the biomes and preselects the size
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
	var land := _label("LAND",27,HouseStyle.ACCENT)
	land.add_theme_font_override("font",LOGO)
	wordmark.add_child(land)
	var crumb := _label("    MAIN MENU  /  PREPARE YOUR TABLE",14,HouseStyle.MUTED)
	crumb.add_theme_font_override("font",HouseStyle.mono())
	crumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(crumb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)
	_back = _button("←  Back to main menu")
	_back.flat = true
	_back.pressed.connect(_on_close)
	_header.add_child(_back)
	_back_wide = HBoxContainer.new()
	_back_wide.theme = HouseStyle.menu_theme()
	_back_wide.add_theme_constant_override("separation",HouseStyle.GAP_ROW)
	var back := HouseStyle.button("Back to main menu",HouseStyle.BUTTON,HouseStyle.MENU_H_ACTION)
	back.name = "BackWide"
	back.focus_mode = Control.FOCUS_ALL
	back.icon = HouseStyle.svg_icon(MenuView.ICON_SVG % "<path d='M15 5l-7 7 7 7'/>")
	back.add_theme_constant_override("icon_max_width",16)
	back.pressed.connect(_on_close)
	_back_wide.add_child(back)
	_back_wide.add_child(HouseStyle.key_cap("Esc"))
	_header.add_child(_back_wide)
	var intro := VBoxContainer.new()
	_intro = intro
	intro.add_theme_constant_override("separation",8)
	_page.add_child(intro)
	var eyebrow := _label("NEW TABLE",HouseStyle.MENU_FONT_EYEBROW,HouseStyle.ACCENT)
	eyebrow.add_theme_font_override("font",HouseStyle.eyebrow_font())
	intro.add_child(eyebrow)
	_wide_only = [crumb,eyebrow]
	_title_row = BoxContainer.new()   # the first row of the setup: the game system sits on the title line, so it costs no height
	intro.add_child(_title_row)
	var title := _label("Prepare your table.",34)
	_title = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_row.add_child(title)
	var system_caption := _label("Game system",12,HouseStyle.MUTED)
	system_caption.visible = false   # step 01 below is the visible switch; the dropdown stays as its hidden twin
	system_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_row.add_child(system_caption)
	_system_option = OptionButton.new()
	_system_option.name = "SystemOption"
	_system_option.tooltip_text = "Sets the terrain on offer, the table size it starts on and the army lists the table accepts."
	_system_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_system_option.visible = false
	for id in GameSystem.IDS:
		_system_option.add_item(GameSystem.label(id))
	_system_option.add_theme_font_override("font",FONT)
	_system_option.add_theme_font_size_override("font_size",13)
	_system_option.item_selected.connect(func(index: int) -> void: set_system(GameSystem.IDS[index]))
	_title_row.add_child(_system_option)
	_intro_line = _label("Choose the setting and the space. Build the battlefield your way.",13,HouseStyle.MUTED,true)
	intro.add_child(_intro_line)
	_add_system_cards()
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation",36)
	_page.add_child(_columns)
	var left := VBoxContainer.new()
	_left = left
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1
	left.add_theme_constant_override("separation",14)
	_columns.add_child(left)
	left.add_child(_step_heading("02","Choose a biome","The biome defines the visual style. Terrain stays yours to place."))
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
		photo.size_flags_vertical = Control.SIZE_EXPAND_FILL   # a card grown by _fill_height grows its photo
		stack.add_child(photo)
		_cards.append(photo)
		var label := _label(BIOMES[key][0],12)
		label.custom_minimum_size.y = 30
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(label)
		_card_names.append(label)
		button.pressed.connect(_select_biome.bind(key))
		_grid.add_child(button)
		_biome_buttons[key] = button
	_add_left_air(left)
	var size_header := HBoxContainer.new()
	left.add_child(size_header)
	var size_title := _step_heading("03","Set the table size","Table size is fixed once you create it.")
	size_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_header.add_child(size_title)
	_unit_option = OptionButton.new()
	_unit_option.add_item("Inches")
	_unit_option.add_item("Centimeters")
	_unit_option.add_theme_font_override("font",FONT)
	_unit_option.add_theme_font_size_override("font_size",12)
	_unit_option.item_selected.connect(_on_units_changed)
	_unit_option.visible = false
	size_header.add_child(_unit_option)
	_unit_segments = HouseStyle.button_row(["Inches","Centimeters"],HouseStyle.SEGMENT,HouseStyle.H_CHIP)
	_unit_segments.theme = HouseStyle.theme()
	_unit_segments.size_flags_horizontal = Control.SIZE_SHRINK_END
	for i in 2:
		var segment := _unit_segments.get_child(i) as Button
		segment.focus_mode = Control.FOCUS_ALL   # reachable by keyboard, as the dropdown was
		segment.pressed.connect(func() -> void:
			_unit_option.select(i)
			_on_units_changed(i))
	size_header.add_child(_unit_segments)
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
		var texts := [_label(spec[1],11,HouseStyle.MUTED),_label("Your dimensions",13),_label(spec[2],10,HouseStyle.MUTED)]
		for text in texts:
			column.add_child(text)
		_size_texts.append(texts)
		var value: Label = texts[1]
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
		var caption := _label(title_value+" (in)",12,HouseStyle.MUTED)
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
	_size_note = _label("Table size is fixed once you create it.",11,HouseStyle.MUTED)
	left.add_child(_size_note)
	_add_left_air(left)
	left.add_child(HSeparator.new())
	if layout_step:
		_add_opponent_row(left)
		_add_layout_row(left)
	else:
		left.add_child(_label("+   Your terrain. Your layout.",14,HouseStyle.ACCENT))
		left.add_child(_label("Place and rearrange terrain freely after creating your table. The biome defines its visual style.",12,HouseStyle.MUTED,true))
	_add_left_air(left)   # a third share of the slack beside the rail card (16:10)
	_rail_card = PanelContainer.new()
	_rail_card.name = "RailCard"
	_rail_card.clip_contents = true
	_rail_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_card.size_flags_stretch_ratio = 1.2
	_columns.add_child(_rail_card)
	var right := VBoxContainer.new()
	_right = right
	right.add_theme_constant_override("separation",12)
	_rail_card.add_child(right)
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
	_preview_description = _label("",12,HouseStyle.MUTED,true)
	caption.add_child(_preview_description)
	_right_note = [_label("Example terrain arrangement. Your layout is up to you.",11,HouseStyle.MUTED,true),HSeparator.new()]
	for note in _right_note:
		right.add_child(note)
	_foot_margin = MarginContainer.new()
	_foot_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL   # takes the right column's slack
	right.add_child(_foot_margin)
	var footprint_row := HBoxContainer.new()
	_foot_margin.add_child(footprint_row)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footprint_row.add_child(details)
	details.add_child(_label("TABLE FOOTPRINT",10,HouseStyle.ACCENT))
	_feet_label = _label("",21)
	details.add_child(_feet_label)
	_secondary_size = _label("",12,HouseStyle.MUTED)
	details.add_child(_secondary_size)
	_footprint = Footprint.new()
	_footprint.custom_minimum_size = Vector2(240,110)
	_footprint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footprint.resized.connect(_footprint.queue_redraw)
	footprint_row.add_child(_footprint)
	_rail_body = VBoxContainer.new()
	_rail_body.add_theme_constant_override("separation",18)
	right.add_child(_rail_body)
	var slot := MarginContainer.new()   # Create table in the card, 24 px from its edges
	slot.name = "CreateSlot"
	for side in ["left","right","bottom"]:
		slot.add_theme_constant_override("margin_"+side,24)
	_rail_body.add_child(slot)
	_page.add_child(HSeparator.new())
	_footer = BoxContainer.new()
	_page.add_child(_footer)
	var summary_column := VBoxContainer.new()
	_summary_column = summary_column
	summary_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(summary_column)
	summary_column.add_child(_label("YOUR TABLE",10,HouseStyle.MUTED))
	var rows := BoxContainer.new()   # System / Biome / Size on one line, so the 720 page keeps its height; rows in the rail
	_summary_rows = rows
	rows.add_theme_constant_override("separation",10)
	summary_column.add_child(rows)
	for row: String in ["System","Biome","Size"] + (["Opponent"] if opponent != null else []):
		var pair := PanelContainer.new()   # a hairline under it in the rail card
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation",10)
		pair.add_child(line)
		rows.add_child(pair)
		var row_name := _label(row,12,HouseStyle.MUTED)
		row_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_name.set_meta("caption",row)
		line.add_child(row_name)
		_summary[row] = _label("",16)
		line.add_child(_summary[row])
		if row == "Opponent":
			_opponent_key = row_name
	var keys := HBoxContainer.new()   # the key legend: what the keyboard does on this page
	keys.name = "KeyLegend"
	keys.theme = HouseStyle.theme()
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keys.add_theme_constant_override("separation",HouseStyle.GAP_CONTROL)
	_footer.add_child(keys)
	for pair: Array in [["Tab","next step"],["← →","choose"],["Enter","create table"],["Esc","back"]]:
		keys.add_child(HouseStyle.label(pair[0],HouseStyle.KEYCAP))
		keys.add_child(_label(pair[1]+"   ",12,HouseStyle.MUTED))
	_create = _button("Create table     →")
	var cap := HouseStyle.key_cap_on_gold("Enter")   # shown in the rail card only
	cap.name = "EnterCap"
	cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cap.offset_left = -16
	cap.offset_right = -16
	cap.visible = false
	_create.add_child(cap)
	_create.custom_minimum_size = Vector2(230,50)
	_create.pressed.connect(_confirm)
	_footer.add_child(_create)
	_style(_create,true,true)


## Step 04 in the setup's first state: one row "04 Lay out the table", the chosen way's name and Change; it opens
## the second state, the page of the four ways (SetupLayoutStep).
func _add_layout_row(column: VBoxContainer) -> void:
	layout = SetupLayout.new()
	add_child(layout)
	var row := _button("")
	row.name = "LayoutRow"
	row.custom_minimum_size.y = 52
	row.pressed.connect(_show_state.bind("layout"))
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := _label("05   Lay out the table",17)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(heading)
	_layout_name = _label("",16)
	line.add_child(_layout_name)
	line.add_child(_label("   Change",15,HouseStyle.ACCENT))
	row.add_child(line)
	column.add_child(row)


## Step 04 in the setup's first state: "04 Who is at the table?", the opponent's name and Change; it opens the
## "who" page (SetupOpponentStep).
func _add_opponent_row(column: VBoxContainer) -> void:
	opponent = SetupOpponent.new()
	var row := _button("")
	row.name = "OpponentRow"
	row.custom_minimum_size.y = 52
	row.pressed.connect(_show_state.bind("who"))
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_label("04   Who is at the table?",17))
	_opponent_name = _label("",16)   # takes the room the heading and Change leave, cut with an ellipsis (720p)
	_opponent_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opponent_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_opponent_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_opponent_name.clip_text = true
	line.add_child(_opponent_name)
	line.add_child(_label("   Change",15,HouseStyle.ACCENT))
	row.add_child(line)
	column.add_child(row)
	opponent.changed.connect(func() -> void:
		online = opponent.who == "online"
		_opponent_name.text = opponent.label()
		if _summary.has("Opponent"):
			_summary.Opponent.text = opponent.label())


## The inner pages: "who" (step 04) or "layout" (step 05) in place of steps 01-03 and the summary; "" is state one.
## Change on a folded row returns to state one, except row 04 of the layout page (the who page) and the who page's
## row 05 (the layout page).
func _show_state(state: String) -> void:
	for part: Control in [_system_step, _columns, _footer, _page.get_child(_footer.get_index() - 1)]:
		part.visible = state.is_empty()
	if is_instance_valid(_step04):
		_step04.queue_free()
	_layout()   # the title block follows: in the left column in state one, over an inner page otherwise
	if state.is_empty():
		return
	var values := [_summary.System.text, _summary.Biome.text, _summary.Size.text]
	_step04 = SetupLayoutStep.new() if state == "layout" else SetupOpponentStep.new()
	_step04.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_child(0).add_child(_step04)
	_step04.connect("create_requested", _confirm)
	if state == "layout":
		_step04.call("setup", layout, values + [opponent.label()])
		_step04.connect("change_requested", func(step: int) -> void: _show_state("who" if step == 4 else ""))
	else:
		_step04.call("setup", opponent, values + [layout.label()])
		_step04.connect("change_requested", func(_step: int) -> void: _show_state(""))
		_step04.connect("layout_requested", _show_state.bind("layout"))


## Step 01 of the setup: one card per game system (its name, Battle or Skirmish, the board it starts on).
func _add_system_cards() -> void:
	var step := BoxContainer.new()
	step.vertical = true
	step.add_theme_constant_override("separation",10)
	_page.add_child(step)
	_system_step = step
	var heading := _step_heading("01","Choose a game system",
		"Sets the terrain on offer, the starting table size and the army lists the table accepts.")
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	step.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step.add_child(row)
	for id: String in GameSystem.IDS:
		var button := _button(GameSystem.label(id))
		button.set_meta("visual_card",true)
		button.custom_minimum_size.y = 64
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 12
		column.alignment = BoxContainer.ALIGNMENT_CENTER   # name and tag centred at either card height
		column.offset_right = -8
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(column)
		var family := _label("GRIMDARK" if id.begins_with("gf") else "FANTASY",13,HouseStyle.MUTED)
		column.add_child(family)
		var system_name := _label(GameSystem.label(id),14)
		column.add_child(system_name)
		var board := GameSystem.default_board_feet(id)
		var tag := "Skirmish" if GameSystem.scale(id) == GameSystem.SCALE_SKIRMISH else "Battle"
		var tag_line := _label("%s  ·  %d × %d ft" % [tag,board.x,board.y],11,HouseStyle.MUTED)
		column.add_child(tag_line)
		var chips := HBoxContainer.new()   # from 900 px: a BATTLE / SKIRMISH chip and the board in mono (sheet 03)
		chips.add_theme_constant_override("separation",8)
		chips.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END   # at the card's foot
		var chip := PanelContainer.new()
		var chip_box := _box(Color.TRANSPARENT,HouseStyle.LINE)
		chip_box.content_margin_left = 7
		chip_box.content_margin_right = 7
		chip.add_theme_stylebox_override("panel",chip_box)
		chip.add_child(_label(tag.to_upper(),12,HouseStyle.MUTED))
		chips.add_child(chip)
		chips.add_child(_label("%d × %d FT" % [board.x,board.y],13,HouseStyle.MUTED))
		for text: Label in [chip.get_child(0),chips.get_child(1)]:
			text.add_theme_font_override("font",HouseStyle.mono())
		column.add_child(chips)
		var tick := TextureRect.new()   # the chosen card's gold tick, top right
		tick.texture = HouseStyle.svg_icon(MenuView.ICON_SVG % SetupLayoutStep.TICK)
		tick.modulate = HouseStyle.GOLD
		tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tick.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tick.offset_left = -34
		tick.offset_top = 12
		tick.offset_right = -12
		tick.offset_bottom = 34
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(tick)
		_system_parts[id] = [column,family,system_name,tag_line,chips,tick]
		button.pressed.connect(func() -> void: set_system(id))
		row.add_child(button)
		_system_buttons[id] = button


## The pick a fresh table starts on; the visible switch is the in-game rules chip/toggle (step 2.10),
## not a chooser section — the chooser renders exactly as it did before the flip.
func _select_rules(level: int) -> void:
	if online and level == RulesAutomation.Level.AUTOMATIC:
		return
	selected_rules = level
	if is_node_ready():
		_refresh()


## An expanding gap in the left column: when the right column grew taller, the left column's slack is
## shared between the biome cards, the size step and the note instead of one hole at its bottom.
func _add_left_air(column: VBoxContainer) -> void:
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(air)
	_left_air.append(air)


func set_biomes(keys: Array, current: String) -> void:
	_biome_keys = keys.map(func(key: Variant) -> String: return table_biome(str(key))) \
		.filter(func(key: String) -> bool: return BIOMES.has(key))
	_pick_biome(table_biome(current))


## The biomes on offer: what the caller listed, minus the ones the selected game system does not offer.
func _shown_biomes() -> Array:
	return _biome_keys.filter(func(key: String) -> bool: return GameSystem.offers("biome", key, selected_system))


## Selects `current`, or the first biome on offer when it is not on offer (a hidden biome is never selected).
func _pick_biome(current: String) -> void:
	var shown := _shown_biomes()
	selected_biome = current if current in shown else str(shown[0]) if not shown.is_empty() else ""
	if is_node_ready():
		_refresh()


## Sets the game system the table is for; the biomes it does not offer disappear (the selection falls back if it was one)
## and the size starts on the system's own board: 4 x 4 ft for the skirmish books, 6 x 4 ft otherwise. Only a PRESELECT:
## a size picked afterwards wins.
func set_system(id: String) -> void:
	selected_system = GameSystem.normalize(id)
	selected_size = "square" if GameSystem.default_board_feet(selected_system) == Vector2i(4, 4) else "standard"
	_pick_biome(selected_biome)


func _select_biome(key: String) -> void:
	if key in _shown_biomes():
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
	var shown := _shown_biomes()
	_system_option.select(GameSystem.IDS.find(selected_system))
	for id in _system_buttons:
		_style(_system_buttons[id],id == selected_system)
		_system_parts[id][5].visible = _rail_body.visible and id == selected_system
	for key in _biome_buttons:
		_biome_buttons[key].visible = key in shown
		_style(_biome_buttons[key],key == selected_biome)
	for key in _size_buttons:
		_style(_size_buttons[key],key == selected_size)
	for i in 2:
		HouseStyle.set_selected(_unit_segments.get_child(i) as Button,i == _unit_option.selected)
	_size_labels.standard.text = _size_text(Vector2(72,48))
	_size_labels.square.text = _size_text(Vector2(48,48))
	_custom.visible = selected_size == "custom"
	var inches := chosen_inches()
	_valid = valid_dimensions(inches) and selected_biome in shown
	_create.disabled = not _valid or _emitted
	_error.visible = not _valid
	_error.text = "Enter width and depth from 30.48 to 609.6 cm." if _unit_option.selected == 1 else "Enter width and depth from 12 to 240 in."
	_summary.System.text = GameSystem.label(selected_system)
	_summary.Biome.text = BIOMES.get(selected_biome,["Choose a biome"])[0]
	_summary.Size.text = _size_text(inches) if valid_dimensions(inches) else "Choose valid dimensions"
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
	if layout != null and _valid:
		layout.set_table(inches / 12.0, selected_system)
		_layout_name.text = layout.label()
	if opponent != null:
		opponent.set_system(selected_system)   # refills NACHTMAHR's factions; writes both labels (changed)
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
		if is_instance_valid(_step04) and _step04.visible:
			_show_state("")   # Esc: from any inner page back to the first state, from there to the menu
		else:
			_on_close()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		_confirm()   # creates only when the choice is valid
		get_viewport().set_input_as_handled()


func _layout(refill := true) -> void:
	if not is_instance_valid(_margin):
		return
	var area := get_visible_rect().size
	var compact := area.y <= 800
	var narrow := area.x < 900
	# The page is a centred column no wider than PAGE_ASPECT x the height (the 1080p page is 1768 px wide),
	# so wide windows keep the 16:9 proportions of cards and preview instead of stretching them.
	var padding := maxi(maxi(20,int(area.x*0.04)),int((area.x-area.y*PAGE_ASPECT)*0.5))
	_header.vertical = area.x < 560
	_title_row.vertical = area.x < 760
	_footer.vertical = narrow
	for side in ["left","right"]:
		_margin.add_theme_constant_override("margin_"+side,padding)
	for side in ["top","bottom"]:
		_margin.add_theme_constant_override("margin_"+side,20 if compact else 36)
	_page.add_theme_constant_override("separation",8 if compact else 24)
	_left.add_theme_constant_override("separation",11 if compact else 14)
	_columns.vertical = narrow
	_columns.add_theme_constant_override("separation",24 if compact else 36)
	_grid.columns = 2 if area.x < 560 else 3
	var six := _six_biomes()
	for photo in _cards:
		photo.custom_minimum_size.y = SIX_PHOTO_H if six else 24.0   # expands to its card, which _fill_height may make flatter
	for name_label in _card_names:
		name_label.custom_minimum_size.y = SIX_BAND_H if six else 30.0
		name_label.add_theme_font_size_override("font_size",16 if six else 12)
	for button in _biome_buttons.values():
		button.custom_minimum_size.y = 76 if compact else 106
	for button in _system_buttons.values():
		button.custom_minimum_size.y = 38 if compact else 64
	_system_step.vertical = not compact   # below 800 px: the heading shares the cards' line ...
	_intro_line.visible = not compact     # ... and the intro's second line goes, so nothing scrolls at 720
	if _opponent_key != null:   # row 04 names the opponent; the one-line summary has no room for it below 800 px
		_opponent_key.visible = not compact
		_summary.Opponent.visible = not compact
	_hero.custom_minimum_size.y = 250 if compact else 370
	if area.y >= RAIL_MIN_H and not narrow:   # the rail card is narrower: the picture starts at its flattest shape
		_hero.custom_minimum_size.y = floorf(_hero.size.x/2.9) if _hero.size.x > 0 else 200.0
	_footprint.custom_minimum_size.y = 110
	_set_rail(area.y >= RAIL_MIN_H and not narrow)
	_columns.custom_minimum_size.y = 0
	for air in _left_air:
		air.visible = false
	if not narrow:
		_fill_height(area.y-2*(20 if compact else 36),8 if compact else 24)
	# Wrapped labels measure their height at their CURRENT width, which the containers set only after this
	# pass (a 1 px wide label reports ~1500 px): fill once more on the next frame, with every width final.
	if refill and not get_tree().process_frame.is_connected(_layout.bind(false)):
		get_tree().process_frame.connect(_layout.bind(false),CONNECT_ONE_SHOT)


## From 900 px of window height (step 82, sheet 03): the columns stand 1.9 : 1 and the right one is the framed rail
## card - the picture edge to edge, the footprint, the summary as rows (caption in mono upper case left, value right, a
## hairline under each) and Create table full width as its last row; the page footer keeps the key legend only. Below,
## the right column and the footer are as before (the 720 tests decide).
func _set_rail(on: bool) -> void:
	var card := StyleBoxFlat.new()
	card.bg_color = HouseStyle.PANEL
	card.border_color = HouseStyle.LINE_SOFT
	card.set_border_width_all(1)
	card.set_corner_radius_all(HouseStyle.RADIUS_PANEL)
	_rail_card.add_theme_stylebox_override("panel",card if on else StyleBoxEmpty.new())
	_left.size_flags_stretch_ratio = 1.9 if on else 1.0
	_rail_card.size_flags_stretch_ratio = 1.0 if on else 1.2
	for note in _right_note:
		note.visible = not on
	for side in ["left","right"]:
		_foot_margin.add_theme_constant_override("margin_"+side,24 if on else 0)
	_rail_body.visible = on
	# Step 84: the header and the title of sheet 03; the title block and step 01 stand in the left column, so the
	# rail card starts level with the title.
	for node in _wide_only:
		node.visible = on
	_back.visible = not on
	_back_wide.visible = on
	_title.add_theme_font_size_override("font_size",44 if on else 34)
	_title.add_theme_font_override("font",HouseStyle.font(500) if on else FONT)
	_intro_line.add_theme_font_size_override("font_size",17 if on else 13)
	for parts: Array in _headings:
		parts[0].add_theme_font_override("font",HouseStyle.mono() if on else FONT)
		parts[0].add_theme_font_size_override("font_size",15 if on else 17)
		parts[0].add_theme_color_override("font_color",HouseStyle.GOLD if on else HouseStyle.INK)
		parts[1].add_theme_font_size_override("font_size",22 if on else 17)
		parts[1].add_theme_font_override("font",HouseStyle.font(500) if on else FONT)
		parts[2].visible = on
	_size_note.visible = not on
	for texts: Array in _size_texts:
		texts[0].text = texts[0].text.to_upper() if on else texts[0].text.capitalize()
		texts[0].add_theme_font_override("font",HouseStyle.mono() if on else FONT)
		for i in 3:
			texts[i].add_theme_font_size_override("font_size",[14,20,15][i] if on else [11,13,10][i])
	for button in _size_buttons.values():
		button.custom_minimum_size.y = 108 if on else 76
	for id: String in _system_parts:
		var parts: Array = _system_parts[id]
		parts[0].alignment = BoxContainer.ALIGNMENT_BEGIN if on else BoxContainer.ALIGNMENT_CENTER
		parts[0].offset_top = 14 if on else 0
		parts[0].offset_bottom = -14 if on else 0
		for i: int in [1,4]:
			parts[i].visible = on
		parts[3].visible = not on
		parts[5].visible = on and id == selected_system
		parts[2].add_theme_font_size_override("font_size",20 if on else 14)
		parts[2].add_theme_font_override("font",HouseStyle.font(500) if on else FONT)
		parts[2].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if on else TextServer.AUTOWRAP_OFF
		if on:
			_system_buttons[id].custom_minimum_size.y = 136
	for pair: Array in [[_intro,0],[_system_step,1]]:
		var home: Node = _left if on and _columns.visible else _page   # the inner pages keep the title over them
		if pair[0].get_parent() != home:
			pair[0].reparent(home,false)
		home.move_child(pair[0],pair[1] if on else pair[1]+1)
	var slot := _rail_body.get_node("CreateSlot") as Control
	for pair: Array in [[_summary_column,_rail_body if on else _footer],[_create,slot if on else _footer]]:
		if pair[0].get_parent() != pair[1]:
			pair[0].reparent(pair[1],false)
	(_summary_column.get_parent() as Node).move_child(_summary_column,0)
	_summary_column.get_child(0).visible = not on   # "YOUR TABLE": the card says it
	_summary_rows.vertical = on
	_summary_rows.add_theme_constant_override("separation",0 if on else 10)
	for pair: Node in _summary_rows.get_children():
		var line := StyleBoxFlat.new()
		line.bg_color = Color.TRANSPARENT
		line.border_color = Color(HouseStyle.LINE,0.6)
		line.border_width_bottom = 1
		line.content_margin_left = 24
		line.content_margin_right = 24
		line.content_margin_top = 9
		line.content_margin_bottom = 9
		(pair as PanelContainer).add_theme_stylebox_override("panel",line if on else StyleBoxEmpty.new())
		var caption := pair.get_child(0).get_child(0) as Label
		caption.text = str(caption.get_meta("caption")).to_upper() if on else str(caption.get_meta("caption"))
		caption.add_theme_font_override("font",HouseStyle.mono() if on else FONT)
		var value := pair.get_child(0).get_child(1) as Label
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if on else HORIZONTAL_ALIGNMENT_LEFT
	_create.custom_minimum_size = Vector2(0,56) if on else Vector2(230,50)
	# In the card the gold action reads as on sheets 03/03b: "Create table" at 18 px semibold, left, its Enter cap right.
	_create.text = "Create table" if on else "Create table     →"
	_create.alignment = HORIZONTAL_ALIGNMENT_LEFT if on else HORIZONTAL_ALIGNMENT_CENTER
	_create.add_theme_font_size_override("font_size",18 if on else 14)
	_create.add_theme_font_override("font",HouseStyle.font(600) if on else FONT)
	_create.get_node("EnterCap").visible = on
	for state in ["normal","hover","pressed","focus"]:
		var box := _create.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			box.content_margin_left = 22 if on else 10


## The page fills the window height at every aspect: spare height grows the biome cards and the preview
## (each only down to its minimum aspect), then the table footprint (until its drawing is bound by its
## width); what is still left spreads evenly over the gaps between the page sections. Nothing scrolls.
func _fill_height(usable: float, separation: int) -> void:
	# Caps come from the sorted widths; the first pass of a new size (stale widths) is redone next frame.
	# Tall windows: the six cards reflow to 2 x 3 when that fits at 2.8:1, so the left column grows with
	# the preview instead of leaving a hole under the size presets.
	# Cards start at their flattest allowed shape and grow from there, so they also make room (the Custom
	# inputs at 1280x720).
	var buttons := _biome_buttons.values()
	if _six_biomes():   # one row of tall cards (sheet 03): the picture's height is fixed, the rest of the page grows
		_grid.columns = 6
		for button in buttons:
			button.custom_minimum_size.y = SIX_PHOTO_H+SIX_BAND_H
		_grow([_hero],_hero.size.x/RAIL_HERO_ASPECT,usable)   # the card's picture first, then the row takes the rest
		_grow(buttons,(_grid.size.x-50)/6/SIX_MIN_ASPECT,usable)
	for columns: int in ([] if _six_biomes() else [2,3]):
		_grid.columns = columns
		var card_width := (_grid.size.x-10*(columns-1))/columns
		for button in buttons:
			button.custom_minimum_size.y = ceilf(card_width/CARD_MAX_ASPECT)
		if columns == 3 or _page.get_combined_minimum_size().y <= usable:
			_grow(buttons,card_width/CARD_MIN_ASPECT,usable)
			break
	_grow([_hero],_hero.size.x/HERO_MIN_ASPECT,usable)
	# Until the 6 x 4 ft drawing (72 x 48 in plus 90 x 38 px of labels) is bound by the footprint's width.
	_grow([_footprint],(_footprint.size.x-90)/72*48+38,usable)
	if _rail_body.visible:   # the rail card reaches down to the legend: the spare height goes into the columns
		_columns.custom_minimum_size.y = _columns.get_combined_minimum_size().y+maxf(0.0,usable-_page.get_combined_minimum_size().y)
	var slack := _right.get_combined_minimum_size().y-_left.get_combined_minimum_size().y
	for air in _left_air:
		air.visible = slack > 48   # each shown gap also costs one column separation (at most 14)
	var gaps := _page.get_children().filter(func(child: Node) -> bool: return child is Control and child.visible).size()-1
	var spare := usable-_page.get_combined_minimum_size().y
	if spare > 0 and gaps > 0:
		_page.add_theme_constant_override("separation",separation+int(spare/gaps))


## A step's heading: its number, its name and (from 900 px, _set_rail) a hint at the right in 15 px muted.
func _step_heading(number: String, step_name: String, hint: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	var parts := [_label(number,17),_label(step_name,17),_label(hint,15,HouseStyle.MUTED)]
	parts[2].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts[2].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parts[2].clip_text = true
	parts[2].text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for part in parts:
		part.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(part)
	_headings.append(parts)
	return row


## The six biomes stand in one row when the rail form leaves the left column at least SIX_MIN_W wide.
func _six_biomes() -> bool:
	return _rail_body.visible and _left.size.x >= SIX_MIN_W


## Raises the controls' minimum height toward `cap` as far as the page still fits `usable` (bisection).
func _grow(controls: Array, cap: float, usable: float) -> void:
	var fits: float = controls[0].custom_minimum_size.y
	var over := cap
	for step in 12:
		if over-fits < 1.0:
			break
		var height := over if step == 0 else (fits+over)*0.5
		for control in controls:
			control.custom_minimum_size.y = height
		if _page.get_combined_minimum_size().y <= usable:
			fits = height
		else:
			over = height
	for control in controls:
		control.custom_minimum_size.y = floorf(fits)


func _label(value: String, font_size: int, color := HouseStyle.INK, wrap := false) -> Label:
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
		var color := HouseStyle.GOLD if primary else Color("253035") if selected else Color("142027")
		if state == "hover":
			color = Color("ebd19a") if primary else Color("293b43")
		var box := _box(color,HouseStyle.GOLD if selected or state == "focus" else HouseStyle.LINE)
		box.set_border_width_all(2 if selected and not primary else 1)   # the chosen card's 2 px gold rim (step 83)
		button.add_theme_stylebox_override(state,box)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state,Color.TRANSPARENT if button.has_meta("visual_card") else Color("192125") if primary else HouseStyle.INK)


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


static func _preview_path(key: String) -> String:
	return "res://assets/ui/table_setup/"+str(PREVIEW_FILE.get(key,key))+".webp"


## The biome's picture (a menu or table biome id); "" for a biome the setup does not know.
static func preview_path(biome: String) -> String:
	var key := table_biome(biome)
	if not BIOMES.has(key):
		return ""
	return _preview_path(key)


func _image(key: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load(_preview_path(key))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
