class_name LearnPage
extends MenuPage
## "Learn to play": the two tracks, the classic tutorial and Trial by Fire, as cards in the left column: what the
## track is, how far the player is, the next lesson and one button that starts or continues it.

signal tutorial_requested(lesson_id: String)
signal scenario_requested(chapter: Dictionary)

var _cards: Dictionary = {}


## `returned`: the page was opened by a return from a lesson (Trial by Fire is selected then).
func setup(tutorial: TutorialProgress, trial: SpielschuleProgress, _returned: bool) -> LearnPage:
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
	return self


## One track card; the next lesson is the first that is not done and can be played (`playable`).
func _track(key: String, words: Array, lessons: Array, done: Array, playable: Array, request: Callable) -> void:
	var card := PanelContainer.new()
	card.name = key
	card.theme_type_variation = HouseStyle.PANEL_VARIANT
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
	box.add_child(button)
	left.add_child(card)
	_cards[key] = [card, next_label, button]
