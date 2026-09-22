extends Control
## Native Control implementation of the approved menu, independent of game routing.
signal route_opened
signal route_closed
const INK := Color("e9e9df")
const MUTED := Color("a7b0b6")
const GOLD := Color("d9bd83")
const CYAN := Color("87babc")
const FONT = preload("res://assets/ui_glassmorphism/fonts/Inter.ttf")
const LOGO = preload("res://assets/ui_glassmorphism/fonts/Orbitron.ttf")
var buttons: Dictionary = {}
var resume: PanelContainer
var save_name: Label
var save_date: Label
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

class Action extends Button:
	var description := ""
	var glyph := ""
	var primary := false
	var outlined := false

	func _ready() -> void:
		custom_minimum_size = Vector2(0,54 if description.is_empty() else 75)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_font_override("font",FONT)
		add_theme_font_size_override("font_size",17)
		for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
			add_theme_color_override(state,Color.TRANSPARENT)
		refresh_style()
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func refresh_style() -> void:
		for state in ["normal","hover","pressed","focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = GOLD if primary else Color("1823296b") if outlined else Color.TRANSPARENT
			if state in ["hover","pressed"]:
				box.bg_color = Color("ebd19a") if primary else Color("26333b9c")
			box.border_color = GOLD if primary or state == "focus" else Color("a4b8bd44")
			box.set_border_width_all(1 if primary or outlined or state == "focus" else 0)
			box.set_corner_radius_all(4)
			add_theme_stylebox_override(state,box)
		queue_redraw()

	func _draw() -> void:
		var color := Color("192125") if primary else INK
		var left := 18.0 if glyph.is_empty() else 52.0
		var baseline := 34.0 if not description.is_empty() else size.y*0.5+6
		draw_string(FONT,Vector2(left,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-left-35,17,color)
		if not description.is_empty():
			draw_string(FONT,Vector2(left,baseline+22),description,HORIZONTAL_ALIGNMENT_LEFT,size.x-left-25,12,Color("344c54") if primary else MUTED)
		if not glyph.is_empty():
			draw_string(FONT,Vector2(14,size.y*0.5+7),glyph,HORIZONTAL_ALIGNMENT_LEFT,28,24,color if primary else CYAN)
		draw_string(FONT,Vector2(size.x-31,size.y*0.5+6),"→",HORIZONTAL_ALIGNMENT_LEFT,24,21,color)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_masthead = HBoxContainer.new()
	add_child(_masthead)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_masthead.add_child(identity)
	identity.add_child(_label("TABLETOP FÜR ONEPAGERULES",10,MUTED))
	var wordmark := HBoxContainer.new()
	wordmark.add_theme_constant_override("separation",0)
	identity.add_child(wordmark)
	for part in ["NIEMANDS","LAND"]:
		var letter := _label(part,48,CYAN if part == "LAND" else INK)
		letter.add_theme_font_override("font",LOGO)
		wordmark.add_child(letter)
	var rule := ColorRect.new()
	rule.color = Color("819f9e65")
	rule.custom_minimum_size = Vector2(450,1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	identity.add_child(rule)
	var settings := _utility("SettingsBtn","⚙  Einstellungen")
	settings.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_masthead.add_child(settings)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation",5)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_scroll.add_child(_main)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	welcome_kicker = _label("WILLKOMMEN BEI NIEMANDSLAND",10,MUTED)
	_main.add_child(welcome_kicker)
	welcome = _label("Dein erster Tisch wartet.",35,INK)
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
	saved.add_child(_label("LETZTER SPIELSTAND",10,MUTED))
	save_name = _label("",21,INK)
	save_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	saved.add_child(save_name)
	save_date = _label("",12,MUTED)
	saved.add_child(save_date)
	var cont := _action("ContinueBtn","Weiterspielen","","",true)
	cont.custom_minimum_size.y = 54
	saved.add_child(cont)
	var actions := VBoxContainer.new()
	actions.name = "MenuButtons"
	actions.add_theme_constant_override("separation",5)
	_main.add_child(actions)
	actions.add_child(_action("StartBattleBtn","Neuen Tisch vorbereiten","Größe und Biom auswählen","+",false,true))
	actions.add_child(_action("OnlineBtn","Online spielen","Raum erstellen oder einem Tisch beitreten","⊕"))
	actions.add_child(_action("LoadBattleBtn","Spielstand laden","Eine gespeicherte Partie öffnen","□"))
	actions.add_child(_action("LearnBtn","Spiel lernen","Bedienung üben und Feuertaufe entdecken","≡"))
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation",24)
	add_child(_footer)
	for row in [["HelpBtn","Hilfe & Feedback"],["CreditsBtn","Credits & Lizenzen"],["ExitGameBtn","Beenden"]]:
		_footer.add_child(_utility(row[0],row[1]))
	version = _label("",11,MUTED)
	add_child(version)
	status = _label("Kulisse wird vorbereitet …",11,MUTED)
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
	route_back = _utility("RouteBackBtn","←  Zurück")
	column.add_child(route_back)
	route_title = _label("",28,INK)
	column.add_child(route_title)
	_route_body = VBoxContainer.new()
	column.add_child(_route_body)
	for key in ["online","learn","help"]:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation",12)
		_route_body.add_child(group)
		routes[key] = group
	for row in [
		["online","HostOnlineBtn","Raum erstellen","Einen Tisch für deine Runde vorbereiten"],
		["online","JoinOnlineBtn","Mit Code beitreten","Einen sechsstelligen Einladungscode eingeben"],
		["online","BrowseOnlineBtn","Öffentliche Tische","Eine offene Spielrunde finden"],
		["learn","TutorialBtn","Bedienung lernen","Klassisches Tutorial: Kamera, Miniaturen und Werkzeuge"],
		["learn","SpielschuleBtn","Feuertaufe · In Entwicklung","Kurze, einzeln spielbare Übungsszenarien"],
		["help","HelpTutorialBtn","Bedienung lernen","Das vorhandene Tutorial öffnen"],
		["help","ReportProblemBtn","Problem melden","Eine Diagnosedatei zum Weitergeben erstellen"]]:
		var button := _action(row[1],row[2],row[3],"",false,true)
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
	route_title.text = {"online":"Gemeinsam an einen Tisch.","learn":"Finde deinen Einstieg.","help":"Hilfe & Feedback."}[key]
	route_panel.reset_size()
	route_panel.show()
	# Trap keyboard focus within the open route, including Shift+Tab and arrows.
	var focus: Array[Control] = [route_back]
	for button in routes[key].get_children():
		focus.append(button)
	set_focus_chain(focus)
	focus[1].grab_focus()
	route_opened.emit()


func close_route() -> void:
	if not route_panel.visible:
		return
	route_panel.hide()
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	route_closed.emit()


func set_save(info: Dictionary) -> void:
	resume.visible = not info.is_empty()
	buttons.ContinueBtn.visible = resume.visible
	welcome_kicker.text = "WILLKOMMEN ZURÜCK" if resume.visible else "WILLKOMMEN BEI NIEMANDSLAND"
	welcome.text = "Zurück an den Tisch." if resume.visible else "Dein erster Tisch wartet."
	if resume.visible:
		save_name.text = str(info.name)
		save_name.tooltip_text = str(info.name)
		var stamp := Time.get_datetime_dict_from_unix_time(info.modified_unix)
		save_date.text = "Gespeichert am %02d.%02d.%04d" % [stamp.day,stamp.month,stamp.year]
	var start: Action = buttons.StartBattleBtn
	start.primary = not resume.visible
	# Rebuild only the state styles, once after the save lookup.
	start.refresh_style()
	set_focus_chain(main_buttons())


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
	_masthead.position = Vector2(left,42)
	_masthead.size.x = size.x-left*2
	_scroll.position = Vector2(left,clampf(size.y*0.185,165,200))
	_scroll.size = Vector2(minf(450,size.x-left*2),maxf(150,size.y-_scroll.position.y-140))
	_footer.position = Vector2(left,size.y-85)
	version.position = Vector2(left,size.y-35)
	status.position = Vector2(size.x-450,size.y-35)
	status.size.x = 354
	route_panel.position = Vector2(maxf(24,size.x-620),minf(215,size.y*0.2))
	route_panel.size.x = 500


func _action(id: String, title: String, description: String, glyph: String, primary := false, outlined := false) -> Action:
	var button := Action.new()
	button.name = id
	button.text = title
	button.description = description
	button.glyph = glyph
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
	button.add_theme_font_size_override("font_size",13)
	button.add_theme_color_override("font_color",MUTED)
	button.add_theme_color_override("font_hover_color",GOLD)
	button.add_theme_stylebox_override("normal",_box(Color.TRANSPARENT,Color.TRANSPARENT,10))
	button.add_theme_stylebox_override("focus",_box(Color.TRANSPARENT,GOLD,10))
	buttons[id] = button
	return button


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font",FONT)
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
