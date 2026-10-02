extends GdUnitTestSuite
## A6 (Map editor plan): the coverage stats and the OPR guidelines sit in one house card; a met guideline
## reads green, a missed one amber, and the guideline text is unchanged.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func _scene_block(node_name: String) -> String:
	var text := FileAccess.get_file_as_string("res://scenes/map_layout.tscn")
	var start := text.find('[node name="%s"' % node_name)
	var end := text.find("\n[node ", start + 1)
	return text.substr(start, (end if end >= 0 else text.length()) - start)


func _inside_card(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != _ed:
		if p is PanelContainer and (p as PanelContainer).theme_type_variation == HouseStyle.CARD:
			return true
		p = p.get_parent()
	return false


func test_a6_stats_and_guidelines_sit_in_a_house_card() -> void:
	assert_bool(_inside_card(_ed.stats_label)).override_failure_message("A6 — StatsLabel not in a card").is_true()
	assert_bool(_inside_card(_ed.recommendations_label)).override_failure_message("A6 — RecommendationsLabel not in a card").is_true()


func test_a6_met_guidelines_read_green_and_missed_ones_amber_with_the_same_text() -> void:
	_ed._update_recommendations_with_values(18, 30.0, 60.0, 40.0, 40.0, 2)
	var rows := _ed.find_child("GuidelineRows", true, false)
	assert_object(rows).override_failure_message("A6 — no GuidelineRows").is_not_null()
	if rows == null:
		return
	var ok_rows := 0
	var bad_rows := 0
	var lines: Array = []
	for r: Label in rows.get_children():
		lines.append(r.text)
		if r.text.begins_with("✓"):
			ok_rows += 1
			assert_bool(r.get_theme_color("font_color") == HouseStyle.tone_ink(HouseStyle.TONE_OK)).is_true()
		elif r.text.begins_with("✗"):
			bad_rows += 1
			assert_bool(r.get_theme_color("font_color") == HouseStyle.WARN).is_true()
	assert_int(ok_rows).is_greater(0)
	assert_int(bad_rows).is_greater(0)  # the empty map misses the gap / symmetry guidelines
	var expected: Array = []
	for l: String in _ed.recommendations_label.text.split("\n"):
		if not l.strip_edges().is_empty():
			expected.append(l)
	assert_array(lines).is_equal(expected)


func test_a6_stats_labels_carry_no_paint_overrides() -> void:
	for n in ["StatsLabel", "RecommendationsLabel"]:
		assert_str(_scene_block(n)).not_contains("theme_override_")
	assert_bool(_ed.recommendations_label.has_theme_color_override("font_color")).is_false()
	assert_bool(_ed.stats_label.has_theme_color_override("font_color")).is_false()
