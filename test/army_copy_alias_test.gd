extends GdUnitTestSuite
## S8-U4: Ctrl+D (copy_to_clipboard + paste_from_clipboard) on army models must not make ALIAS copies.
## Node.duplicate() carries the model's game_unit / model_instance metas (and the opr_unit group) along, so
## the copy resolved to the ORIGINAL's ModelInstance and Delete on the copy parked the original. The copy is
## now a plain prop; deleting it is the hard delete (+ Ctrl+Z) and reports a tutorial "object deleted" event
## (T-03 "delete") because the park signals no longer fire for it.

const Director := preload("res://scripts/tutorial_director.gd")
const Flow := preload("res://scripts/tutorial_flow.gd")
const Progress := preload("res://scripts/tutorial_progress.gd")
const TEST_CFG := "user://test_army_copy_alias.cfg"


func after_test() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


## A loose army model wrapper the way OPRArmyManager / EquipmentDistributor build one.
func _army_model(unit: GameUnit, index: int) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	node.name = "Marine_%d" % index
	node.add_to_group("selectable")
	node.add_to_group("miniature")
	node.add_to_group("opr_unit")
	node.add_to_group("unit")
	node.set_meta("network_id", 100 + index)
	var model := ModelInstance.new()
	model.node = node
	model.unit = unit
	model.model_index = index
	model.wounds_max = 1
	model.wounds_current = 1
	unit.models.append(model)
	node.set_meta("model_instance", model)
	node.set_meta("game_unit", unit)
	node.set_meta("model_index", index)
	return node


func _manager() -> ObjectManager:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	return om


## Ctrl+D on `original`: exactly the two calls main.gd makes. Returns the pasted copy.
func _duplicate(om: ObjectManager, original: Node3D) -> Node3D:
	om._add_to_selection(original)
	om.copy_to_clipboard()
	om.paste_from_clipboard(Vector3(0.1, 0.0, 0.1))
	var selected := om.get_selected_objects()
	assert_int(selected.size()).is_equal(1)
	return selected[0]


func test_duplicate_of_an_army_model_is_not_an_alias() -> void:
	var om := _manager()
	var unit := GameUnit.new()
	var original := _army_model(unit, 0)
	add_child(original)

	var copy := _duplicate(om, original)

	assert_object(copy).is_not_same(original)
	assert_object(UnitUtils.get_model_instance(copy)).is_null()
	assert_object(UnitUtils.get_game_unit(copy)).is_null()
	assert_bool(copy.is_in_group("opr_unit")).is_false()
	# The original keeps its identity.
	assert_object(UnitUtils.get_model_instance(original)).is_same(unit.models[0])
	assert_object(UnitUtils.get_game_unit(original)).is_same(unit)
	assert_bool(original.is_in_group("opr_unit")).is_true()


func test_delete_on_the_duplicate_leaves_the_original_alive() -> void:
	var om := _manager()
	var unit := GameUnit.new()
	var original := _army_model(unit, 0)
	add_child(original)
	var copy := _duplicate(om, original)
	var rc: RadialMenuController = auto_free(RadialMenuController.new())

	rc.delete_objects([copy])

	# The original model is neither parked nor hidden; the copy is what went away.
	assert_bool(unit.models[0].is_alive).is_true()
	assert_int(unit.models[0].wounds_current).is_equal(1)
	assert_bool(original.visible).is_true()
	assert_bool(original.get_meta("deleted", false)).is_false()
	assert_bool(copy.visible).is_false()


func test_duplicate_of_a_regiment_tray_does_not_reach_the_original_unit() -> void:
	var om := _manager()
	var unit := GameUnit.new()
	unit.unit_properties = {"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true}
	var members: Array = []
	var footprints: Array = []
	for i in range(2):
		var member := _army_model(unit, i)
		add_child(member)
		members.append(member)
		footprints.append(Vector2(0.025, 0.025))
	var tray: RegimentTray = auto_free(RegimentTray.new())
	add_child(tray)
	tray.form(members, footprints, 2)
	tray.set_meta("regiment", Regiment.new(unit, tray, 2))
	tray.set_meta("network_id", 200)
	var rc: RadialMenuController = auto_free(RadialMenuController.new())

	var copy := _duplicate(om, tray)
	rc.delete_objects([copy])

	# The copy's models are plain props; deleting the copy tray never kills the original regiment.
	assert_bool(copy.has_meta("regiment")).is_false()
	for child in copy.get_children():
		assert_bool(child.has_meta("game_unit")).is_false()
		assert_bool(child.has_meta(RegimentTray.MEMBER_META)).is_false()
	for model in unit.models:
		assert_bool(model.is_alive).is_true()
		assert_bool(model.node.is_queued_for_deletion()).is_false()
	assert_bool(tray.is_queued_for_deletion()).is_false()


func test_deleting_a_plain_copy_emits_objects_deleted() -> void:
	var om := _manager()
	var unit := GameUnit.new()
	var original := _army_model(unit, 0)
	add_child(original)
	var copy := _duplicate(om, original)
	var rc: RadialMenuController = auto_free(RadialMenuController.new())
	assert_bool(rc.has_signal("objects_deleted")).is_true()
	var seen: Array = []
	rc.connect("objects_deleted", func(nodes: Array) -> void: seen.append(nodes))

	rc.delete_objects([copy])

	assert_int(seen.size()).is_equal(1)
	var reported: Array = seen[0] if not seen.is_empty() else []
	assert_array(reported).contains_exactly([copy])


func test_tutorial_delete_step_completes_when_the_duplicate_is_deleted() -> void:
	var director := auto_free(Director.new()) as TutorialDirector
	director.flow = Flow.new(Flow.build_tool_track())
	director.flow.start_at("T-03")
	director.progress = Progress.new(TEST_CFG)
	director.progress.load_from_disk()
	var rc: RadialMenuController = auto_free(RadialMenuController.new())
	director._radial_controller = rc
	director._connect_seams()
	# Walk T-03 up to the "delete" step with the real event names of the earlier steps.
	for event in [Flow.Event.UNIT_MOVED, Flow.Event.ROTATED, Flow.Event.ROTATED, Flow.Event.ROTATED,
			Flow.Event.ARRANGED, Flow.Event.ARRANGED, Flow.Event.PASTED, Flow.Event.LOCK_TOGGLED]:
		director._on_event(event)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("delete")

	var om := _manager()
	var unit := GameUnit.new()
	var original := _army_model(unit, 0)
	add_child(original)
	var copy := _duplicate(om, original)
	rc.delete_objects([copy])

	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("undo")
