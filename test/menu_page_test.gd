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
