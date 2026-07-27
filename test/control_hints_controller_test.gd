extends GdUnitTestSuite
## Contextual control hints (UX polish): the PURE classify/hint helpers plus the dwell/hide flow.
## Every advertised key must stay a verified live binding — the curation lives in one constant.


func test_classify_kinds() -> void:
	assert_str(ControlHintsController.classify(true, true, true)).is_equal("regiment")
	assert_str(ControlHintsController.classify(true, false, true)).is_equal("unit")
	assert_str(ControlHintsController.classify(false, false, true)).is_equal("object")
	assert_str(ControlHintsController.classify(false, false, false)).is_equal("")


func test_every_kind_has_a_nonempty_curated_hint() -> void:
	for kind in ["regiment", "unit", "object"]:
		assert_bool(ControlHintsController.hint_for(kind).is_empty()) \
			.override_failure_message("missing hint for %s" % kind).is_false()
	assert_str(ControlHintsController.hint_for("")).is_equal("")
	assert_str(ControlHintsController.hint_for("no_such_kind")).is_equal("")


func test_hover_flow_dwell_then_show_then_instant_hide() -> void:
	var c: ControlHintsController = auto_free(ControlHintsController.new())
	add_child(c)
	var obj: Node3D = auto_free(Node3D.new())
	obj.add_to_group("selectable")
	add_child(obj)
	c.on_hover_changed(obj)
	# Not visible before the dwell elapses (no flicker while sweeping the cursor).
	assert_bool((c.get_node("ControlHints") as PanelContainer).visible).is_false()
	await get_tree().create_timer(ControlHintsController.DWELL_SEC + 0.1).timeout
	assert_bool((c.get_node("ControlHints") as PanelContainer).visible).is_true()
	# Hover end hides instantly.
	c.on_hover_changed(null)
	assert_bool((c.get_node("ControlHints") as PanelContainer).visible).is_false()
