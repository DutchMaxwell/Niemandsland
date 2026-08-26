extends GdUnitTestSuite
## NML-1078 / GH #363 — Discord playtest feedback: on a two-monitor PC the game opened on
## the SECOND monitor and could not be moved back; the fullscreen toggle did nothing because
## borderless fullscreen just covers whatever screen the window is already on. Fix: the
## window always starts on the PRIMARY monitor (project.godot initial_position_type=1), and
## GraphicsSettings.screen_index lets the player park it on another monitor deliberately.

var _screen_index_before: int
var _fullscreen_before: bool


func before_test() -> void:
	_screen_index_before = GraphicsSettings.screen_index
	_fullscreen_before = GraphicsSettings.fullscreen


func after_test() -> void:
	GraphicsSettings.screen_index = _screen_index_before
	GraphicsSettings.fullscreen = _fullscreen_before
	GraphicsSettings.save_settings()


## T1 — the window must open centred on the PRIMARY screen (type 1), not "screen under the
## mouse" (type 3, the reported cause: the mouse happened to be on the second monitor).
func test_initial_position_type_is_primary_screen_center() -> void:
	assert_int(ProjectSettings.get_setting("display/window/size/initial_position_type")).is_equal(1)


## T2 — screen_index round-trips through save/load like the other persisted settings.
func test_screen_index_round_trips_through_save_and_load() -> void:
	GraphicsSettings.screen_index = 1
	GraphicsSettings.save_settings()
	GraphicsSettings.screen_index = -1
	GraphicsSettings.load_settings()
	assert_int(GraphicsSettings.screen_index).is_equal(1)


## T3 — an out-of-range screen resolves to the primary screen without erroring, and does not
## silently flip fullscreen. On this (headless, single-screen) machine the window must end up
## on the primary screen.
func test_apply_screen_out_of_range_falls_back_to_primary() -> void:
	var fullscreen_before := GraphicsSettings.fullscreen
	GraphicsSettings.apply_screen(99)
	assert_bool(GraphicsSettings.fullscreen).is_equal(fullscreen_before)
	if DisplayServer.get_screen_count() >= 1:
		assert_int(DisplayServer.window_get_current_screen()).is_equal(DisplayServer.get_primary_screen())
