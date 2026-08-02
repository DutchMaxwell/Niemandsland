extends GdUnitTestSuite
## The Game School start-menu ENTRY exists in scenes/startup_menu.tscn, right after the Tutorial
## entry, as a MenuListButton reading "SPIELSCHULE (IN ARBEIT)". Instantiate-only (never in tree) so
## this asserts what the .tscn stores — what a future .tscn edit would break — without running the
## menu's heavy _ready() (diorama build, music, attract mode). Same pattern as ui_click_ownership_test.

const MENU_SCENE := "res://scenes/startup_menu.tscn"
const BTN_PATH := "SafeArea/Columns/LeftColumn/MenuButtons/SpielschuleBtn"


func _menu() -> Control:
	return auto_free(load(MENU_SCENE).instantiate()) as Control


func test_game_school_entry_exists_and_is_a_menu_list_button() -> void:
	var btn := _menu().get_node_or_null(BTN_PATH)
	assert_object(btn) \
		.override_failure_message("startup_menu.tscn must carry a SpielschuleBtn in the MenuButtons column") \
		.is_not_null()
	assert_bool(btn is MenuListButton).is_true()
	# E3b (01.08.): the label used to read "FEUERTAUFE — TUTORIAL" and sat directly under an entry
	# reading "TUTORIAL" — which is how TC-058 ended up reporting the new course from inside the old
	# one. Both entries say what they are now, and this one says plainly that it is unfinished.
	# The course keeps its name; only the MENU LABEL changed. "Feuertaufe" lives on in the chapter
	# content, and the finale is still "Ins Niemandsland — face NACHTMAHR".
	# The counterpart assertion for the other entry is in test/startup_menu_test.gd.
	assert_str((btn as Button).text).is_equal("SPIELSCHULE (IN ARBEIT)")


func test_game_school_entry_sits_right_after_the_tutorial_entry() -> void:
	var buttons := _menu().get_node("SafeArea/Columns/LeftColumn/MenuButtons")
	var tutorial := buttons.get_node("TutorialBtn")
	var spielschule := buttons.get_node("SpielschuleBtn")
	assert_int(spielschule.get_index()).is_equal(tutorial.get_index() + 1)


func test_menu_buttons_are_stop_surfaces_so_clicks_never_leak_to_the_table() -> void:
	# The new entry is a plain Button (default MOUSE_FILTER_STOP), so it owns its own clicks — the
	# click-ownership invariant (test/ui_click_ownership_test.gd) holds for it with no extra work.
	var btn := _menu().get_node(BTN_PATH) as Button
	assert_int(btn.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
