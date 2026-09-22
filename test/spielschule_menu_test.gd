extends GdUnitTestSuite
## Both teaching routes remain separately named and wired inside the Learn group.
func test_learn_group_exposes_both_distinct_routes() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	menu.view.buttons.LearnBtn.pressed.emit()
	assert_bool(menu.tutorial_btn.is_visible_in_tree()).is_true()
	assert_bool(menu.spielschule_btn.is_visible_in_tree()).is_true()
	assert_str(menu.tutorial_btn.description).contains("Klassisches Tutorial")
	assert_str(menu.spielschule_btn.text).contains("Feuertaufe")
	assert_str(menu.spielschule_btn.text).contains("In Entwicklung")
	assert_int(menu.spielschule_btn.get_index()).is_equal(menu.tutorial_btn.get_index()+1)
	assert_int(menu.spielschule_btn.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(menu.spielschule_btn.pressed.is_connected(menu._on_spielschule_pressed)).is_true()

func test_feuertaufe_still_opens_real_chapter_picker() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	menu.view.show_route("learn")
	menu.spielschule_btn.pressed.emit()
	var found := false
	for child in menu.get_children():
		if child is AcceptDialog and child.title == "FEUERTAUFE":
			found = child.visible
	assert_bool(found).is_true()
	assert_bool(menu.view.route_panel.visible).is_false()
