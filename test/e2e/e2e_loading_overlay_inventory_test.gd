extends GdUnitTestSuite
## E2E — the army loading bar, row 38 of the UI inventory (uimenus step 10): a centred label and an eased
## progress bar, determinate (set_progress) or indeterminate (creeps to 0.9), full-screen cover (owns the
## clicks) or compact panel (the rest stays clickable), fade out on completion, awaitable, frees itself.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

var _overlay: LoadingOverlay


func _make(compact: bool) -> LoadingOverlay:
	var o := LoadingOverlay.new()
	o.compact = compact
	add_child(o)
	await get_tree().process_frame
	return o


func after_test() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()


func _missing(o: LoadingOverlay) -> Array:
	var missing: Array = []
	if o._label == null:
		missing.append("label")
	if o._fill == null:
		missing.append("fill")
	if o._content == null:
		missing.append("content")
	return missing


func test_full_overlay_has_label_and_bar_and_owns_the_clicks() -> void:
	_overlay = await _make(false)
	assert_array(_missing(_overlay)).override_failure_message("loading overlay parts missing: %s" % str(_missing(_overlay))).is_empty()
	assert_int(_overlay._content.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int(_overlay.layer).is_equal(200)
	_overlay.set_label("BUILDING TABLE")
	assert_str(_overlay._label.text).is_equal("BUILDING TABLE")
	var covers := false
	for c in _overlay._content.get_children():
		if c is ColorRect and (c as ColorRect).color.a >= 0.99:
			covers = true
	assert_bool(covers).override_failure_message("the full-screen cover is missing").is_true()


func test_compact_overlay_leaves_the_rest_of_the_screen_clickable() -> void:
	_overlay = await _make(true)
	assert_int(_overlay._content.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for c in _overlay._content.get_children():
		assert_bool(c is ColorRect).override_failure_message("compact mode must not cover the screen").is_false()
	assert_bool(_overlay.find_children("*", "PanelContainer", true, false).size() > 0).is_true()


func test_progress_eases_toward_its_target_and_never_jumps() -> void:
	_overlay = await _make(false)
	_overlay.set_progress(0.5)
	for _i in 5:
		await get_tree().process_frame
	assert_float(_overlay._current).is_greater(0.0)
	assert_float(_overlay._current).is_less(0.5)
	assert_float(_overlay._fill.size.x).is_equal_approx(_overlay._current * LoadingOverlay.TRACK_W, 0.01)
	_overlay.set_progress(2.0)
	assert_float(_overlay._target).is_equal(1.0)


func test_indeterminate_creeps_but_never_past_the_cap() -> void:
	_overlay = await _make(false)
	_overlay.set_indeterminate(true)
	_overlay._process(100.0)
	assert_float(_overlay._target).is_equal(LoadingOverlay.CREEP_TARGET)
	_overlay.set_progress(0.2)
	_overlay._process(100.0)
	assert_float(_overlay._target).is_equal(0.2)


func test_complete_and_free_fills_fades_and_frees() -> void:
	_overlay = await _make(false)
	var o := _overlay
	o.complete_and_free()
	await get_tree().create_timer(0.1).timeout
	assert_float(o._target).is_equal(1.0)
	await get_tree().create_timer(1.0).timeout
	assert_bool(is_instance_valid(o) and not o.is_queued_for_deletion()).override_failure_message("the overlay did not free itself").is_false()


func test_fade_and_free_frees_without_forcing_100_percent() -> void:
	_overlay = await _make(true)
	var o := _overlay
	o.set_progress(0.3)
	o.fade_and_free()
	await get_tree().create_timer(0.8).timeout
	assert_bool(is_instance_valid(o) and not o.is_queued_for_deletion()).is_false()


func test_inventory_check_names_a_removed_control() -> void:
	_overlay = await _make(false)
	assert_array(_missing(_overlay)).is_empty()
	var label := _overlay._label
	_overlay._label = null
	var missing := _missing(_overlay)
	_overlay._label = label
	assert_array(missing).contains_exactly(["label"])
