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
