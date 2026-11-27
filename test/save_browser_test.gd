extends GdUnitTestSuite
## The "Load game" sheet (menu step 48.2): one row per save of the folder, newest first, over a dimmed screen.
## Red before the step: there is no res://scripts/save_browser.gd.

const SCRIPT := "res://scripts/save_browser.gd"
const FIXTURE := "res://test/fixtures/continue_card/save_with_facts.nml"
const DIR := "user://save_browser_fixture"

var _host: Control


func before() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for file: String in ["first", "second", "third", "fourth"]:   # a second apart: mtimes are whole seconds
		FileAccess.open(DIR.path_join(file + ".nml"), FileAccess.WRITE).store_string(
			FileAccess.get_file_as_string(FIXTURE))
		await get_tree().create_timer(1.1).timeout


func after() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)


func before_test() -> void:
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	get_tree().root.add_child(_host)


func _open(dir: String) -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no save browser").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var browser: Control = (load(SCRIPT) as GDScript).new()
	browser.call("open", _host, dir)
	await get_tree().process_frame
	return browser


func _names(browser: Control) -> Array:
	var names: Array = []
	for row: Node in (browser.get("rows") as Node).get_children():
		names.append((row.find_children("*", "Label", true, false)[0] as Label).text)
	return names


func test_one_row_per_save_newest_first() -> void:
	var browser := await _open(DIR)
	if browser == null:
		return
	assert_array(_names(browser)).is_equal(["fourth", "third", "second", "first"])
	var sheet := browser.find_child("Sheet", true, false) as Control
	assert_vector(sheet.custom_minimum_size).is_equal(Vector2(1200, 780))


func test_a_row_load_button_requests_its_file() -> void:
	var browser := await _open(DIR)
	if browser == null:
		return
	var monitor := monitor_signals(browser, false)
	var first_row := (browser.get("rows") as Node).get_child(0)
	var load_button := first_row.find_children("*", "Button", true, false)[0] as Button
	assert_str(load_button.text).is_equal("Load")
	load_button.pressed.emit()
	await assert_signal(monitor).is_emitted("load_requested", [DIR.path_join("fourth.nml"), load_button])


func test_the_close_box_and_esc_close_the_sheet() -> void:
	for how: String in ["close", "esc"]:
		var browser := await _open(DIR)
		if browser == null:
			return
		var heard: Array = []
		browser.connect("closed", func() -> void: heard.append(how))
		if how == "close":
			(browser.find_child("CloseButton", true, false) as Button).pressed.emit()
		else:
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			browser.get_viewport().push_input(esc)
		await get_tree().process_frame
		assert_array(heard).is_equal([how])


## Step 48.2b: the fact line of a row is filled after the sheet is open, one save per frame (red before: no line).
func test_the_fact_line_is_filled_after_the_frames_have_run() -> void:
	var browser := await _open(DIR)
	if browser == null:
		return
	for _i in 5:
		await get_tree().process_frame
	var facts := (browser.get("rows") as Node).get_child(0).find_child("Facts", true, false) as Label
	assert_object(facts).override_failure_message("no fact line").is_not_null()
	if facts != null:
		assert_str(facts.text).is_equal("GRIMDARK FUTURE · ROUND 3 · GRASSLAND · 6 x 4 FT")


func test_an_empty_folder_says_so() -> void:
	var browser := await _open("user://save_browser_empty")
	if browser == null:
		return
	var texts: Array = []
	for label: Label in browser.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			texts.append(label.text)
	assert_array(texts).contains(["No saved games yet.", "Games you save at the table appear here."])
