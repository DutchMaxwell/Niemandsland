extends GdUnitTestSuite
## The lesson page of the main menu (step 48.6): two track cards, the classic tutorial and Trial by Fire, each
## with its progress and one button. Red before the step: there is no res://scripts/learn_page.gd.

const SCRIPT := "res://scripts/learn_page.gd"
const TUTORIAL_CFG := "user://learn_page_test_tutorial.cfg"
const TRIAL_CFG := "user://learn_page_test_trial.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(TUTORIAL_CFG)
	DirAccess.remove_absolute(TRIAL_CFG)


func _page(trial_done: int, tutorial_done: int) -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no learn page").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var tutorial := TutorialProgress.new(TUTORIAL_CFG)
	var track := TutorialFlow.ids(TutorialFlow.build_tool_track())
	for i in tutorial_done:
		tutorial.mark_lesson_completed(track[i])
	var trial := SpielschuleProgress.new(TRIAL_CFG)
	for i in trial_done:
		trial.mark_completed(Spielschule.ids()[i])
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var page: Control = (load(SCRIPT) as GDScript).new()
	page.call("setup", tutorial, trial, false)
	host.add_child(page)
	page.size = host.size
	await get_tree().process_frame
	return page


func _card(page: Control, key: String) -> Dictionary:
	var card := page.find_child(key, true, false) as Control
	var texts: Array = []
	for label: Label in card.find_children("*", "Label", true, false):
		texts.append(label.text)
	var button := card.find_children("*", "Button", true, false)[0] as Button
	return {"texts": texts, "button": button, "selected": bool(card.get_meta("selected", false))}


func test_nothing_done_reads_start() -> void:
	var page := await _page(0, 0)
	if page == null:
		return
	var classic := _card(page, "ClassicTrack")
	assert_str((classic.button as Button).text).is_equal("Start")
	assert_array(classic.texts).contains(["0 / 11 LESSONS", "NEXT: CAMERA & TABLE"])


func test_two_trial_lessons_done_continue_trial_by_fire_with_lesson_3() -> void:
	var page := await _page(2, 0)
	if page == null:
		return
	var trial := _card(page, "TrialTrack")
	assert_str((trial.button as Button).text).is_equal("Continue with lesson 3")
	assert_array(trial.texts).contains(["2 / 11 LESSONS", "NEXT: BRING YOUR ARMY"])
	var requested: Array = []
	page.connect("scenario_requested", func(chapter: Dictionary) -> void: requested.append(chapter.id))
	(trial.button as Button).pressed.emit()
	assert_array(requested).is_equal(["S-03"])


func test_all_done_says_so_and_is_disabled() -> void:
	var page := await _page(11, 11)
	if page == null:
		return
	for key: String in ["ClassicTrack", "TrialTrack"]:
		var button := _card(page, key).button as Button
		assert_str(button.text).is_equal("All lessons done - pick one to replay")
		assert_bool(button.disabled).is_true()


## Step 48.6b: exactly one track is selected - Trial by Fire once any of its lessons is done or after a return
## from a lesson, else the classic tutorial; its button is the gold one; a click on the other card selects it.
func test_one_track_is_selected_and_its_button_is_gold() -> void:
	var page := await _page(0, 0)
	if page == null:
		return
	assert_bool(_card(page, "ClassicTrack").selected).is_true()
	assert_bool(_card(page, "TrialTrack").selected).is_false()
	assert_str(String((_card(page, "ClassicTrack").button as Button).theme_type_variation)).is_equal(
		String(HouseStyle.PRIMARY))
	(_card(page, "TrialTrack").button as Button).grab_focus()
	assert_bool(_card(page, "TrialTrack").selected).is_true()
	assert_bool(_card(page, "ClassicTrack").selected).is_false()


func test_trial_progress_selects_trial_by_fire() -> void:
	var page := await _page(2, 0)
	if page == null:
		return
	assert_bool(_card(page, "TrialTrack").selected).is_true()
	assert_bool(_card(page, "ClassicTrack").selected).is_false()


func _lesson_cards(page: Control) -> Array:
	var grid := page.find_child("LessonGrid", true, false)
	return [] if grid == null else grid.find_children("Lesson*", "Button", true, false)


func _texts(node: Node) -> Array:
	var texts: Array = []
	for label: Label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and not label.text.is_empty():
			texts.append(label.text)
	return texts


## Step 48.7: the right panel lists the selected track's lessons as numbered cards, never by working code
## (red before: no grid).
func test_the_selected_track_shows_eleven_numbered_cards_without_working_codes() -> void:
	var page := await _page(2, 0)
	if page == null:
		return
	var cards := _lesson_cards(page)
	assert_int(cards.size()).is_equal(11)
	if cards.size() < 11:
		return
	assert_array(_texts(cards[8])).contains(["09", "Spellcasting"])
	assert_array(_texts(cards[0])).contains(["Done · replay"])
	var next := cards.filter(func(c: Node) -> bool: return _texts(c).has("Next lesson"))
	assert_int(next.size()).is_equal(1)
	assert_array(_texts(next[0])).contains(["03"])
	var codes := RegEx.create_from_string("[ST]-\\d\\d|S-SPELL|W\\d")
	for text: String in _texts(page):
		assert_object(codes.search(text)).override_failure_message("working code in " + text).is_null()
	var requested: Array = []
	page.connect("scenario_requested", func(chapter: Dictionary) -> void: requested.append(chapter.id))
	(cards[4] as Button).pressed.emit()
	assert_array(requested).is_equal(["S-05"])


func test_selecting_the_classic_track_shows_its_lessons() -> void:
	var page := await _page(2, 1)
	if page == null:
		return
	page.call("select", "ClassicTrack")
	var cards := _lesson_cards(page)
	assert_int(cards.size()).is_equal(11)
	if cards.is_empty():
		return
	assert_array(_texts(cards[0])).contains(["01", "Camera & table", "Done · replay"])
	var requested: Array = []
	page.connect("tutorial_requested", func(id: String) -> void: requested.append(id))
	(cards[1] as Button).pressed.emit()
	assert_array(requested).is_equal([TutorialFlow.ids(TutorialFlow.build_tool_track())[1]])


## Step 48.7b: a done lesson carries a drawn tick, the last Trial card spans two columns and reads "11 · FINALE",
## and the classic track's reset link empties its progress (red before: none of these).
func test_tick_finale_and_reset() -> void:
	var page := await _page(2, 1)
	if page == null:
		return
	await get_tree().process_frame
	var cards := _lesson_cards(page)
	assert_int(cards[0].find_children("Tick", "TextureRect", true, false).size()).is_equal(1)
	assert_int(cards[3].find_children("Tick", "TextureRect", true, false).size()).is_equal(0)
	var finale := cards[10] as Control
	assert_array(_texts(finale)).contains(["11 · FINALE", "FINALE"])
	var tag := finale.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text == "FINALE")
	assert_bool(not tag.is_empty() and (tag[0] as Node).get_parent() is PanelContainer) \
		.override_failure_message("FINALE is not a chip (sheet 07)").is_true()
	assert_float(finale.size.x).is_greater(1.9 * (cards[8] as Control).size.x)
	page.call("select", "ClassicTrack")
	var reset := page.find_child("ResetTutorial", true, false) as Button
	assert_object(reset).override_failure_message("no reset link").is_not_null()
	if reset == null:
		return
	reset.pressed.emit()
	assert_str((_card(page, "ClassicTrack").button as Button).text).is_equal("Start")
	page.call("select", "TrialTrack")
	assert_bool((page.find_child("ResetTutorial", true, false) as Control).visible).is_false()


## Step 48.10: Tab walks the page in reading order - the way back, the two track buttons, every lesson card, the
## reset link - and wraps (red before: the engine's own order jumps between the columns).
func test_tab_walks_the_page_in_reading_order() -> void:
	var page := await _page(2, 1)
	if page == null:
		return
	page.call("select", "ClassicTrack")
	await get_tree().process_frame
	var order: Array[String] = []
	var at := page.get("back") as Control
	for _i in 16:
		order.append(String(at.name))
		at = at.get_node(at.focus_next) if not at.focus_next.is_empty() else null
		if at == null:
			break
	var expected: Array[String] = ["WayBack", "ClassicTrackButton", "TrialTrackButton"]
	for i in 11:
		expected.append("Lesson%02d" % (i + 1))
	expected.append_array(["ResetTutorial", "WayBack"])
	assert_array(order).is_equal(expected)


## Sheet 07 (.ch.next): the next lesson's card has the lighter fill #253035, drawn (red before: the 10 % accent wash of a
## hovered row, never drawn - the card was darker than its neighbours, as the setup's cards before #3838).
func test_the_next_lesson_has_the_sheets_fill() -> void:
	var page := await _page(2, 1)
	if page == null:
		return
	await get_tree().process_frame
	page.call("select", "ClassicTrack")
	await get_tree().process_frame
	var next: Array = _lesson_cards(page).filter(func(c: Node) -> bool: return (c as Control).has_theme_stylebox_override(&"normal"))
	assert_int(next.size()).is_equal(1)
	if next.size() == 1:
		var box := (next[0] as Control).get_theme_stylebox(&"normal") as StyleBoxFlat
		assert_str(box.bg_color.to_html(false)).is_equal("253035")
		assert_bool(box.draw_center).is_true()
