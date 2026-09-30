extends GdUnitTestSuite
## E2E — the model download progress panel, row 39 of the UI inventory (uimenus step 10): a centred modal that
## owns its clicks, the label "LOADING ARMY", a 320 x 18 progress bar without a percentage that glides toward
## the done count, and hides when the download finishes. While the army loading overlay is up, the same
## events feed that overlay instead (its own test is the row 38 suite). Real main.tscn.
## test_inventory_check_names_a_missing_part proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _missing() -> Array:
	var missing: Array = []
	if _main._cache_progress_panel == null:
		return ["panel"]
	if _main._cache_progress_label == null:
		missing.append("label")
	if _main._cache_progress_bar == null:
		missing.append("bar")
	return missing


func test_download_panel_shows_label_and_a_bar_that_owns_its_clicks() -> void:
	_main._on_model_caching_started(5)
	await _runner.simulate_frames(2)
	assert_array(_missing()).is_empty()
	var panel: Control = _main._cache_progress_panel
	assert_bool(panel.visible).is_true()
	assert_int(panel.mouse_filter).override_failure_message("the modal must own its clicks").is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(_main._cache_progress_label.text).is_equal("LOADING ARMY")
	var bar: ProgressBar = _main._cache_progress_bar
	assert_float(bar.max_value).is_equal(5.0)
	assert_float(bar.value).is_equal(0.0)
	assert_bool(bar.show_percentage).is_false()
	assert_float(bar.custom_minimum_size.x).is_equal(320.0)
	assert_float(bar.custom_minimum_size.y).is_equal(18.0)
	var centre := panel.get_global_rect().get_center()
	var vp := panel.get_viewport_rect().size
	assert_float(absf(centre.x - vp.x * 0.5)).override_failure_message("not centred horizontally").is_less(vp.x * 0.05)
	assert_float(absf(centre.y - vp.y * 0.5)).override_failure_message("not centred vertically").is_less(vp.y * 0.05)


func test_progress_glides_toward_the_done_count_and_finish_hides_the_panel() -> void:
	_main._on_model_caching_started(4)
	_main._on_model_caching_progress(2, 4)
	await get_tree().create_timer(0.7).timeout
	assert_float(_main._cache_progress_bar.value).is_equal_approx(2.0, 0.05)
	_main._on_model_caching_progress(4, 4)
	await get_tree().create_timer(0.7).timeout
	assert_float(_main._cache_progress_bar.value).is_equal_approx(4.0, 0.05)
	_main._on_model_caching_finished()
	assert_bool(_main._cache_progress_panel.visible).is_false()


func test_a_zero_total_is_clamped_to_one() -> void:
	_main._on_model_caching_started(0)
	assert_float(_main._cache_progress_bar.max_value).is_equal(1.0)


func test_inventory_check_names_a_missing_part() -> void:
	_main._on_model_caching_started(3)
	assert_array(_missing()).is_empty()
	var bar: ProgressBar = _main._cache_progress_bar
	_main._cache_progress_bar = null
	var missing := _missing()
	_main._cache_progress_bar = bar
	assert_array(missing).contains_exactly(["bar"])
