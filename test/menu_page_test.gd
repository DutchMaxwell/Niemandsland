extends GdUnitTestSuite
## The page skeleton of the main menu (step 48.5): the lesson page and the online hub stand on it.
## Red before the step: there is no res://scripts/menu_page.gd.

const SCRIPT := "res://scripts/menu_page.gd"


func _page() -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no menu page").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var page: Control = (load(SCRIPT) as GDScript).new()
	host.add_child(page)
	page.size = host.size
	await get_tree().process_frame
	return page


func test_the_page_has_its_way_back_and_its_two_columns() -> void:
	var page := await _page()
	if page == null:
		return
	assert_str((page.get("back") as Button).text).is_equal("Main menu")
	var right := page.get("right") as Control
	assert_float(right.position.x).is_equal(640.0)
	assert_float(right.position.x + right.size.x).is_equal(1920.0 - 64.0)
	assert_object(page.get("left")).is_not_null()


func test_the_way_back_and_esc_close_the_page() -> void:
	var page := await _page()
	if page == null:
		return
	var heard: Array = []
	page.connect("closed", func() -> void: heard.append("closed"))
	(page.get("back") as Button).pressed.emit()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	page.get_viewport().push_input(esc)
	await get_tree().process_frame
	assert_array(heard).is_equal(["closed", "closed"])


## Step 48.5b: the menu shows a page in place of its list and brings the list back (red before: no open_page).
func test_the_menu_opens_a_page_in_place_of_its_list_and_returns() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var view: Control = runner.scene().view
	assert_bool(view.has_method("open_page")).override_failure_message("no open_page").is_true()
	if not view.has_method("open_page"):
		return
	var learn := view.buttons.LearnBtn as Control
	learn.grab_focus()
	var page: Control = (load(SCRIPT) as GDScript).new()
	view.call("open_page", page)
	await runner.simulate_frames(2)
	for key: String in ["_scroll", "_footer", "news_card", "_masthead"]:
		assert_bool((view.get(key) as Control).visible).override_failure_message(key + " shown").is_false()
	assert_object(view.get_viewport().gui_get_focus_owner()).is_same(page.get("back"))
	runner.simulate_key_pressed(KEY_ESCAPE)
	await runner.simulate_frames(2)
	assert_bool(is_instance_valid(page) and page.is_inside_tree()).is_false()
	assert_array(runner.scene().find_children("*", "PromptCard", true, false)).is_empty()   # Esc is not Quit here
	assert_bool((view.get("_scroll") as Control).visible).is_true()
	assert_object(view.get_viewport().gui_get_focus_owner()).is_same(learn)
	view.call("show_route", "help")
	assert_bool(view.route_panel.visible).is_true()


## Sheets 02 and 07: the header breathes - 26 px from the way back to the eyebrow, 22 px from the title to the column
## (red before: 10 px each, the way back glued to the eyebrow).
func test_the_header_has_the_sheets_rhythm() -> void:
	var page := await _page()
	if page == null:
		return
	(page.get("eyebrow") as Label).text = "LEARN TO PLAY"
	(page.get("title") as Label).text = "Find your starting point."
	(page.get("left") as Control).add_child(Control.new())
	await get_tree().process_frame
	await get_tree().process_frame
	var back := (page.get("back") as Control).get_parent() as Control
	var eyebrow := page.get("eyebrow") as Control
	var title := page.get("title") as Control
	var left := page.get("left") as Control
	assert_float(eyebrow.get_global_rect().position.y - back.get_global_rect().end.y).is_between(24.0, 28.0)
	assert_float(left.get_global_rect().position.y - title.get_global_rect().end.y).is_between(20.0, 24.0)
