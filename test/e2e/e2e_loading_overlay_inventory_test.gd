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
	# Sheet 06 (red on main: none of these parts): the wordmark, an optional title, the stage line and the per cent.
	var parts := ["_title", "_stage", "_percent"].filter(func(p: String) -> bool: return _overlay.get(p) == null)
	assert_array(parts).override_failure_message("full overlay parts missing: %s" % str(parts)).is_empty()
	if not parts.is_empty():
		return
	assert_object(_overlay.find_child("Wordmark", true, false)).is_not_null()
	assert_bool(_overlay._title.visible).override_failure_message("no title until one is set").is_false()
	_overlay.set_title("Urban ruins")
	assert_bool(_overlay._title.visible).is_true()
	_overlay.set_stage("Raising terrain")
	assert_str(_overlay._stage.text).is_equal("RAISING TERRAIN")
	_overlay._current = 0.62
	_overlay._process(0.0)
	assert_str(_overlay._percent.text).is_equal("62 %")
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
	assert_float(_overlay._fill.size.x).is_equal_approx(_overlay._current * _overlay._track_w(), 0.01)
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


func test_overlay_wears_the_house_style_in_both_modes() -> void:
	_overlay = await _make(false)
	assert_str(String(_overlay._label.theme_type_variation)).is_equal(String(HouseStyle.EYEBROW))
	var gradient := ((_overlay._fill as TextureRect).texture as GradientTexture1D).gradient
	assert_that(gradient.get_color(0)).is_equal(HouseStyle.ACCENT)   # the full bar runs accent to gold
	assert_that(gradient.get_color(1)).is_equal(HouseStyle.GOLD)
	var full := _overlay
	_overlay = await _make(true)
	assert_that((_overlay._fill as ColorRect).color).is_equal(HouseStyle.ACCENT)
	var panel := _overlay.find_children("*", "PanelContainer", true, false)[0] as PanelContainer
	assert_str(String(panel.theme_type_variation)).is_equal(String(HouseStyle.PANEL_VARIANT))
	assert_object(panel.theme).is_same(HouseStyle.theme())
	full.queue_free()
	assert_bool(FileAccess.get_file_as_string("res://scripts/loading_overlay.gd").contains("HudTokens")).is_false()


## Sheet 06 at the mockup's measures: a 760 px bar, a 56 px title, a 20 px subtitle, mono capitals for the stage line and the
## per cent, the signature rule under the wordmark, the legal line at the foot (red on main: 560 px, 44 px, no rule, no line).
func test_the_full_overlay_measures_as_sheet_06() -> void:
	_overlay = await _make(false)
	assert_float(_overlay._track_w()).is_equal(760.0)
	assert_int(_overlay._title.get_theme_font_size("font_size")).is_equal(56)
	assert_int(_overlay._subtitle.get_theme_font_size("font_size")).is_equal(20)
	for line: Label in [_overlay._stage, _overlay._percent]:
		assert_int(line.get_theme_font_size("font_size")).is_equal(14)
		assert_object(line.get_theme_font("font")).is_same(HouseStyle.mono())
	var rule := _overlay.find_child("SignatureRule", true, false) as Control
	assert_object(rule).override_failure_message("no signature rule under the wordmark").is_not_null()
	if rule != null:
		assert_float(rule.get_combined_minimum_size().x).is_equal(250.0)
	var legal := _overlay.find_child("LegalLine", true, false) as Label
	assert_object(legal).override_failure_message("no legal line").is_not_null()
	if legal != null:
		assert_bool(legal.uppercase).is_true()
		assert_str(legal.text).contains("OnePageRules")
	_overlay.free()
	_overlay = await _make(true)
	assert_float(_overlay._track_w()).is_equal(360.0)
	assert_object(_overlay.find_child("LegalLine", true, false)).override_failure_message("the compact panel shows the legal line").is_null()


## The loading picture names its stages as a row of marks under the subtitle: the ones before the stage in hand are done,
## it is gold, the rest pending; a text that is no stage leaves them; the plain and the compact overlay show none
## (sheet 06; red on main: no marks, no set_stages).
func test_stage_marks_follow_the_stage_in_hand() -> void:
	_overlay = await _make(false)
	assert_bool(_overlay.has_method("set_stages")).override_failure_message("no set_stages").is_true()
	if not _overlay.has_method("set_stages"):
		return
	assert_object(_overlay.find_child("StageMarks", true, false)).override_failure_message("marks without names").is_null()
	_overlay.set_stages(PackedStringArray(["Table", "Battlemap", "Terrain", "Miniatures"]))
	var states := func() -> Array: return _overlay._stage_marks.map(func(m: Control) -> int: return m.state)
	assert_array(states.call()).is_equal([1, 0, 0, 0])
	_overlay.set_stage("Terrain")
	assert_array(states.call()).is_equal([2, 2, 1, 0])
	assert_that(_overlay._stage_labels[2].get_theme_color("font_color")).is_equal(HouseStyle.GOLD)
	assert_that(_overlay._stage_labels[0].get_theme_color("font_color")).is_equal(HouseStyle.INK)
	assert_that(_overlay._stage_labels[3].get_theme_color("font_color")).is_equal(HouseStyle.MUTED)
	_overlay.set_stage("Waiting for the host")
	assert_array(states.call()).is_equal([2, 2, 1, 0])
	_overlay.set_stage("")
	assert_array(states.call()).is_equal([2, 2, 2, 2])
	_overlay.free()
	_overlay = await _make(true)
	_overlay.set_stages(PackedStringArray(["Table"]))
	assert_object(_overlay.find_child("StageMarks", true, false)).override_failure_message("the compact panel shows marks").is_null()


## One tip under the bar of the named loading picture, and only there: not on the plain overlay, not on the compact panel,
## not in a window lower than 800 px (sheet 06; red on main: no tip).
func test_the_named_overlay_shows_one_tip() -> void:
	_overlay = await _make(false)
	var card := _overlay.find_child("TipCard", true, false) as Control
	assert_object(card).override_failure_message("no tip card").is_not_null()
	if card == null:
		return
	assert_bool(card.visible).override_failure_message("a tip on the plain overlay").is_false()
	_overlay.set_title("Urban ruins")
	assert_bool(card.visible).is_equal(LoadingOverlay.tip_fits(_overlay.get_viewport().get_visible_rect().size.y))
	var words: Array[String] = []
	for l: Node in card.find_children("*", "Label", true, false):
		words.append((l as Label).text)
	assert_bool(words.has("AT THE TABLE")).is_true()
	# the "?" stands as a key cap between the tip's two parts; the picture's caption comes with the tip (sheet 06)
	assert_str(" ? ".join(words.slice(1).filter(func(w: String) -> bool: return w != "?"))).is_equal(LoadingOverlay.TIPS[0])
	var cap := card.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text == "?")
	assert_bool(not cap.is_empty() and String((cap[0] as Label).theme_type_variation) == String(HouseStyle.KEYCAP)).is_true()
	var caption := _overlay.find_child("PictureCaption", true, false) as Control
	assert_bool(caption != null and caption.visible == card.visible).override_failure_message("no picture caption").is_true()
	assert_bool(LoadingOverlay.tip_fits(1080.0)).is_true()
	assert_bool(LoadingOverlay.tip_fits(720.0)).is_false()
	_overlay.free()
	_overlay = await _make(true)
	assert_object(_overlay.find_child("TipCard", true, false)).override_failure_message("the compact panel shows a tip").is_null()


func test_inventory_check_names_a_removed_control() -> void:
	_overlay = await _make(false)
	assert_array(_missing(_overlay)).is_empty()
	var label := _overlay._label
	_overlay._label = null
	var missing := _missing(_overlay)
	_overlay._label = label
	assert_array(missing).contains_exactly(["label"])
