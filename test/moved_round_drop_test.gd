extends GdUnitTestSuite

const MAIN := preload("res://scripts/main.gd")


func _fixture() -> Dictionary:
	var main: Node3D = auto_free(MAIN.new())
	var objects: ObjectManager = auto_free(ObjectManager.new())
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var unit: GameUnit = auto_free(GameUnit.new())
	unit.unit_id = "own_unit"
	unit.unit_properties = {"player_id": 1, "name": "Own Unit"}
	var model: Node3D = auto_free(Node3D.new())
	model.set_meta("game_unit", unit)
	objects._selected_objects = [model]
	main.object_manager = objects
	main.opr_army_manager = army
	return {"main": main, "objects": objects, "army": army, "unit": unit, "model": model}


func test_plain_click_in_play_does_not_mark_unit_moved() -> void:
	var f := _fixture()
	(f["army"] as OPRArmyManager).start_game()
	(f["main"] as Node3D)._on_unit_moved()
	assert_bool((f["unit"] as GameUnit).unit_properties.has("moved_round")).is_false()


func test_deployment_drag_does_not_mark_round_one_move() -> void:
	var f := _fixture()
	assert_bool((f["army"] as OPRArmyManager).is_deployment_phase()).is_true()
	(f["main"] as Node3D)._on_units_dropped([{"node": f["model"], "inches": 4.0}])
	(f["main"] as Node3D)._on_unit_moved()
	assert_bool((f["unit"] as GameUnit).unit_properties.has("moved_round")).is_false()


func test_only_moved_unit_is_stamped_during_play() -> void:
	var f := _fixture()
	var other: GameUnit = auto_free(GameUnit.new())
	other.unit_id = "selected_but_still"
	other.unit_properties = {"player_id": 1, "name": "Selected But Still"}
	var other_model: Node3D = auto_free(Node3D.new())
	other_model.set_meta("game_unit", other)
	(f["objects"] as ObjectManager)._selected_objects.append(other_model)
	(f["army"] as OPRArmyManager).start_game()
	(f["main"] as Node3D)._on_units_dropped([{"node": f["model"], "inches": 4.0}])
	(f["main"] as Node3D)._on_unit_moved()
	assert_int(int((f["unit"] as GameUnit).unit_properties.get("moved_round", -1))).is_equal(1)
	assert_bool(other.unit_properties.has("moved_round")).is_false()


func test_takeback_restores_previous_moved_round_stamp() -> void:
	var f := _fixture()
	var main := f["main"] as Node3D
	var unit := f["unit"] as GameUnit
	var model := f["model"] as Node3D
	var trails: MoveTrails = auto_free(MoveTrails.new())
	var undo: UndoManager = auto_free(UndoManager.new())
	main.move_trails = trails
	main.undo_manager = undo
	(f["army"] as OPRArmyManager).start_game()
	model.global_position = Vector3(0.2, 0, 0)
	var moves := [{"node": model, "from": Vector3.ZERO, "to": model.global_position,
		"from_raw": Vector3.ZERO, "from_rot": 0.0, "inches": 0.2 / 0.0254,
		"path": PackedVector2Array([Vector2.ZERO, Vector2(0.2, 0)]),
		"radius_m": 0.0125, "drop_id": 1}]
	main._on_trails_dropped(moves, true)
	main._on_units_dropped(moves)
	assert_int(int(unit.unit_properties.get("moved_round", -1))).is_equal(1)
	assert_str(undo.undo_for(0)).contains("Take back")
	assert_bool(unit.unit_properties.has("moved_round")).is_false()
	assert_vector(model.global_position).is_equal(Vector3.ZERO)
