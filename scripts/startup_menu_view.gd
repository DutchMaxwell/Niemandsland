extends Control
## Native Control implementation of the approved menu, independent of game routing.
signal route_opened
signal route_closed
signal arrived
const FONT = preload("res://assets/ui_glassmorphism/fonts/Inter.ttf")
const LOGO = preload("res://assets/ui_glassmorphism/fonts/Orbitron.ttf")
var buttons: Dictionary = {}
var resume: PanelContainer
var save_name: Label
var save_date: Label
var save_facts: Array[Label] = []
var save_picture: TextureRect
const PICTURE_SIZE := Vector2(150,112)
var welcome: Label
var welcome_kicker: Label
var status: Label
var version: Label
var route_panel: PanelContainer
var route_title: Label
var routes: Dictionary = {}
var route_back: Button
var _return_focus: Control
var page_open: Control   # the MenuPage shown in place of the list, or null
var news_card: Button
var _news_eyebrow: Label
var _news_title: Label
var _news_count: Label
var _news_picture: TextureRect
var _news_shown := false   # the release notes have cards
var _scroll: ScrollContainer
var _main: VBoxContainer
var _footer: HBoxContainer
var _masthead: HBoxContainer
var _route_body: VBoxContainer
var _arrived := false
## The arrival (motion table): the rows rise this far while they fade in, one every ARRIVAL_STAGGER seconds.
const ARRIVAL_RISE := 12.0
const ARRIVAL_STAGGER := 0.06
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
	&"go": "<path d='M9 5l7 7-7 7'/>",
	&"help": "<circle cx='12' cy='12' r='9'/><path d='M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 17h.01'/>",
	&"info": "<circle cx='12' cy='12' r='9'/><path d='M12 11v5.5M12 7.5h.01'/>",
	&"power": "<path d='M12 3v8M6.6 6.6a8 8 0 1 0 10.8 0'/>",
}
const ICON_PX := 24
const NEWS_W := 396   # the news card: 64 px from the right edge, 96 px from the bottom
const NEWS_H := 116
const MONTHS := ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
static var _icons: Dictionary = {}

class Action extends Button:
	var description := ""
	var row_icon: Texture2D  # not "icon": a Button already draws that one itself
	var end_mark: Texture2D  # the chevron at the row's end; the Continue button has none
	var primary := false
	var outlined := false
	var highlighted := false  # drawn lit while at rest (the Learn row of a first launch)
	var tag := ""  # a small mono tag after the title ("NEW HERE?")
	var key_hint := ""  # the key that takes this row while it is the main action ("Enter")
	var key_cap: Label

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		set_meta(UiMotion.META_FLAT,true)
		if not key_hint.is_empty():
			key_cap = HouseStyle.key_cap_on_gold(key_hint)
			key_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			key_cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			key_cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			key_cap.grow_vertical = Control.GROW_DIRECTION_BOTH
			key_cap.offset_left = -52
			key_cap.offset_right = -52
			add_child(key_cap)
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

	## Row titles stand at weight 500, the main action (the gold row, Continue) at 600: hierarchy without a new colour.
	func title_font() -> Font:
		return HouseStyle.font(600 if primary else 500)

	func refresh_style() -> void:
		custom_minimum_size = Vector2(0,54 if description.is_empty() else 76 if primary else 64)
		if key_cap != null:
			key_cap.visible = primary
		for state in ["normal","hover","pressed","focus"]:
			var box := StyleBoxFlat.new()
			var lit: bool = state != "normal" or highlighted
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

	## The tag: mono 12 px in gold with a 60 % gold rim, 22 px high, radius 3.
	func _draw_tag(origin: Vector2) -> void:
		var font := HouseStyle.mono()
		var box := StyleBoxFlat.new()
		box.bg_color = Color.TRANSPARENT
		box.border_color = Color(HouseStyle.GOLD,0.6)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		var width := font.get_string_size(tag,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+16
		draw_style_box(box,Rect2(origin,Vector2(width,22)))
		draw_string(font,origin+Vector2(8,15),tag,HORIZONTAL_ALIGNMENT_LEFT,-1,12,HouseStyle.GOLD)

	func _draw() -> void:
		var color := Color("192125") if primary else HouseStyle.INK
		var left := 18.0 if row_icon == null else 52.0
		# 28 and 49 on the 64 px row; centred on the taller first-run row, as the mockup draws it.
		var baseline := size.y*0.5-4 if not description.is_empty() else size.y*0.5+8
		draw_string(title_font(),Vector2(left,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-left-35,22,color)
		if not description.is_empty():
			draw_string(FONT,Vector2(left,size.y*0.5+17),description,HORIZONTAL_ALIGNMENT_LEFT,size.x-left-25,15,Color("344c54") if primary else HouseStyle.MUTED)
		if row_icon != null:
			draw_texture_rect(row_icon,Rect2(16,size.y*0.5-ICON_PX*0.5,ICON_PX,ICON_PX),false,color if primary else HouseStyle.ACCENT)
		var lit := not primary and (is_hovered() or has_focus() or highlighted)
		if not tag.is_empty():
			_draw_tag(Vector2(left+title_font().get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x+12,baseline-19))
		if lit:
			draw_rect(Rect2(0,12,3,size.y-24),HouseStyle.GOLD)
		if end_mark != null:
			var mark := HouseStyle.GOLD if lit else color if primary else HouseStyle.MUTED
			draw_texture_rect(end_mark,Rect2(size.x-40,size.y*0.5-ICON_PX*0.5,ICON_PX,ICON_PX),false,mark)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_masthead = HBoxContainer.new()
	add_child(_masthead)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_masthead.add_child(identity)
	identity.add_child(_label("TABLETOP FOR ONEPAGERULES",14,HouseStyle.MUTED,HouseStyle.eyebrow_font()))
	var wordmark := HBoxContainer.new()
	wordmark.add_theme_constant_override("separation",0)
	identity.add_child(wordmark)
	for part in ["NIEMANDS","LAND"]:
		var letter := _label(part,54,HouseStyle.ACCENT if part == "LAND" else HouseStyle.INK)
		letter.add_theme_font_override("font",LOGO)
		wordmark.add_child(letter)
	identity.add_child(HouseStyle.signature_rule(470))
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation",5)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_scroll.add_child(_main)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	welcome_kicker = _label("WELCOME TO NIEMANDSLAND",14,HouseStyle.ACCENT,HouseStyle.eyebrow_font())
	_main.add_child(welcome_kicker)
	welcome = _label("Your first table awaits.",44,HouseStyle.INK)
	welcome.add_theme_font_override("font",HouseStyle.font(500))
	_main.add_child(welcome)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_main.add_child(gap)
	resume = PanelContainer.new()
	resume.add_theme_stylebox_override("panel",_box(Color("182329dc"),Color("b8a67955"),18))
	resume.draw.connect(_draw_card_corners)
	resume.resized.connect(resume.queue_redraw)
	_main.add_child(resume)
	var saved := VBoxContainer.new()
	saved.add_theme_constant_override("separation",12)
	resume.add_child(saved)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation",18)
	saved.add_child(head)
	save_picture = TextureRect.new()
	save_picture.custom_minimum_size = PICTURE_SIZE
	save_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	save_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	save_picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	save_picture.visible = false
	head.add_child(save_picture)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation",4)
	head.add_child(text)
	text.add_child(_label("LATEST SAVE",14,HouseStyle.MUTED,HouseStyle.eyebrow_font()))
	save_name = _label("",26,HouseStyle.INK)
	save_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var name_row := MarginContainer.new()   # 6 px between the kicker and the name (4 of separation, 2 of margin)
	name_row.add_theme_constant_override("margin_top",2)
	name_row.add_child(save_name)
	text.add_child(name_row)
	for _i in 2:
		var fact := _label("",14,HouseStyle.MUTED,HouseStyle.mono())
		text.add_child(fact)
		save_facts.append(fact)
	save_date = _label("",15,HouseStyle.MUTED)
	text.add_child(save_date)
	var cont := _action("ContinueBtn","Continue","",null,true)
	cont.key_hint = "Enter"
	cont.custom_minimum_size.y = 54
	saved.add_child(cont)
	var actions := VBoxContainer.new()
	actions.name = "MenuButtons"
	actions.add_theme_constant_override("separation",5)
	_main.add_child(actions)
	var start := _action("StartBattleBtn","Prepare a new table","Choose a game system, a biome and a size",_icon(&"table"),false,true)
	start.key_hint = "Enter"
	actions.add_child(start)
	actions.add_child(_action("OnlineBtn","Play online","Create a room or join a table",_icon(&"globe")))
	actions.add_child(_action("LoadBattleBtn","Load game","Open a saved game",_icon(&"folder")))
	actions.add_child(_action("LearnBtn","Learn to play","Learn the controls and explore Trial by Fire",_icon(&"book")))
	actions.add_child(_action("SettingsBtn","Settings","Display, graphics, audio and accessibility",_icon(&"sliders")))
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation",34)
	add_child(_footer)
	for row in [["HelpBtn","Help & feedback",&"help"],["CreditsBtn","Credits & licenses",&"info"],["ExitGameBtn","Quit",&"power"]]:
		if row[0] == "ExitGameBtn":
			var quit := HBoxContainer.new()
			quit.add_theme_constant_override("separation",4)
			quit.add_child(_utility(row[0],row[1],row[2]))
			var esc := HouseStyle.key_cap("Esc")
			esc.theme = HouseStyle.theme()
			esc.add_theme_font_size_override("font_size",14)
			quit.add_child(esc)
			_footer.add_child(quit)
		else:
			_footer.add_child(_utility(row[0],row[1],row[2]))
	version = _label("",14,HouseStyle.MUTED,HouseStyle.mono())
	version.uppercase = true
	add_child(version)
	status = _label("Preparing background …",14,HouseStyle.MUTED,HouseStyle.mono())
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	_build_routes()
	_build_news_card()
	buttons.HelpBtn.pressed.connect(func() -> void: show_route("help"))
	resized.connect(_layout)
	_layout()


## The news card (sheet 01): the release's first highlight at the right edge, a way into the release notes.
func _build_news_card() -> void:
	news_card = Button.new()
	news_card.name = "NewsCard"
	news_card.focus_mode = Control.FOCUS_ALL
	news_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	news_card.custom_minimum_size = Vector2(NEWS_W,NEWS_H)
	var rest := _box(HouseStyle.PANEL,HouseStyle.LINE_SOFT,16)
	var lit := _box(HouseStyle.PANEL,HouseStyle.ACCENT,16)
	for state in ["normal","disabled"]:
		news_card.add_theme_stylebox_override(state,rest)
	for state in ["hover","pressed","focus"]:
		news_card.add_theme_stylebox_override(state,lit)
	add_child(news_card)
	buttons["NewsCard"] = news_card
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_MINSIZE,16)
	row.add_theme_constant_override("separation",14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	news_card.add_child(row)
	_news_picture = TextureRect.new()   # only when the card names a picture
	_news_picture.custom_minimum_size = Vector2(132,84)
	_news_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_news_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_news_picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_news_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_news_picture)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation",6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_news_eyebrow = _label("",14,HouseStyle.ACCENT,HouseStyle.eyebrow_font())
	_news_title = _label("",18,HouseStyle.INK,HouseStyle.font(500))
	_news_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation",4)
	_news_count = _label("",15,HouseStyle.MUTED)
	_news_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_news_count)
	line.add_child(_label("Read",15,HouseStyle.GOLD))
	var chevron := TextureRect.new()
	chevron.texture = _icon(&"go")
	chevron.custom_minimum_size = Vector2(16,16)
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.modulate = HouseStyle.GOLD
	line.add_child(chevron)
	for part: Control in [_news_eyebrow,_news_title,_news_count,line,chevron]:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_news_eyebrow)
	column.add_child(_news_title)
	column.add_child(line)
	set_news(WhatsNewContent.new().cards())


## Fills the news card from the release notes' cards (the first one, in the shown language); no cards, no card.
func set_news(cards: Array) -> void:
	_news_shown = not cards.is_empty()
	if _news_shown:
		var locale := TranslationServer.get_locale()
		var first: Dictionary = cards[0]
		var texts: Dictionary = first.get(WhatsNewContent.language(locale),{})
		_news_eyebrow.text = (WhatsNewContent.new().text_for(locale,"title") % WhatsNewContent.version()).to_upper()
		_news_title.text = str(texts.get("title",""))
		_news_count.text = "%d highlights" % cards.size()
		var picture := str(first.get("image",""))
		_news_picture.texture = load(picture) if not picture.is_empty() and ResourceLoader.exists(picture) else null
		_news_picture.visible = _news_picture.texture != null
	_sync_news_card()


## The card stands while the main list does: not with a route panel open, not without notes.
func _sync_news_card() -> void:
	news_card.visible = _news_shown and not route_panel.visible


## The Continue card's two gold corner brackets (top left, bottom right): 14 px legs, 1.5 px strokes.
func _draw_card_corners() -> void:
	for corner: Array in [[Vector2.ONE,Vector2(1,1)],[resume.size-Vector2.ONE,Vector2(-1,-1)]]:
		var at: Vector2 = corner[0]
		var way: Vector2 = corner[1]
		resume.draw_line(at,at+Vector2(14*way.x,0),HouseStyle.GOLD,1.5,true)
		resume.draw_line(at,at+Vector2(0,14*way.y),HouseStyle.GOLD,1.5,true)


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
	for key in ["help"]:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation",12)
		_route_body.add_child(group)
		routes[key] = group
	for row in [
		["help","HelpTutorialBtn","Learn the controls","Open the tutorial"],
		["help","WhatsNewBtn",WhatsNewContent.new().text_for(TranslationServer.get_locale(), "menu"),""],
		["help","ReportProblemBtn","Report a problem","Create a diagnostics file to share"]]:
		var button := _action(row[1],row[2],row[3],null,false,true)
		routes[row[0]].add_child(button)
		button.pressed.connect(close_route)
	route_back.pressed.connect(close_route)
	route_panel.hide()


## The menu arrives, once per start (never again after the table setup or a rebuilt backdrop): the wordmark
## fades in over a screen beat, the Continue card and the rows rise and fade in one after the other. Reduce
## Motion shows everything at once.
func play_arrival() -> void:
	if _arrived:
		return
	_arrived = true
	if UiMotion.reduced():
		arrived.emit()
		return
	var rows: Array[Control] = []
	if resume.visible:
		rows.append(resume)
	for row in _main.get_node("MenuButtons").get_children():
		rows.append(row as Control)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_masthead.modulate.a = 0.0
	tween.tween_property(_masthead,"modulate:a",1.0,HudTokens.DUR_SCREEN)
	var delay := 0.0
	for row in rows:
		var rest := row.position.y
		row.modulate.a = 0.0
		row.position.y = rest+ARRIVAL_RISE
		tween.tween_property(row,"modulate:a",1.0,HudTokens.DUR_PANEL_IN).set_delay(delay)
		tween.tween_property(row,"position:y",rest,HudTokens.DUR_PANEL_IN).set_delay(delay)
		delay += ARRIVAL_STAGGER
	await tween.finished
	arrived.emit()


func show_route(key: String) -> void:
	if not routes.has(key):
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	for route in routes:
		routes[route].visible = route == key
	route_title.text = {"help":"Help & feedback."}[key]
	route_panel.reset_size()
	route_panel.show()
	_sync_news_card()
	UiFeedback.play_panel(true)
	_slide_route(true)
	# Trap keyboard focus within the open route, including Shift+Tab and arrows.
	var focus: Array[Control] = [route_back]
	for button in routes[key].get_children():
		focus.append(button)
	set_focus_chain(focus)
	focus[1].grab_focus()
	route_opened.emit()


## A page of the menu (MenuPage) in place of the list: the masthead, the list, the footer links, the news card
## and the scene caption go while it is open; its `closed` brings them and the focus back.
func open_page(page: Control) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	page_open = page
	for part: Control in [_masthead, _scroll, _footer, news_card, status]:
		part.hide()
	add_child(page)
	page.connect("closed", close_page)
	(page.get("back") as Control).grab_focus()


func close_page() -> void:
	if not is_instance_valid(page_open):
		return
	page_open.queue_free()
	page_open = null
	for part: Control in [_masthead, _scroll, _footer, status]:
		part.show()
	_sync_news_card()
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()


func close_route() -> void:
	if not route_panel.visible or _route_closing:
		return
	UiFeedback.play_panel(false)
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	await _slide_route(false)
	_sync_news_card()
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
		var picture := TableSizeDialog.preview_path(str(info.get("biome","")))
		save_picture.texture = load(picture) if not picture.is_empty() else null
		save_picture.visible = save_picture.texture != null
		var lines := facts_lines(info)
		for i in save_facts.size():
			save_facts[i].text = lines[i] if i < lines.size() else ""
			save_facts[i].visible = i < lines.size()
		var stamp := Time.get_datetime_dict_from_unix_time(info.modified_unix)
		save_date.text = "Saved on %d %s %d" % [stamp.day,MONTHS[stamp.month-1],stamp.year]
	var start: Action = buttons.StartBattleBtn
	start.primary = not resume.visible
	# Rebuild only the state styles, once after the save lookup.
	start.refresh_style()
	# A first launch points at Learn: second in the list, lit and tagged; with a save it is back in fourth place.
	var learn: Action = buttons.LearnBtn
	learn.highlighted = not resume.visible
	learn.tag = "" if resume.visible else "NEW HERE?"
	learn.refresh_style()
	learn.get_parent().move_child(learn,3 if resume.visible else 1)
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
	var keys: Array = ["ContinueBtn"]   # the shown order: the card's button, the list as it stands, the footer, the news card
	for row in buttons.StartBattleBtn.get_parent().get_children():
		keys.append(String(row.name))
	keys.append_array(["HelpBtn","CreditsBtn","ExitGameBtn","NewsCard"])
	for key in keys:
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
	news_card.size = Vector2(NEWS_W,NEWS_H)
	news_card.position = Vector2(size.x-64-NEWS_W,size.y-96-NEWS_H)
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
	button.end_mark = null if description.is_empty() else _icon(&"go")
	button.primary = primary
	button.outlined = outlined
	buttons[id] = button
	return button


func _utility(id: String, title: String, icon_key: StringName = &"") -> Button:
	var button := Button.new()
	button.name = id
	button.text = title
	button.flat = true
	if icon_key != &"":   # an 18 px icon tinted with the text, 9 px before it
		button.icon = _icon(icon_key)
		button.add_theme_constant_override("icon_max_width",18)
		button.add_theme_constant_override("h_separation",9)
		for state in ["icon_normal_color","icon_pressed_color","icon_focus_color"]:
			button.add_theme_color_override(state,HouseStyle.MUTED)
		for state in ["icon_hover_color","icon_hover_pressed_color"]:
			button.add_theme_color_override(state,HouseStyle.GOLD)
	button.add_theme_font_override("font",FONT)
	button.add_theme_font_size_override("font_size",16)
	button.add_theme_color_override("font_color",HouseStyle.MUTED)
	button.add_theme_color_override("font_hover_color",HouseStyle.GOLD)
	# One box for every state: the theme's own hover box is wider, so the text got less room on hover.
	var rest := _box(Color.TRANSPARENT,Color.TRANSPARENT,10)
	for state in ["normal","hover","pressed"]:
		button.add_theme_stylebox_override(state,rest)
	var ring := _box(Color.TRANSPARENT,HouseStyle.ACCENT,10)
	ring.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",ring)
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
