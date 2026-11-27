class_name LearnPage
extends MenuPage
## "Learn to play": the two tracks, the classic tutorial and Trial by Fire, as cards in the left column: what the
## track is, how far the player is, the next lesson and one button that starts or continues it. Exactly one track is
## selected (gold rim and corners, NEXT in gold, its button gold with an Enter cap); a click on a card selects it.

signal tutorial_requested(lesson_id: String)
signal scenario_requested(chapter: Dictionary)

const CARD_H := 150
var _cards: Dictionary = {}
var _lessons: Dictionary = {}   # per track: lessons, done, playable, next, its name and how a card launches
var _grid: VBoxContainer
var _reset: Button
var _tutorial: TutorialProgress
var _trial: SpielschuleProgress
const TICK := "<path d='M5 12.5l4.5 4.5L19 7.5'/>"


## `returned`: the page was opened by a return from a lesson (Trial by Fire is selected then).
func setup(tutorial: TutorialProgress, trial: SpielschuleProgress, returned: bool) -> LearnPage:
	eyebrow.text = "LEARN TO PLAY"
	_build_panel()
	title.text = "Find your starting point."
	_tutorial = tutorial
	_trial = trial
	_build("TrialTrack" if returned or trial.any_completed(Spielschule.ids()) else "ClassicTrack")
	return self


## The two track cards from the progress as it stands, then `key` selected.
func _build(key: String) -> void:
	for card: Node in left.get_children():
		left.remove_child(card)
		card.queue_free()
	var tutorial := _tutorial
	var trial := _trial
	var track := TutorialFlow.build_tool_track()
	var done: Array = track.map(func(l: Dictionary) -> bool: return tutorial.is_lesson_completed(str(l.id)))
	_track("ClassicTrack", ["CLASSIC TUTORIAL", "Learn the controls", "Camera, miniatures and tools, on a prepared table."],
		track, done, track.map(func(_l: Dictionary) -> bool: return true),
		func(_lesson: Dictionary) -> void: tutorial_requested.emit(""),
		func(lesson: Dictionary) -> void: tutorial_requested.emit(str(lesson.id)))
	var chapters := Spielschule.chapters()
	done = chapters.map(func(c: Dictionary) -> bool: return trial.is_completed(str(c.id)))
	_track("TrialTrack", ["TRIAL BY FIRE · IN DEVELOPMENT", "Short practice scenarios",
		"Eleven short lessons — play them in any order, replay any time."], chapters, done,
		chapters.map(Spielschule.is_available), func(chapter: Dictionary) -> void: scenario_requested.emit(chapter),
		func(chapter: Dictionary) -> void: scenario_requested.emit(chapter))
	select(key)


## One track card; the next lesson is the first that is not done and can be played (`playable`).
func _track(key: String, words: Array, lessons: Array, done: Array, playable: Array, request: Callable,
		launch: Callable) -> void:
	var card := PanelContainer.new()
	card.name = key
	card.draw.connect(_draw_corners.bind(card))
	card.gui_input.connect(func(e: InputEvent) -> void: if e is InputEventMouseButton and e.pressed: select(key))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)
	for i in 3:
		var label := _text(words[i], [HouseStyle.MENU_FONT_EYEBROW, 24, HouseStyle.MENU_FONT_CAPTION][i],
			[HouseStyle.eyebrow_font(), HouseStyle.font(500), HouseStyle.font(400)][i])
		label.add_theme_color_override(&"font_color", [HouseStyle.ACCENT if key == "TrialTrack" else HouseStyle.MUTED,
			HouseStyle.INK, HouseStyle.MUTED][i])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(label)
	var count := done.count(true)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 4
	bar.value = 100.0 * count / lessons.size()
	box.add_child(bar)
	var next := -1
	for i in lessons.size():
		if next < 0 and not done[i] and playable[i]:
			next = i
	_lessons[key] = [lessons, done, playable, next, words[0].get_slice(" · ", 0), launch]
	var line := HBoxContainer.new()
	var tally := _text("%d / %d LESSONS" % [count, lessons.size()], HouseStyle.MENU_FONT_EYEBROW, HouseStyle.mono())
	tally.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(tally)
	var next_label := _text("" if next < 0 else "NEXT: " + str(lessons[next].title).to_upper(),
		HouseStyle.MENU_FONT_EYEBROW, HouseStyle.mono())
	line.add_child(next_label)
	box.add_child(line)
	var button := HouseStyle.button("Start" if count == 0 else "Continue with lesson %d" % (next + 1),
		HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	button.name = key + "Button"
	button.focus_mode = FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if next < 0:
		button.text = "All lessons done - pick one to replay"
		button.disabled = true
	else:
		button.pressed.connect(func() -> void: request.call(lessons[next]))
	var cap := HouseStyle.key_cap_on_gold("Enter")
	cap.name = "EnterCap"
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	cap.set_anchors_preset(PRESET_CENTER_RIGHT)
	cap.grow_horizontal = GROW_DIRECTION_BEGIN
	cap.grow_vertical = GROW_DIRECTION_BOTH
	cap.offset_left = -12
	cap.offset_right = -12
	button.add_child(cap)
	button.focus_entered.connect(select.bind(key))
	box.add_child(button)
	left.add_child(card)
	_cards[key] = [card, next_label, button]


func select(key: String) -> void:
	for other: String in _cards:
		var on := other == key
		var parts: Array = _cards[other]
		var box := HouseStyle.menu_theme().get_stylebox(&"panel", HouseStyle.PANEL_VARIANT).duplicate() as StyleBoxFlat
		box.set_content_margin_all(20)
		if on:
			box.border_color = HouseStyle.GOLD
		(parts[0] as PanelContainer).add_theme_stylebox_override(&"panel", box)
		(parts[0] as Control).set_meta("selected", on)
		(parts[0] as Control).queue_redraw()
		(parts[1] as Label).add_theme_color_override(&"font_color", HouseStyle.GOLD if on else HouseStyle.MUTED)
		var button := parts[2] as Button
		button.theme_type_variation = HouseStyle.PRIMARY if on and not button.disabled else HouseStyle.BUTTON
		(button.get_node("EnterCap") as Control).visible = on and not button.disabled
	_fill_grid(key)


## The right panel's head: the selected track's name, "Pick a lesson", "Everything stays replayable".
func _build_panel() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	right.add_child(box)
	var head := HBoxContainer.new()
	var names := VBoxContainer.new()
	names.size_flags_horizontal = SIZE_EXPAND_FILL
	var track_name := _text("", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font())
	track_name.name = "TrackName"
	track_name.add_theme_color_override(&"font_color", HouseStyle.ACCENT)
	names.add_child(track_name)
	names.add_child(_text("Pick a lesson", 22, HouseStyle.font(500)))
	head.add_child(names)
	var note := _text("Everything stays replayable", HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
	note.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	head.add_child(note)
	box.add_child(head)
	_grid = VBoxContainer.new()
	_grid.name = "LessonGrid"
	_grid.add_theme_constant_override(&"separation", 12)
	box.add_child(_grid)
	_reset = HouseStyle.button("Reset tutorial progress", HouseStyle.DANGER_BUTTON, HouseStyle.MENU_H_ACTION)
	_reset.name = "ResetTutorial"
	_reset.flat = true
	_reset.focus_mode = FOCUS_ALL
	_reset.size_flags_horizontal = SIZE_SHRINK_END
	_reset.pressed.connect(func() -> void:
		_tutorial.reset()
		_build("ClassicTrack"))
	box.add_child(_reset)


## The selected track's lessons, four to a row: position, title, goal and a state
## line ("Done · replay", or "Next lesson" in gold on the next one); a lesson that cannot be played says so.
func _fill_grid(key: String) -> void:
	var data: Array = _lessons[key]
	(right.find_child("TrackName", true, false) as Label).text = str(data[4])
	_reset.visible = key == "ClassicTrack"
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var row: HBoxContainer
	for i in (data[0] as Array).size():
		if i % 4 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override(&"separation", 12)
			_grid.add_child(row)
		var lesson: Dictionary = data[0][i]
		var card := Button.new()
		card.name = "Lesson%02d" % (i + 1)
		card.custom_minimum_size = Vector2(0, CARD_H)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.disabled = not data[2][i]
		card.pressed.connect(func() -> void: (data[5] as Callable).call(lesson))
		var words := VBoxContainer.new()
		words.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 16)
		words.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(words)
		var finale := key == "TrialTrack" and i == (data[0] as Array).size() - 1
		var number := HBoxContainer.new()
		number.add_child(_text("%02d · FINALE" % (i + 1) if finale else "%02d" % (i + 1), 14, HouseStyle.mono()))
		if data[1][i]:   # a drawn tick, not a glyph: the mono font's coverage of U+2713 is not proven
			var tick := TextureRect.new()
			tick.name = "Tick"
			tick.texture = HouseStyle.svg_icon(MenuView.ICON_SVG % TICK)
			tick.custom_minimum_size = Vector2(14, 14)
			tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tick.modulate = HouseStyle.OK
			number.add_child(tick)
		words.add_child(number)
		var lesson_title := _text(str(lesson.title), 19, HouseStyle.font(500))
		lesson_title.autowrap_mode = TextServer.AUTOWRAP_WORD   # long classic titles wrap inside their card
		words.add_child(lesson_title)
		var goal := _text(str(lesson.get("goal", "")), HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
		goal.autowrap_mode = TextServer.AUTOWRAP_WORD
		goal.size_flags_vertical = SIZE_EXPAND_FILL
		words.add_child(goal)
		var state := "Next lesson" if i == data[3] else ("Done · replay" if data[1][i] else "")
		state = "Coming soon" if card.disabled else state
		var state_label := _text(state, HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
		state_label.add_theme_color_override(&"font_color", HouseStyle.GOLD if i == data[3] else HouseStyle.MUTED)
		words.add_child(state_label)
		if finale:   # two columns wide, a gold wash from the left and the tag "Finale"
			card.size_flags_stretch_ratio = 2.0
			var wash := GradientTexture2D.new()
			wash.gradient = Gradient.new()
			wash.gradient.set_color(0, Color(HouseStyle.GOLD, 0.14))
			wash.gradient.set_color(1, Color(HouseStyle.GOLD, 0.0))
			var fill := TextureRect.new()
			fill.texture = wash
			fill.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			fill.mouse_filter = MOUSE_FILTER_IGNORE
			card.add_child(fill)
			card.move_child(fill, 0)
			var tag := _text("FINALE", 13, HouseStyle.mono())   # a bordered gold chip (sheet 07)
			tag.add_theme_color_override(&"font_color", HouseStyle.GOLD)
			var chip := PanelContainer.new()
			var rim := StyleBoxFlat.new()
			rim.bg_color = Color(HouseStyle.GOLD, 0.08)
			rim.border_color = Color(HouseStyle.GOLD, 0.6)
			rim.set_border_width_all(1)
			rim.set_corner_radius_all(3)
			rim.content_margin_left = 8
			rim.content_margin_right = 8
			chip.add_theme_stylebox_override(&"panel", rim)
			chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
			chip.add_child(tag)
			words.add_child(chip)
		for label: Label in words.find_children("*", "Label", true, false):
			label.mouse_filter = MOUSE_FILTER_IGNORE
		if i == data[3]:   # the next lesson: the gold rim and the lighter fill
			var rim := HouseStyle.menu_theme().get_stylebox(&"normal", &"Button").duplicate() as StyleBoxFlat
			rim.bg_color = HouseStyle.ROW_HOVER
			rim.border_color = HouseStyle.GOLD
			card.add_theme_stylebox_override(&"normal", rim)
		row.add_child(card)
	_chain()


## The selected card's two gold corner brackets (top left, bottom right), as on the menu's Continue card.
func _draw_corners(card: Control) -> void:
	if not card.get_meta("selected", false):
		return
	for corner: Array in [[Vector2.ONE, Vector2.ONE], [card.size - Vector2.ONE, -Vector2.ONE]]:
		card.draw_line(corner[0], corner[0] + Vector2(14 * corner[1].x, 0), HouseStyle.GOLD, 1.5, true)
		card.draw_line(corner[0], corner[0] + Vector2(0, 14 * corner[1].y), HouseStyle.GOLD, 1.5, true)


## Tab in reading order: the way back, the two track buttons, the lesson cards row by row, the reset link (while
## shown), and round again; the arrow keys keep the engine's neighbour search inside the grid.
func _chain() -> void:
	var stops: Array[Control] = [back]
	for key: String in _cards:
		stops.append(_cards[key][2])
	stops.append_array(_grid.find_children("Lesson*", "Button", true, false))
	if _reset.visible:
		stops.append(_reset)
	for i in stops.size():
		stops[i].focus_next = stops[i].get_path_to(stops[(i + 1) % stops.size()])
		stops[i].focus_previous = stops[i].get_path_to(stops[i - 1])
