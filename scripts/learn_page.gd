class_name LearnPage
extends MenuPage
## "Learn to play": the two tracks, the classic tutorial and Trial by Fire, as cards in the left column: what the
## track is, how far the player is, the next lesson and one button that starts or continues it. Exactly one track is
## selected (gold rim and corners, NEXT in gold, its button gold with an Enter cap); a click on a card selects it.

signal tutorial_requested(lesson_id: String)
signal scenario_requested(chapter: Dictionary)

var _cards: Dictionary = {}


## `returned`: the page was opened by a return from a lesson (Trial by Fire is selected then).
func setup(tutorial: TutorialProgress, trial: SpielschuleProgress, returned: bool) -> LearnPage:
	eyebrow.text = "LEARN TO PLAY"
	title.text = "Find your starting point."
	var track := TutorialFlow.build_tool_track()
	var done: Array = track.map(func(l: Dictionary) -> bool: return tutorial.is_lesson_completed(str(l.id)))
	_track("ClassicTrack", ["CLASSIC TUTORIAL", "Learn the controls", "Camera, miniatures and tools, on a prepared table."],
		track, done, track.map(func(_l: Dictionary) -> bool: return true),
		func(_lesson: Dictionary) -> void: tutorial_requested.emit(""))
	var chapters := Spielschule.chapters()
	done = chapters.map(func(c: Dictionary) -> bool: return trial.is_completed(str(c.id)))
	_track("TrialTrack", ["TRIAL BY FIRE · IN DEVELOPMENT", "Short practice scenarios",
		"Eleven short lessons — play them in any order, replay any time."], chapters, done,
		chapters.map(Spielschule.is_available), func(chapter: Dictionary) -> void: scenario_requested.emit(chapter))
	select("TrialTrack" if returned or trial.any_completed(Spielschule.ids()) else "ClassicTrack")
	return self


## One track card; the next lesson is the first that is not done and can be played (`playable`).
func _track(key: String, words: Array, lessons: Array, done: Array, playable: Array, request: Callable) -> void:
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


## The selected card's two gold corner brackets (top left, bottom right), as on the menu's Continue card.
func _draw_corners(card: Control) -> void:
	if not card.get_meta("selected", false):
		return
	for corner: Array in [[Vector2.ONE, Vector2.ONE], [card.size - Vector2.ONE, -Vector2.ONE]]:
		card.draw_line(corner[0], corner[0] + Vector2(14 * corner[1].x, 0), HouseStyle.GOLD, 1.5, true)
		card.draw_line(corner[0], corner[0] + Vector2(0, 14 * corner[1].y), HouseStyle.GOLD, 1.5, true)
