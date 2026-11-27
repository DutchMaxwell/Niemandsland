extends GdUnitTestSuite
## Both teaching tracks stay reachable and separately named: "Learn to play" opens the
## lesson page with the classic tutorial and Trial by Fire as two cards; a return from a
## lesson opens it on Trial by Fire.


func test_learn_page_shows_both_tracks() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	menu.view.buttons.LearnBtn.pressed.emit()
	var page: LearnPage = menu.view.page_open
	assert_object(page).is_not_null()
	for key: String in ["ClassicTrack", "TrialTrack"]:
		assert_bool((page.find_child(key, true, false) as Control).is_visible_in_tree()).is_true()
	var texts: Array = []
	for label: Label in page.find_children("*", "Label", true, false):
		texts.append(label.text)
	assert_array(texts).contains(["CLASSIC TUTORIAL", "TRIAL BY FIRE · IN DEVELOPMENT"])
	assert_bool(menu.view.route_panel.visible).is_false()


## The page's two requests reach the menu's launchers (the launch swaps the scene: not run).
func test_the_page_requests_reach_the_menus_launchers() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	menu.view.buttons.LearnBtn.pressed.emit()
	var page: LearnPage = menu.view.page_open
	assert_bool(page.tutorial_requested.is_connected(menu._launch_tutorial)).is_true()
	assert_bool(page.scenario_requested.is_connected(menu._launch_scenario)).is_true()


func test_a_return_from_a_lesson_opens_the_page_on_trial_by_fire() -> void:
	var before: Variant = ProjectSettings.get_setting("niemandsland/open_game_school", false)
	ProjectSettings.set_setting("niemandsland/open_game_school", true)
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	await runner.simulate_frames(2)
	var page: LearnPage = runner.scene().view.page_open
	ProjectSettings.set_setting("niemandsland/open_game_school", before)
	assert_object(page).is_not_null()
	if page == null:
		return
	var trial := page.find_child("TrialTrack", true, false) as Control
	assert_bool(bool(trial.get_meta("selected", false))).is_true()
