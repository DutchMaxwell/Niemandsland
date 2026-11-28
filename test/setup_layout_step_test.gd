extends GdUnitTestSuite
## Step 04's page (step 65.5): the folded rows of steps 01-03 and the heading.
## Red before the step: there is no res://scripts/setup_layout_step.gd.

const SCRIPT := "res://scripts/setup_layout_step.gd"

var _layout: SetupLayout


func _step(size_feet: Vector2, system := "gf") -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no step 04 page").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	_layout = auto_free(SetupLayout.new())
	add_child(_layout)
	_layout.set_table(size_feet, system)
	var step: Control = auto_free((load(SCRIPT) as GDScript).new())
	step.size = Vector2(1920, 1080)
	add_child(step)
	step.call("setup", _layout, ["Grimdark Future", "Urban ruins", "72 × 48 in", "Two players, one screen"])
	return step


func _way(step: Control, way: String) -> Button:
	return step.find_child("Way_" + way, true, false) as Button


func test_change_on_a_folded_row_asks_for_that_step() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var asked: Array = []
	step.connect("change_requested", func(index: int) -> void: asked.append(index))
	(step.find_child("Change2", true, false) as Button).pressed.emit()
	assert_array(asked).is_equal([2])


func test_the_folded_rows_show_the_values_of_steps_01_to_03() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var texts: Array = step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["01", "Game system", "Grimdark Future", "72 × 48 in", "Lay out the table"])


## Step 65.5b: the four ways as cards (red before: no cards).
func test_four_ways_and_the_default_is_chosen() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	for way: String in ["empty", "generated", "theme", "file"]:
		assert_object(_way(step, way)).override_failure_message(way).is_not_null()
	if _way(step, "empty") == null:
		return
	assert_bool(bool(_way(step, SetupLayout.DEFAULT_WAY).get_meta("chosen", false))).is_true()
	assert_bool(_way(step, "theme").disabled).is_false()


func test_the_ready_made_table_is_off_on_4_by_4_and_a_press_chooses_a_way() -> void:
	var step := _step(Vector2(4, 4))
	if step == null or _way(step, "theme") == null:
		fail("no way cards")
		return
	assert_bool(_way(step, "theme").disabled).is_true()
	_way(step, "generated").pressed.emit()
	assert_str(_layout.label()).is_equal("Auto-generated")
	assert_bool(bool(_way(step, "generated").get_meta("chosen", false))).is_true()
	assert_bool(bool(_way(step, "empty").get_meta("chosen", false))).is_false()


func _rail_texts(step: Control) -> Array:
	var rail := step.find_child("Rail", true, false)
	return [] if rail == null else rail.find_children("*", "Label", true, false).filter(
		func(l: Label) -> bool: return l.is_visible_in_tree())


## Step 65.6: the rail - the legend's counts add up to the facts line, a failing guideline line is shown in the warn
## colour, the empty table shows none, Create table asks to create (red before: no rail).
func test_the_rail_tells_the_layout() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	assert_object(step.find_child("Rail", true, false)).override_failure_message("no rail").is_not_null()
	if step.find_child("Rail", true, false) == null:
		return
	assert_bool(_rail_texts(step).any(func(l: Label) -> bool: return l.text.contains("terrain pieces"))).is_false()
	_layout.choose("generated")
	var labels := _rail_texts(step)
	var legend := 0
	for l: Label in labels:
		var m := RegEx.create_from_string("^(Ruins|Forest|Container|Dangerous) (\\d+)$").search(l.text)
		if m != null:
			legend += int(m.get_string(2))
	var facts := labels.filter(func(l: Label) -> bool: return l.text.contains(" PIECES · COVERAGE "))
	assert_int(facts.size()).is_equal(1)
	assert_int(int((facts[0] as Label).text.get_slice(" ", 0))).is_equal(legend)
	var guide := labels.filter(func(l: Label) -> bool: return l.text.contains("table coverage"))
	assert_int(guide.size()).is_equal(1)
	var ok: bool = (_layout.facts().lines as Array)[1].ok
	assert_object((guide[0] as Label).get_theme_color(&"font_color")).is_equal(HouseStyle.OK if ok else HouseStyle.WARN)
	var asked: Array = []
	step.connect("create_requested", func() -> void: asked.append(true))
	(step.find_child("CreateTable", true, false) as Button).pressed.emit()
	assert_array(asked).is_equal([true])


## Step 65.8: Generate again (only on the generated way), the mirror switch and the layout editor from the setup
## (red before: no tools).
func test_generate_again_mirror_and_the_editor() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var again := step.find_child("GenerateAgain", true, false) as Button
	assert_object(again).override_failure_message("no tools").is_not_null()
	if again == null:
		return
	assert_bool(again.disabled).is_true()
	_layout.choose("generated")
	assert_bool(again.disabled).is_false()
	var first := JSON.stringify(_layout.editor.placed_pieces)
	var changed := false
	for _i in 10:
		again.pressed.emit()
		changed = changed or JSON.stringify(_layout.editor.placed_pieces) != first
	assert_bool(changed).override_failure_message("ten presses gave the same layout").is_true()
	(step.find_child("Mirror", true, false) as BaseButton).toggled.emit(true)
	assert_bool(_layout.editor.point_symmetry_enabled).is_true()
	var pieces: int = _layout.facts().pieces
	(step.find_child("EditInEditor", true, false) as Button).pressed.emit()
	assert_bool(_layout.editor.visible).is_true()
	_layout.editor._on_close_pressed()
	assert_bool(_layout.editor.visible).is_false()
	assert_str(_layout.label()).is_equal("Edited layout")
	assert_int(_layout.facts().pieces).is_equal(pieces)


## Step 65.9: the deployment zones and the mission objectives on step 04, and the key legend (red before: none).
func test_zones_objectives_and_the_key_legend() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var front := step.find_child("ZoneFrontLine", true, false) as Button
	assert_object(front).override_failure_message("no zones card").is_not_null()
	if front == null:
		return
	front.pressed.emit()
	assert_int(_layout.editor.deployment_type).is_equal(1)
	var texts: Array = step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["Empty table · Front Line (12\")", "No objectives placed"])
	_layout.editor.mission_objectives.append(Vector2(12, 12))
	_layout.editor.mission_objectives.append(Vector2(60, 36))
	_layout.changed.emit()
	texts = step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["2 objectives placed", "generate again", "create table"])
	(step.find_child("DeployObjectives", true, false) as Button).pressed.emit()
	assert_bool(_layout.editor.visible).is_true()
	assert_bool(_layout.editor.objectives_editing).is_true()


func _sized_step(window: Vector2) -> Control:
	var step := _step(Vector2(6, 4))
	if step == null:
		return null
	step.size = window
	_layout.choose("generated")
	for _i in 3:
		await get_tree().process_frame
	return step


## Step 65.10: state two fits a 1280 x 720 window without scrolling; at 1920 x 1080 the way cards keep 196 px
## (red before: the page stood at its 1920 x 1080 places in every window).
func test_state_two_fits_a_720p_window() -> void:
	var step := await _sized_step(Vector2(1280, 720))
	if step == null:
		return
	var window := Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(1)
	for control: Control in step.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and control.get_global_rect().has_area():
			assert_bool(window.encloses(control.get_global_rect())).override_failure_message(
				"%s at %s" % [control.name, control.get_global_rect()]).is_true()
	var keys: Control = step.get("_keys")
	var left: Control = step.get("left")
	assert_float(keys.get_global_rect().position.y).override_failure_message("the key legend overlaps the left column"
		).is_greater_equal(left.get_global_rect().end.y)


func test_the_way_cards_keep_196_px_at_1080p() -> void:
	var step := await _sized_step(Vector2(1920, 1080))
	if step == null:
		return
	assert_float((step.find_child("Way_empty", true, false) as Control).size.y).is_greater_equal(196.0)


func test_a_folded_row_is_built_alone() -> void:
	var calls: Array = []
	var row: PanelContainer = auto_free(SetupLayoutStep.folded_row(4, "Opponent", "Two players, one screen",
		func() -> void: calls.append(4)))
	var texts: Array = row.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).is_equal(["04", "Opponent", "Two players, one screen"])
	(row.find_child("Change4", true, false) as Button).pressed.emit()
	assert_array(calls).is_equal([4])


## Spec 97 (step 97.8): "Lay out the table" is step 05 - the opponent (step 04) is the fourth folded row and has a
## rail row (red before: heading "04", three folded rows, no OPPONENT).
func test_lay_out_the_table_is_step_05_after_the_opponent() -> void:
	var step := _step(Vector2(6, 4))
	var texts: Array = step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["05", "Opponent", "OPPONENT", "Two players, one screen"])
	assert_int(texts.count("04")).is_equal(1)   # the folded row 04 (Opponent), no longer the heading
	var asked: Array = []
	step.connect("change_requested", func(index: int) -> void: asked.append(index))
	var change := step.find_child("Change4", true, false) as Button
	assert_object(change).override_failure_message("no folded row 04").is_not_null()
	if change != null:
		change.pressed.emit()
		assert_array(asked).is_equal([4])


## The chosen way card is as light as on sheet 03c (#253035, `.w.on`), not the never-drawn 10 % accent wash of a
## hovered row that left it darker than its neighbours (red before; the same cause as the opponent cards).
func test_the_chosen_way_card_has_the_sheets_fill() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	var box := _way(step, SetupLayout.DEFAULT_WAY).get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_str(box.bg_color.to_html(false)).is_equal("253035")
	assert_bool(box.draw_center).override_failure_message("the fill is not drawn").is_true()


## Gap review 27.11. (sheet 03c): at 1080p the deployment zones are a compact joined group at the left, and the cards
## of the page stand 14 px apart with 20 px inside (red before: three stretched buttons, 8 px gaps, 10 px inside).
func test_the_tools_and_zones_have_room_at_1080p() -> void:
	var step := _step(Vector2(6, 4))
	if step == null:
		return
	await get_tree().process_frame
	var none := step.find_child("ZoneNone", true, false) as Control
	var custom := step.find_child("ZoneCustom", true, false) as Control
	var group := none.get_parent() as Control
	assert_float(group.size.x).override_failure_message("the zones stretch across the card").is_less(group.get_parent().size.x * 0.8)
	assert_float(custom.get_global_rect().position.x - none.get_global_rect().end.x).is_less(200.0)
	assert_int((step.get("left") as Control).get_theme_constant(&"separation")).is_equal(14)
	var tools := (step.find_child("GenerateAgain", true, false) as Node).get_parent().get_parent() as PanelContainer
	assert_float(tools.get_theme_stylebox(&"panel").content_margin_left).is_equal(20.0)


## GEN-6: the board card - offered for gff on 4 x 4 ft, "New board" (and G) changes the code in the rail; gf has no
## card; off 4 x 4 ft the card is there but off.
@warning_ignore('unused_parameter')
func test_the_generated_board_card(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var step := _step(Vector2(4, 4), "gff")
	if step == null:
		return
	var card := _way(step, "board")
	assert_object(card).override_failure_message("no board card").is_not_null()
	if card == null:
		return
	assert_bool(card.visible and not card.disabled).is_true()
	card.pressed.emit()
	assert_str(_layout.way).is_equal("board")
	var again := step.find_child("GenerateAgain", true, false) as Button
	assert_str(again.text).is_equal("New board")
	var facts: Array = step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	var code := GeneratedBoard.code(_layout.board)
	assert_str(code).starts_with("TW-")
	assert_array(facts).contains(["BOARD " + code])
	assert_bool((step.find_child("CopyBoardCode", true, false) as Button).visible).is_true()
	assert_bool((step.find_child("ZoneCustom", true, false) as Button).visible).is_false()
	again.pressed.emit()
	assert_str(GeneratedBoard.code(_layout.board)).is_not_equal(code)
	_layout.set_table(Vector2(6, 4), "gff")
	assert_bool(card.visible and card.disabled).is_true()
	assert_str(_layout.way).is_equal("empty")
	var plain := _step(Vector2(4, 4), "gf")
	assert_bool(_way(plain, "board").visible).override_failure_message("gf was offered a board").is_false()


## GEN-13: the board card waits for its kit - downloading (a stub door says "waiting") -> off with the share in its caption;
## cached ("ready") -> on; not used in this run ("not_used": headless, low preset, Compatibility) -> on, nothing to wait for.
func test_the_board_card_waits_for_its_kit() -> void:
	var step := _step(Vector2(4, 4), "gff")
	if step == null or _way(step, "board") == null:
		return
	var card := _way(step, "board")
	var answer := {"state": "waiting", "pct": 37}
	var asked: Array = []
	step.set("kit_state", func(kit_theme: String) -> Dictionary:
		asked.append(kit_theme)
		return answer)
	step.call("poll_kit")
	assert_array(asked).contains(["tiefwerk"])
	assert_bool(card.disabled).override_failure_message("a board without its kit can be chosen").is_true()
	var texts: Array = card.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(texts).contains(["Downloading the board kit ... 37 %"])
	answer.merge({"state": "ready", "pct": 100}, true)   # in place: the stub holds this dictionary
	step.call("poll_kit")
	assert_bool(card.disabled).is_false()
	answer.merge({"state": "not_used", "pct": 100}, true)
	step.call("poll_kit")
	assert_bool(card.disabled).is_false()
