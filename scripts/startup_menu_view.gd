extends Control
## Native Control implementation of the approved menu, independent of game routing.
signal route_opened
signal route_closed
const FONT = preload("res://assets/ui_glassmorphism/fonts/Inter.ttf")
const LOGO = preload("res://assets/ui_glassmorphism/fonts/Orbitron.ttf")
const MONO = preload("res://assets/ui_glassmorphism/fonts/SourceCodePro.ttf")
var buttons: Dictionary = {}
var resume: PanelContainer
var save_name: Label
var save_date: Label
var save_facts: Array[Label] = []
var welcome: Label
var welcome_kicker: Label
var status: Label
var version: Label
var route_panel: PanelContainer
var route_title: Label
var routes: Dictionary = {}
var route_back: Button
var _return_focus: Control
var _scroll: ScrollContainer
var _main: VBoxContainer
var _footer: HBoxContainer
var _masthead: HBoxContainer
var _route_body: VBoxContainer
var _route_tween: Tween
var _route_rest := Vector2.ZERO
var _route_closing := false
## How far the sub-menu panel slides while it fades in and out.
const ROUTE_SLIDE := 16.0
## Row icons: own drawings in the tool rail's style (24 x 24 view box), built once as crisp textures.
const ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 24 24' fill='none' stroke='#fff' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'>%s</svg>"
const ICON_PATHS := {
	&"table": "<path d='M3 17l4-9h10l4 9z'/><path d='M5.2 12h13.6M10 8l-1.5 9M14 8l1.5 9'/>",
	&"globe": "<circle cx='12' cy='12' r='9'/><path d='M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18'/>",
	&"folder": "<path d='M3 7.5a1.5 1.5 0 0 1 1.5-1.5H9l2 2.5h8.5A1.5 1.5 0 0 1 21 10v7.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z'/>",
	&"book": "<path d='M12 6.5c-2-1.3-4.7-1.7-8-1.5v13c3.3-.2 6 .2 8 1.5 2-1.3 4.7-1.7 8-1.5V5c-3.3-.2-6 .2-8 1.5zM12 6.5v13'/>",
	&"sliders": "<path d='M4 7h10M18 7h2M4 17h4M12 17h8M14 4.5v5M8 14.5v5'/>",
}
const ICON_PX := 24
static var _icons: Dictionary = {}

class Action extends Button:
	var description := ""
	var row_icon: Texture2D  # not "icon": a Button already draws that one itself
	var primary := false
	var outlined := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		set_meta(UiMotion.META_FLAT,true)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_font_override("font",FONT)
		add_theme_font_size_override("font_size",22)
		for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
			add_theme_color_override(state,Color.TRANSPARENT)
		refresh_style()
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func refresh_style() -> void:
		custom_minimum_size = Vector2(0,54 if description.is_empty() else 76 if primary else 64)
		for state in ["normal","hover","pressed","focus"]:
			var box := StyleBoxFlat.new()
			var lit: bool = state != "normal"
			box.bg_color = HouseStyle.GOLD if primary else Color("1823296b") if outlined else Color.TRANSPARENT
			if lit and not primary:
				box.bg_color = HouseStyle.ROW_PRESS if state == "pressed" else HouseStyle.ROW_HOVER
			elif state in ["hover","pressed"]:
				box.bg_color = Color("ebd19a")
			box.border_color = HouseStyle.GOLD if primary else HouseStyle.LINE_SOFT if lit else Color("a4b8bd44")
			box.set_border_width_all(1 if primary or outlined or lit else 0)
			box.set_corner_radius_all(4)
			add_theme_stylebox_override(state,box)
		queue_redraw()

	func _draw() -> void:
		var color := Color("192125") if primary else HouseStyle.INK
		var left := 18.0 if row_icon == null else 52.0
		# 28 and 49 on the 64 px row; centred on the taller first-run row, as the mockup draws it.
		var baseline := size.y*0.5-4 if not description.is_empty() else size.y*0.5+8
		draw_string(FONT,Vector2(left,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-left-35,22,color)
		if not description.is_empty():
			draw_string(FONT,Vector2(left,size.y*0.5+17),description,HORIZONTAL_ALIGNMENT_LEFT,size.x-left-25,15,Color("344c54") if primary else HouseStyle.MUTED)
		if row_icon != null:
			draw_texture_rect(row_icon,Rect2(16,size.y*0.5-ICON_PX*0.5,ICON_PX,ICON_PX),false,color if primary else HouseStyle.ACCENT)
		var lit := not primary and (is_hovered() or has_focus())
		if lit:
			draw_rect(Rect2(0,12,3,size.y-24),HouseStyle.GOLD)
		draw_string(FONT,Vector2(size.x-31,size.y*0.5+6),HouseStyle.GLYPH_GO,HORIZONTAL_ALIGNMENT_LEFT,24,28,HouseStyle.GOLD if lit else color)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_masthead = HBoxContainer.new()
	add_child(_masthead)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_masthead.add_child(identity)
	identity.add_child(_label("TABLETOP FOR ONEPAGERULES",14,HouseStyle.MUTED))
	var wordmark := HBoxContainer.new()
	wordmark.add_theme_constant_override("separation",0)
	identity.add_child(wordmark)
	for part in ["NIEMANDS","LAND"]:
		var letter := _label(part,54,HouseStyle.ACCENT if part == "LAND" else HouseStyle.INK)
		letter.add_theme_font_override("font",LOGO)
		wordmark.add_child(letter)
	var rule := ColorRect.new()
	rule.color = Color("819f9e65")
	rule.custom_minimum_size = Vector2(500,1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	identity.add_child(rule)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation",5)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_scroll.add_child(_main)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	welcome_kicker = _label("WELCOME TO NIEMANDSLAND",14,HouseStyle.MUTED)
	_main.add_child(welcome_kicker)
	welcome = _label("Your first table awaits.",44,HouseStyle.INK)
	_main.add_child(welcome)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_main.add_child(gap)
	resume = PanelContainer.new()
	resume.add_theme_stylebox_override("panel",_box(Color("182329dc"),Color("b8a67955"),20))
	_main.add_child(resume)
	var saved := VBoxContainer.new()
	saved.add_theme_constant_override("separation",12)
	resume.add_child(saved)
	saved.add_child(_label("LATEST SAVE",14,HouseStyle.MUTED))
	save_name = _label("",26,HouseStyle.INK)
	save_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	saved.add_child(save_name)
	for _i in 2:
		var fact := _label("",14,HouseStyle.MUTED,MONO)
		saved.add_child(fact)
		save_facts.append(fact)
	save_date = _label("",15,HouseStyle.MUTED)
	saved.add_child(save_date)
	var cont := _action("ContinueBtn","Continue","",null,true)
	cont.custom_minimum_size.y = 54
	saved.add_child(cont)
	var actions := VBoxContainer.new()
	actions.name = "MenuButtons"
	actions.add_theme_constant_override("separation",5)
	_main.add_child(actions)
	actions.add_child(_action("StartBattleBtn","Prepare a new table","Choose a size and biome",_icon(&"table"),false,true))
	actions.add_child(_action("OnlineBtn","Play online","Create a room or join a table",_icon(&"globe")))
	actions.add_child(_action("LoadBattleBtn","Load game","Open a saved game",_icon(&"folder")))
	actions.add_child(_action("LearnBtn","Learn to play","Learn the controls and explore Trial by Fire",_icon(&"book")))
	actions.add_child(_action("SettingsBtn","Settings","Display, graphics, audio and accessibility",_icon(&"sliders")))
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation",24)
	add_child(_footer)
	for row in [["HelpBtn","Help & feedback"],["CreditsBtn","Credits & licenses"],["ExitGameBtn","Quit"]]:
		_footer.add_child(_utility(row[0],row[1]))
	version = _label("",14,HouseStyle.MUTED,MONO)
	add_child(version)
	status = _label("Preparing background …",14,HouseStyle.MUTED,MONO)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	_build_routes()
	buttons.OnlineBtn.pressed.connect(func() -> void: show_route("online"))
	buttons.LearnBtn.pressed.connect(func() -> void: show_route("learn"))
	buttons.HelpBtn.pressed.connect(func() -> void: show_route("help"))
	resized.connect(_layout)
	_layout()


func _build_routes() -> void:
	route_panel = PanelContainer.new()
	route_panel.add_theme_stylebox_override("panel",_box(Color("111a20fa"),Color("63747580"),30))
	add_child(route_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	route_panel.add_child(column)
	route_back = _utility("RouteBackBtn",HouseStyle.GLYPH_BACK+"  Back")
	column.add_child(route_back)
	route_title = _label("",28,HouseStyle.INK)
	column.add_child(route_title)
	_route_body = VBoxContainer.new()
	column.add_child(_route_body)
	for key in ["online","learn","help"]:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation",12)
		_route_body.add_child(group)
		routes[key] = group
	for row in [
		["online","HostOnlineBtn","Create a room","Prepare a table for your group"],
		["online","JoinOnlineBtn","Join with a code","Enter a six-character invitation code"],
		["online","BrowseOnlineBtn","Public tables","Find an open game"],
		["learn","TutorialBtn","Learn the controls","Classic tutorial: camera, miniatures and tools"],
		["learn","SpielschuleBtn","Trial by Fire · In development","Short practice scenarios you can play individually"],
		["help","HelpTutorialBtn","Learn the controls","Open the tutorial"],
		["help","WhatsNewBtn",WhatsNewContent.new().text_for(TranslationServer.get_locale(), "menu"),""],
		["help","ReportProblemBtn","Report a problem","Create a diagnostics file to share"]]:
		var button := _action(row[1],row[2],row[3],null,false,true)
		routes[row[0]].add_child(button)
		button.pressed.connect(close_route)
	route_back.pressed.connect(close_route)
	route_panel.hide()


func show_route(key: String) -> void:
	if not routes.has(key):
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	for route in routes:
		routes[route].visible = route == key
	route_title.text = {"online":"Meet around the table.","learn":"Find your starting point.","help":"Help & feedback."}[key]
	route_panel.reset_size()
	route_panel.show()
	UiFeedback.play_panel(true)
	_slide_route(true)
	# Trap keyboard focus within the open route, including Shift+Tab and arrows.
	var focus: Array[Control] = [route_back]
	for button in routes[key].get_children():
		focus.append(button)
	set_focus_chain(focus)
	focus[1].grab_focus()
	route_opened.emit()


func close_route() -> void:
	if not route_panel.visible or _route_closing:
		return
	UiFeedback.play_panel(false)
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	await _slide_route(false)
	route_closed.emit()


## The panel's motion (motion table: in 220 ms with an ease-out, out 180 ms with an ease-in, both cubic):
## it slides ROUTE_SLIDE px and fades. Reduce Motion shows and hides it at once. A close ends with the
## panel hidden; route_closed fires after that.
func _slide_route(opening: bool) -> void:
	if _route_tween != null:
		_route_tween.kill()
	_route_closing = not opening
	if UiMotion.reduced():
		route_panel.position.x = _route_rest.x
		route_panel.modulate.a = 1.0
		route_panel.visible = opening
		_route_closing = false
		return
	if opening:
		route_panel.position.x = _route_rest.x-ROUTE_SLIDE
		route_panel.modulate.a = 0.0
	var duration := HudTokens.DUR_PANEL_IN if opening else HudTokens.DUR_PANEL_OUT
	_route_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
	_route_tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	_route_tween.tween_property(route_panel,"position:x",_route_rest.x if opening else _route_rest.x-ROUTE_SLIDE,duration)
	_route_tween.tween_property(route_panel,"modulate:a",1.0 if opening else 0.0,duration)
	await _route_tween.finished
	if not opening:
		route_panel.hide()
		route_panel.position.x = _route_rest.x
		route_panel.modulate.a = 1.0
		_route_closing = false


func set_save(info: Dictionary) -> void:
	resume.visible = not info.is_empty()
	buttons.ContinueBtn.visible = resume.visible
	welcome_kicker.text = "WELCOME BACK" if resume.visible else "WELCOME TO NIEMANDSLAND"
	welcome.text = "Back to the table." if resume.visible else "Your first table awaits."
	if resume.visible:
		save_name.text = str(info.name)
		save_name.tooltip_text = str(info.name)
		var lines := facts_lines(info)
		for i in save_facts.size():
			save_facts[i].text = lines[i] if i < lines.size() else ""
			save_facts[i].visible = i < lines.size()
		var stamp := Time.get_datetime_dict_from_unix_time(info.modified_unix)
		save_date.text = "Saved on %04d-%02d-%02d" % [stamp.year,stamp.month,stamp.day]
	var start: Action = buttons.StartBattleBtn
	start.primary = not resume.visible
	# Rebuild only the state styles, once after the save lookup.
	start.refresh_style()
	set_focus_chain(main_buttons())


## The Continue card's two mono lines, e.g. "GRIMDARK FUTURE · ROUND 1" and "GRASSLAND · 6 x 4 FT"; a line
## whose facts the save does not hold is left out.
static func facts_lines(info: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var first: Array[String] = []
	if info.has("system"):
		first.append(GameSystem.label(str(info.system)).to_upper())
	if info.has("round"):
		first.append("ROUND %d" % int(info.round))
	var second: Array[String] = []
	var biome := TableSizeDialog.table_biome(str(info.get("biome","")))
	if TableSizeDialog.BIOMES.has(biome):
		second.append(str(TableSizeDialog.BIOMES[biome][0]).to_upper())
	if info.has("size_feet"):
		second.append("%s x %s FT" % [String.num(info.size_feet[0],1).trim_suffix(".0"),String.num(info.size_feet[1],1).trim_suffix(".0")])
	for parts: Array[String] in [first,second]:
		if not parts.is_empty():
			lines.append(" · ".join(parts))
	return lines


func main_buttons() -> Array[Control]:
	var result: Array[Control] = []
	for key in ["ContinueBtn","StartBattleBtn","OnlineBtn","LoadBattleBtn","LearnBtn","SettingsBtn","HelpBtn","CreditsBtn","ExitGameBtn"]:
		if buttons[key].is_visible_in_tree():
			result.append(buttons[key])
	return result


static func set_focus_chain(controls: Array[Control]) -> void:
	for i in controls.size():
		var previous := controls[(i-1+controls.size())%controls.size()]
		var next := controls[(i+1)%controls.size()]
		controls[i].focus_neighbor_top = controls[i].get_path_to(previous)
		controls[i].focus_neighbor_bottom = controls[i].get_path_to(next)
		controls[i].focus_previous = controls[i].get_path_to(previous)
		controls[i].focus_next = controls[i].get_path_to(next)


func _layout() -> void:
	var left := maxf(28,size.x*0.05)
	_masthead.position = Vector2(left,58)
	_masthead.size.x = size.x-left*2
	_scroll.position = Vector2(left,clampf(size.y*0.19,180,206))
	_scroll.size = Vector2(minf(500,size.x-left*2),maxf(150,size.y-_scroll.position.y-140))
	_footer.position = Vector2(left,size.y-108)
	version.position = Vector2(left,size.y-50)
	status.position = Vector2(size.x-450,size.y-50)
	status.size.x = 354
	_route_rest = Vector2(left+_scroll.size.x+24,_scroll.position.y)
	route_panel.position = _route_rest
	route_panel.custom_minimum_size.x = 560


static func _icon(key: StringName) -> Texture2D:
	if not _icons.has(key):
		_icons[key] = HouseStyle.svg_icon(ICON_SVG % ICON_PATHS[key])
	return _icons[key]


func _action(id: String, title: String, description: String, icon_texture: Texture2D, primary := false, outlined := false) -> Action:
	var button := Action.new()
	button.name = id
	button.text = title
	button.description = description
	button.row_icon = icon_texture
	button.primary = primary
	button.outlined = outlined
	buttons[id] = button
	return button


func _utility(id: String, title: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = title
	button.flat = true
	button.add_theme_font_override("font",FONT)
	button.add_theme_font_size_override("font_size",16)
	button.add_theme_color_override("font_color",HouseStyle.MUTED)
	button.add_theme_color_override("font_hover_color",HouseStyle.GOLD)
	# One box for every state: the theme's own hover box is wider, so the text got less room on hover.
	var rest := _box(Color.TRANSPARENT,Color.TRANSPARENT,10)
	for state in ["normal","hover","pressed"]:
		button.add_theme_stylebox_override(state,rest)
	button.add_theme_stylebox_override("focus",_box(Color.TRANSPARENT,HouseStyle.GOLD,10))
	buttons[id] = button
	return button


func _label(text_value: String, font_size: int, color: Color, font: Font = FONT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	return label


func _box(color: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box
